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