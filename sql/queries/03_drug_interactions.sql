-- Query #3: Drug Interaction Flags

-- Synthea does not encode contraindications between medications
-- This query models two proxies
-- 1) A way to classify drugs into clinically meaningful groups
-- 2) A reference table saying which groups are dangerous together (known interacting drug classes)
-- Uses drug names found in this dataset only

-- Classified by ingredient name (ILIKE on description) rather than by `code`
-- The same drug has a different RxNorm code per dose/form (e.g. simvastatin has 4 codes in this data)

-- CTE 1: classified_medications
-- Bucketing every medication into a drug class by ingredient name
WITH classified_medications AS (
    SELECT
        med.patient_id,
        med.id AS medication_id,
        med.description,
        med.start,
        med.stop,
        CASE
            WHEN med.description ILIKE '%warfarin%' THEN 'anticoagulant'
            WHEN med.description ILIKE '%clopidogrel%' THEN 'antiplatelet'
            WHEN med.description ILIKE '%ibuprofen%'
              OR med.description ILIKE '%naproxen%'
              OR med.description ILIKE '%aspirin%' THEN 'NSAID'
            WHEN med.description ILIKE '%lisinopril%'
              OR med.description ILIKE '%enalapril%'
              OR med.description ILIKE '%ramipril%' THEN 'ACE_inhibitor'
            WHEN med.description ILIKE '%diazepam%'
              OR med.description ILIKE '%lorazepam%'
              OR med.description ILIKE '%clonazepam%' THEN 'benzodiazepine'
            WHEN med.description ILIKE '%hydrocodone%'
              OR med.description ILIKE '%oxycodone%'
              OR med.description ILIKE '%tramadol%' THEN 'opioid'
            WHEN med.description ILIKE '%verapamil%' THEN 'calcium_channel_blocker'
            WHEN med.description ILIKE '%simvastatin%'
              OR med.description ILIKE '%atorvastatin%' THEN 'statin'
        END AS drug_class
    FROM medications med
),

-- CTE 2: relevant_medications
-- Only classified rows can ever participate in a known interaction
-- Filtering out unclassified drugs; prevents the need for fully joining medications table on itself
relevant_medications AS (
    SELECT *
    FROM classified_medications
    WHERE drug_class IS NOT NULL
),

-- CTE 3: interacting_pairs
-- Curated reference table of known interacting drug pairs
interacting_pairs (class_a, class_b, interaction_risk) AS (
    VALUES
        ('anticoagulant', 'NSAID', 'Increased bleeding risk'),
        ('antiplatelet', 'NSAID', 'Increased bleeding risk'),
        ('ACE_inhibitor', 'NSAID', 'Reduced antihypertensive/renal effect'),
        ('benzodiazepine', 'opioid', 'Increased respiratory depression risk'),
        ('calcium_channel_blocker', 'statin', 'Increased myopathy/rhabdomyolysis risk')
)

-- Joining relevant_medications to itself
-- Joining to patients for gender
SELECT
    pat.id AS patient_id,
    pat.gender,
    med_a.description AS medication_a,
    med_a.drug_class AS drug_class_a,
    med_b.description AS medication_b,
    med_b.drug_class AS drug_class_b,
    pairs.interaction_risk
FROM relevant_medications med_a
JOIN relevant_medications med_b
    ON med_a.patient_id = med_b.patient_id
    -- avoids self-pairs and a mirrored duplicate of every pair (A,B)/(B,A)
    AND med_a.medication_id < med_b.medication_id
JOIN interacting_pairs pairs
    ON (med_a.drug_class = pairs.class_a AND med_b.drug_class = pairs.class_b)
    OR (med_a.drug_class = pairs.class_b AND med_b.drug_class = pairs.class_a)
JOIN patients pat ON med_a.patient_id = pat.id
-- active windows overlap; NULL stop means still active (open-ended)
WHERE (med_b.stop IS NULL OR med_a.start <= med_b.stop)
  AND (med_a.stop IS NULL OR med_b.start <= med_a.stop)
ORDER BY pairs.interaction_risk, pat.id;
