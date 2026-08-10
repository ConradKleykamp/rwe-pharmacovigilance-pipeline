-- Medication history & adherence.
-- Tracks each patient's fill history per drug and flags treatment gaps.
-- Adherence is assessed per patient+drug pair (not per patient overall) — a gap
-- of more than 30 days between one fill's stop and the next fill's start for the
-- same patient/drug is treated as a lapse in treatment. See README's "A note on
-- framing" section for why 30 days was chosen.
--
-- Scoped to oral tablets with 5+ total fills: injectables/gels (e.g. dental
-- fluoride gel, IV antibiotics given during an inpatient stay) are administered
-- episodically, not taken continuously at home, so a multi-year "gap" between
-- them is normal, not non-adherence. Requiring 5+ fills further excludes
-- coincidental one-off prescriptions (e.g. two unrelated antibiotic courses
-- years apart) from being mistaken for a lapsed continuous therapy.

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

-- total_fills = COUNT(*) + 1 because previous_stop IS NULL (the patient's first
-- fill of this drug) was already filtered out below, so COUNT(*) alone would be
-- one short of the true number of fills.
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
