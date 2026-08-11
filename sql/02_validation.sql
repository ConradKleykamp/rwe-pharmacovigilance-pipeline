-- Data validation for the RWE / pharmacovigilance pipeline
-- Runs after scripts/load_data.py
-- Data has already passed the constraints in 01_schema.sql
-- However, the validation checks search for data that may still be logically wrong
-- Each violation is inserted into validation_log rather than failing the script
-- reports/validation_report.md summarizes these findings

-- Validation log of anything flagging as logically wrong
CREATE TABLE validation_log (
    id                 BIGSERIAL PRIMARY KEY,
    check_name         VARCHAR(100) NOT NULL,
    table_name         VARCHAR(50) NOT NULL,
    record_id          TEXT,
    issue_description  TEXT NOT NULL,
    detected_at        TIMESTAMP NOT NULL DEFAULT now()
);

-- Completeness: rows that are allowed to be empty but shouldn't be at this rate
-- 1) observations: a lab or vital-sign reading with no unit is suspicious
-- Verified beforehand, only 0.2% of these rows are missing units, so this is a genuine minority
-- 2) medications (not included here): active medications with NULL reasoncode/reasondescription
-- Verified beforehand, 59% of active medications have no reasoncode, the empty field is a normal characteristic

-- Flagging lab/vital-sign observations with a NULL units
INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'missing_units_on_measurement',
    'observations',
    obs.id::TEXT,
    'Lab/vital-sign observation (' || obs.code || ' - ' || obs.description || ') has no units recorded'
FROM observations obs
WHERE obs.category IN ('laboratory', 'vital-signs')
  AND obs.units IS NULL;

-- Consistency: logically contradictory data across fields/tables
-- 1) patients: death recorded before birth
-- 2) any table with start/stop: stop < start (conditions, medications, careplans, encounters)
-- 3) encounters: encounters.start occuring after the patient's deathdate

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

-- conditions: stop date before start date
INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'stop_before_start',
    'conditions',
    cond.id::TEXT,
    'Stop (' || cond.stop || ') is before start (' || cond.start || ')'
FROM conditions cond
WHERE cond.stop IS NOT NULL
  AND cond.stop < cond.start;

-- medications: stop date before start date
INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'stop_before_start',
    'medications',
    med.id::TEXT,
    'Stop (' || med.stop || ') is before start (' || med.start || ')'
FROM medications med
WHERE med.stop IS NOT NULL
  AND med.stop < med.start;

-- careplans: stop date before start date
INSERT INTO validation_log (check_name, table_name, record_id, issue_description)
SELECT
    'stop_before_start',
    'careplans',
    careplan.id,
    'Stop (' || careplan.stop || ') is before start (' || careplan.start || ')'
FROM careplans careplan
WHERE careplan.stop IS NOT NULL
  AND careplan.stop < careplan.start;

-- encounters: stop date before start date
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

-- Plausibility: values outside realistic bounds.
-- 1) patients: negative dollar amounts (income, healthcare expenses/coverage)
-- 2) patients: age > 120
-- 3) observations: vital signs checked against logical physiological bounds

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
