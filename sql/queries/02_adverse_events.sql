-- Query #2: Adverse Event Identification

-- Adverse event proxy: an inpatient or emergency encounter that overlaps a patient's active medication window
-- Synthea data has no adverse event flag, so this is a modeled signal

-- This query is NOT restricted to oral tablets
-- This query instead measures concurrent drug exposure during a hospitalization
-- In other words, polypharmacy as an adverse event risk factor, which applies to all drugs

-- Grain: one row per patient, medication, encounter, e.g. a hospitalization with 3 active medications produces 3 rows
-- "Which drugs show up most often near hospitalizations"

-- CTE 1: medication_encounter_overlap
-- Finding a medication that was active during an encounter when it was NOT prescribed
WITH medication_encounter_overlap AS (
    SELECT
        enc.id AS encounter_id,
        enc.patient_id,
        enc.encounterclass,
        enc.start AS encounter_start,
        med.code AS medication_code,
        med.description AS medication_description
    FROM encounters enc
    JOIN medications med ON med.patient_id = enc.patient_id
    WHERE enc.encounterclass IN ('inpatient', 'emergency')
      -- Exclude the encounter that started this medication (that would be the prescribing visit)
      AND med.encounter_id != enc.id
      -- Medication must have been active on the encounter's start date
      -- NULL med.stop means still active (open-ended), so no upper bound
      AND enc.start >= med.start
      AND (med.stop IS NULL OR enc.start <= med.stop)
),

-- CTE 2: encounter_severity
-- Severity proxy: concurrent active-medication count per encounter.
-- Thresholds follow the standard pharmacoepidemiology definition of polypharmacy (5+ concurrent medications)
encounter_severity AS (
    SELECT
        overlap.encounter_id,
        overlap.patient_id,
        overlap.encounterclass,
        overlap.encounter_start,
        overlap.medication_code,
        overlap.medication_description,
        COUNT(*) OVER (PARTITION BY overlap.encounter_id) AS concurrent_medication_count
    FROM medication_encounter_overlap overlap
)

-- Joins to patients for gender
-- CASE buckets concurrent_medication_count into low/polypharmacy/excessive polypharmacy
-- Ordered so the highest-risk (most concurrent drugs) encounters surface first
SELECT
    pat.id AS patient_id,
    pat.gender,
    sev.encounter_id,
    sev.encounterclass,
    sev.encounter_start,
    sev.medication_code,
    sev.medication_description,
    sev.concurrent_medication_count,
    CASE
        WHEN sev.concurrent_medication_count >= 10 THEN 'excessive polypharmacy'
        WHEN sev.concurrent_medication_count >= 5 THEN 'polypharmacy'
        ELSE 'low'
    END AS severity
FROM encounter_severity sev
JOIN patients pat ON sev.patient_id = pat.id
ORDER BY sev.concurrent_medication_count DESC, sev.encounter_start;
