-- Drug interaction flags.
-- Synthea does not encode contraindications between medications (see README's
-- "A note on framing"). This project defines a small, hand-curated reference
-- table of known interacting drug classes, built from established clinical
-- knowledge, using only drug names that actually appear in this dataset —
-- documented as curated domain data, not derived from Synthea.
--
-- Classified by ingredient name (ILIKE on description) rather than by `code`:
-- the same drug has a different RxNorm code per dose/form (e.g. simvastatin
-- alone has 4 codes in this data), so matching on the human-readable name is
-- more robust than listing every code.

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

-- Only classified rows can ever participate in a known interaction, so
-- filtering here keeps the self-join below small instead of joining the
-- full medications table against itself.
relevant_medications AS (
    SELECT *
    FROM classified_medications
    WHERE drug_class IS NOT NULL
),

-- Curated reference: known-interacting drug class pairs. Order within each
-- row doesn't matter — the self-join below matches on either ordering.
interacting_pairs (class_a, class_b, interaction_risk) AS (
    VALUES
        ('anticoagulant', 'NSAID', 'Increased bleeding risk'),
        ('antiplatelet', 'NSAID', 'Increased bleeding risk'),
        ('ACE_inhibitor', 'NSAID', 'Reduced antihypertensive/renal effect'),
        ('benzodiazepine', 'opioid', 'Increased respiratory depression risk'),
        ('calcium_channel_blocker', 'statin', 'Increased myopathy/rhabdomyolysis risk')
)

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
