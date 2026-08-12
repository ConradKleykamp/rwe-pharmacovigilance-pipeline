-- Query #1: Medication history & adherence

-- Tracks each patient's fill history per drug and flags treatment gaps.
-- Adherence is assessed per patient+drug pair (not per patient overall)
-- A "lapse in treatment" is represented as a gap of more than 30 days between one fill's stop and the next fill's start
-- See README's "A note on framing" section for why 30 days was chosen.

-- Scope: oral tablets with 5+ total fills
-- Injectables/gels (e.g. dental fluoride gel, IV antibiotics given during an inpatient stay) are administered episodically
-- These are not taken continuously at home, so a multi-year gap between treatments would be normal (not non-adherence)
-- Requiring 5+ fills further excludes coincidental one-off prescriptions (e.g. two unrelated antibiotic courses taken 5 years apart)

-- CTE 1: medication_gaps
-- For each patient+drug pair, ordered by fill start date, LAG pulls previous fill's stop onto the current row
-- First fill of any pair gets previous_stop = NULL (nothing to lag from), handled in next CTE
-- Window function: LAG(med.stop)
WITH medication_gaps AS (
    SELECT
        med.patient_id,
        med.code,
        med.description,
        med.start,
        LAG(med.stop) OVER (PARTITION BY med.patient_id, med.code ORDER BY med.start) AS previous_stop,
        med.start::DATE - LAG(med.stop) OVER (PARTITION BY med.patient_id, med.code ORDER BY med.start)::DATE AS gap_days
    FROM medications med
    WHERE med.description ILIKE '%Oral Tablet%'
),

-- CTE 2: patient_drug_summary
-- Handles first NULL previous stop from CTE 1
-- Finds worst gap seen for that patient/drug
patient_drug_summary AS (
    SELECT
        gaps.patient_id,
        gaps.code,
        gaps.description,
        COUNT(*) + 1 AS total_fills,
        MAX(gaps.gap_days) AS max_gap_days,
        BOOL_OR(gaps.gap_days > 30) AS has_treatment_gap
    FROM medication_gaps gaps
    WHERE gaps.previous_stop IS NOT NULL
    GROUP BY gaps.patient_id, gaps.code, gaps.description
)

-- Joins to patients for gender
-- Applies total_fills >= 5 filter
-- Labels each row adherent/non-adherent via has_treatment_gap boolean
-- Ordered to show worst lapses first
SELECT
    pat.id AS patient_id,
    pat.gender,
    summary.description AS medication,
    summary.total_fills,
    summary.max_gap_days,
    CASE WHEN summary.has_treatment_gap THEN 'non-adherent' ELSE 'adherent' END AS adherence_status
FROM patient_drug_summary summary
JOIN patients pat ON summary.patient_id = pat.id
WHERE summary.total_fills >= 5
ORDER BY summary.max_gap_days DESC;
