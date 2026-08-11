-- Adverse event identification.
-- Adverse event proxy (see README's "A note on framing"): an inpatient or
-- emergency encounter that overlaps a patient's active medication window.
-- Synthea has no adverse-event flag, so this is a modeled signal, not a
-- literal report.
--
-- Unlike 01_medication_history.sql, this is NOT restricted to oral tablets.
-- That query measured adherence, a concept that only applies to drugs taken
-- continuously at home. This query measures concurrent drug exposure during
-- a hospitalization (polypharmacy as an adverse-event risk factor), which
-- applies just as much to an injectable or IV medication as an oral one.
--
-- Grain: one row per (patient, medication, encounter) — a hospitalization
-- with 3 concurrently active medications produces 3 rows, one flagging each
-- implicated drug, so downstream analysis can ask "which drugs show up most
-- often near hospitalizations."

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
      -- exclude the encounter that started this medication (that's the
      -- prescribing visit, not a hospitalization caused by being on it)
      AND med.encounter_id != enc.id
      -- medication must have been active on the encounter's start date;
      -- NULL med.stop means still active (open-ended), so no upper bound
      AND enc.start >= med.start
      AND (med.stop IS NULL OR enc.start <= med.stop)
),

-- Severity proxy: concurrent active-medication count per encounter.
-- Thresholds follow the standard pharmacoepidemiology definition of
-- polypharmacy (5+ concurrent medications), not an invented cutoff.
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
