# Schema Approach

## Keys
- patients, encounters, careplans all have existing primary/natural keys (Id) generated from Synthea
- conditions, observations, medications, allergies DO NOT; they are just event rows (patient + encounter + code + dates)
- two possible methods to of joining these datasets:
  - surrogate key: synthetic primary key; add a Id column to the 4 tables without primary keys; simpler approach
  - natural composite key: use a combination of existing columns (e.g., patient_id + encounter_id + code...) as primary key
    - FINDING: natural key (patient + encounter + code + start/date) finds 432 duplicates in medications and 9133 duplicates in observations
- CONCLUSION: surrogate keys for conditions, observations, medications, allergies

## Datetime Formatting
- Intuition: ensure full ISO8601 formatting for all datetime columns; preserve timestamps where applicable (e.g., encounters.START/STOP)

## Column Datatypes
- ensuring IDs and codes are identifiers, not numbers --> VARCHAR
- known-bounded/categorical fields (e.g., codes, state, gender) --> VARCHAR; allow tight sizing, e.g. VARCHAR(12) for ETHNICITY at nonhispanic (11 chars)
- descriptive fields --> TEXT

## Dropping Personal Identifiers
- SSN, drivers, passport, prefix, first, middle, last, suffix, maiden, birthplace, address
- although the data is synthetic, these fields are not essential for this project and would likely be excluded in a real world study to ensure HIPAA/ethical compliances


# ETL Approach

## Loading Data
- one function per table (load_patients, load_encounters, etc.)
- each function reads the provided CSV --> cleans/transforms/writes to Postgres
- main() function runs them in same dependency order as the schema
- pandas .to_sql()
- chunked batch insert (instead of row-by-row)
- Loading is logged, one line per table

## Cleaning/Transforming Data
- empty fields in CSV must explicitly be converted to blanks (None) before loading; NaN can be written as a literal string by Postgres
- observations.VALUE becomes value_numeric or value_text depending on rows TYPE
- surrogate key tables do not receive id column from pandas; BIGSERIAL will accomplish this later


# Validation Approach

## Completeness
  - rows missing something the schema allows to be blank but shouldn't usually be
  - 1) observations
    - category in ('laboratory', 'vital-signs') but units row is NULL (a lab/vital reading with no unit is suspicious)
  - 2) medications
    - instinct: active medications with NULL reasoncode/reasondescription
    - FINDING: 59% of active medications have no reasoncode; the empty field is just a normal characteristic of the data

## Consistency
  - logically contradictory data across fields/tables
  - 1) patients
    - deathdate < birthdate (impossible)
  - 2) any table with start/stop --> stop < start (conditions, medications, careplans, encounters)
  - 3) encounters
    - encounters.start occurring AFTER the patient's deathdate

## Plausibility
  - values outside realistic bounds
  - 1) patients
    - income < 0, healthcare_expenses < 0, healthcare_coverage < 0
  - 2) patients 
    - age > 120 (deathdate - birthdate)
  - 3) observations
    - vital-sign codes checked against logical physiological bounds
    - Ex: 8302-2 --> body height outside of 0-300 cm range

# TO DO
- review all new added code/scripts, add comments
- explain query #1
  