-- Data validation for the RWE / pharmacovigilance pipeline.
-- Run after scripts/load_data.py. Every check below is structurally valid data
-- (it already passed the constraints in 01_schema.sql) that may still be
-- logically wrong. Each check inserts its violations into validation_log rather
-- than failing the script, so reports/validation_report.md can summarize findings
-- after the fact instead of the run stopping at the first problem.

CREATE TABLE validation_log (
    id                 BIGSERIAL PRIMARY KEY,
    check_name         VARCHAR(100) NOT NULL,
    table_name         VARCHAR(50) NOT NULL,
    record_id          TEXT,
    issue_description  TEXT NOT NULL,
    detected_at        TIMESTAMP NOT NULL DEFAULT now()
);

-- ============================================================
-- Completeness: data that's technically allowed to be NULL but
-- usually shouldn't be, at the rate it actually occurs here.
-- ============================================================

-- observations: a lab or vital-sign reading with no unit is suspicious.
-- Verified beforehand: only 0.2% of these rows are missing units, so this
-- check flags a genuine minority, not the norm.
INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'missing_units_on_measurement',
    'observations',
    obs.id::TEXT,
    'Lab/vital-sign observation (' || obs.code || ' - ' || obs.description || ') has no units recorded'
FROM observations obs
WHERE obs.category IN ('laboratory', 'vital-signs')
  AND obs.units IS NULL;

-- ============================================================
-- Consistency: fields that contradict each other, none of it
-- caught by foreign keys or NOT NULL constraints.
-- ============================================================

-- patients: death recorded before birth
INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'deathdate_before_birthdate',
    'patients',
    pat.id,
    'Deathdate (' || pat.deathdate || ') is before birthdate (' || pat.birthdate || ')'
FROM patients pat
WHERE pat.deathdate IS NOT NULL
  AND pat.deathdate < pat.birthdate;

-- stop date before start date, checked per table (each has its own start/stop pair)
INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'stop_before_start',
    'conditions',
    cond.id::TEXT,
    'Stop (' || cond.stop || ') is before start (' || cond.start || ')'
FROM conditions cond
WHERE cond.stop IS NOT NULL
  AND cond.stop < cond.start;

INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'stop_before_start',
    'medications',
    med.id::TEXT,
    'Stop (' || med.stop || ') is before start (' || med.start || ')'
FROM medications med
WHERE med.stop IS NOT NULL
  AND med.stop < med.start;

INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'stop_before_start',
    'careplans',
    careplan.id,
    'Stop (' || careplan.stop || ') is before start (' || careplan.start || ')'
FROM careplans careplan
WHERE careplan.stop IS NOT NULL
  AND careplan.stop < careplan.start;

INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'stop_before_start',
    'encounters',
    enc.id,
    'Stop (' || enc.stop || ') is before start (' || enc.start || ')'
FROM encounters enc
WHERE enc.stop IS NOT NULL
  AND enc.stop < enc.start;

-- encounters: a visit recorded after the patient's own death date
INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'encounter_after_death',
    'encounters',
    enc.id,
    'Encounter start (' || enc.start::DATE || ') is after patient deathdate (' || pat.deathdate || ')'
FROM encounters enc
JOIN patients pat ON enc.patient_id = pat.id
WHERE pat.deathdate IS NOT NULL
  AND enc.start::DATE > pat.deathdate;

-- ============================================================
-- Plausibility: values outside realistic bounds.
-- ============================================================

-- patients: negative dollar amounts (income, healthcare expenses/coverage)
INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'negative_dollar_amount',
    'patients',
    pat.id,
    CASE
        WHEN pat.income < 0 THEN 'income is negative (' || pat.income || ')'
        WHEN pat.healthcare_expenses < 0 THEN 'healthcare_expenses is negative (' || pat.healthcare_expenses || ')'
        WHEN pat.healthcare_coverage < 0 THEN 'healthcare_coverage is negative (' || pat.healthcare_coverage || ')'
    END
FROM patients pat
WHERE pat.income < 0
   OR pat.healthcare_expenses < 0
   OR pat.healthcare_coverage < 0;

-- patients: implausible age at death (over 120 years)
INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'implausible_age_at_death',
    'patients',
    pat.id,
    'Age at death is ' || ROUND((pat.deathdate - pat.birthdate) / 365.25, 1) || ' years'
FROM patients pat
WHERE pat.deathdate IS NOT NULL
  AND (pat.deathdate - pat.birthdate) > (120 * 365.25);

-- observations: Body Height (LOINC 8302-2) outside a plausible human range
INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'implausible_height',
    'observations',
    obs.id::TEXT,
    'Body Height value ' || obs.value_numeric || ' ' || COALESCE(obs.units, '') || ' is outside 0-300cm'
FROM observations obs
WHERE obs.code = '8302-2'
  AND (obs.value_numeric < 0 OR obs.value_numeric > 300);

-- observations: Pain severity (LOINC 72514-3) outside its defined 0-10 scale
INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'implausible_pain_severity',
    'observations',
    obs.id::TEXT,
    'Pain severity value ' || obs.value_numeric || ' is outside the 0-10 scale'
FROM observations obs
WHERE obs.code = '72514-3'
  AND (obs.value_numeric < 0 OR obs.value_numeric > 10);
