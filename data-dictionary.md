# Data Dictionary

This document describes every table and column in the PostgreSQL schema
(`sql/01_schema.sql`), the Synthea source column each one came from, and any
business rules or design decisions behind it. Columns present in the raw Synthea
CSVs but not carried into the schema are listed at the end of each table's section,
with the reason they were dropped.

---

## `patients`

Demographic and cohort-definition table. One row per synthetic patient. Source: `data/synthea/patients.csv`.

| Column | Type | Nullable | Source column | Notes |
|---|---|---|---|---|
| `id` | `VARCHAR(36)` | No | `Id` | Synthea-generated UUID, reused as-is (primary key) |
| `birthdate` | `DATE` | No | `BIRTHDATE` | |
| `deathdate` | `DATE` | Yes | `DEATHDATE` | `NULL` = patient still alive in the simulation |
| `marital` | `VARCHAR(1)` | Yes | `MARITAL` | `M`/`S`/`D`/`W`; blank for patients too young to have a marital status recorded |
| `race` | `VARCHAR(20)` | No | `RACE` | Fixed vocabulary: asian, black, hawaiian, native, other, white |
| `ethnicity` | `VARCHAR(20)` | No | `ETHNICITY` | hispanic / nonhispanic |
| `gender` | `VARCHAR(1)` | No | `GENDER` | `M`/`F` |
| `city`, `state`, `county` | `VARCHAR(100)` | Yes | same | |
| `zip` | `VARCHAR(10)` | Yes | `ZIP` | Stored as text to preserve leading zeros (e.g. `00000`) |
| `lat`, `lon` | `NUMERIC` | Yes | `LAT`, `LON` | Geographic coordinates |
| `healthcare_expenses`, `healthcare_coverage`, `income` | `NUMERIC(10,2)` | Yes | same | Dollar amounts |

**Dropped columns**: `SSN`, `DRIVERS`, `PASSPORT`, `PREFIX`, `FIRST`, `MIDDLE`, `LAST`, `SUFFIX`, `MAIDEN`, `BIRTHPLACE`, `ADDRESS`. These are direct patient identifiers or name fields, not needed for analysis. `FIPS` (county FIPS code) is redundant with `county`, which is already captured, and is blank in 1,489 of 5,727 rows. It isn't used by any of the three analysis queries.

---

## `encounters`

One row per healthcare encounter. Every other event table (conditions, medications, and so on) joins back to a specific encounter here. Source: `data/synthea/encounters.csv`.

| Column | Type | Nullable | Source column | Notes |
|---|---|---|---|---|
| `id` | `VARCHAR(36)` | No | `Id` | Synthea UUID (primary key) |
| `patient_id` | `VARCHAR(36)` | No | `PATIENT` | Foreign key → `patients.id` |
| `start`, `stop` | `TIMESTAMP` | No / Yes | `START`, `STOP` | Full timestamp preserved (source includes time-of-day); no blank `STOP` values found in the data |
| `encounterclass` | `VARCHAR(20)` | No | `ENCOUNTERCLASS` | ambulatory, wellness, outpatient, emergency, urgentcare, inpatient, home, virtual, snf, hospice |
| `description` | `TEXT` | Yes | `DESCRIPTION` | What the visit was for |
| `reasondescription` | `TEXT` | Yes | `REASONDESCRIPTION` | |

**Dropped columns**: `ORGANIZATION`, `PROVIDER`, `PAYER`, `CODE`, `REASONCODE`, `BASE_ENCOUNTER_COST`, `TOTAL_CLAIM_COST`, `PAYER_COVERAGE`. These are billing, claims, and provider details, out of scope per the project README.

---

## `conditions`

Diagnoses and comorbidities. One row per condition recorded during an encounter. Source: `data/synthea/conditions.csv`. Not queried by the three Phase 2 analysis queries. It was loaded and validated in Phase 1 for completeness, not because a query needs it.

| Column | Type | Nullable | Source column | Notes |
|---|---|---|---|---|
| `id` | `BIGSERIAL` | No | *(no source column, surrogate key)* | Source has no `Id` column; auto-incrementing key added because the natural key (patient + encounter + code + start) isn't guaranteed unique across the full table |
| `patient_id` | `VARCHAR(36)` | No | `PATIENT` | FK → `patients.id` |
| `encounter_id` | `VARCHAR(36)` | No | `ENCOUNTER` | FK → `encounters.id` |
| `start`, `stop` | `DATE` | No / Yes | `START`, `STOP` | `NULL` stop = condition still active |
| `code` | `VARCHAR(20)` | No | `CODE` | SNOMED-CT code. Kept alongside `description` because filtering on a code is more reliable than filtering on text; see the note below |
| `description` | `VARCHAR(100)` | No | `DESCRIPTION` | Max observed length 78 chars |

**Dropped columns**: `SYSTEM`. Every row has the same value (`SNOMED-CT`), so it carries no information.

**Data quality note**: this table is dominated by administrative and social entries, not just clinical diagnoses. The most frequent entries are "Medication review due," "Stress," "Full-time/Part-time employment," and social-isolation findings, well ahead of actual diagnoses like sinusitis or bronchitis. Any cohort or comorbidity query on this table should filter by `code` deliberately, rather than assuming the most common `description` values reflect how sick the population is.

---

## `medications`

Drug exposure, dosing, and dispensing history. One row per medication order/dispensing event. Source: `data/synthea/medications.csv`.

| Column | Type | Nullable | Source column | Notes |
|---|---|---|---|---|
| `id` | `BIGSERIAL` | No | *(no source column, surrogate key)* | Same reasoning as `conditions.id`. 432 duplicate rows were found on the 4-column natural key |
| `patient_id` | `VARCHAR(36)` | No | `PATIENT` | FK → `patients.id` |
| `encounter_id` | `VARCHAR(36)` | No | `ENCOUNTER` | FK → `encounters.id` |
| `code` | `VARCHAR(20)` | No | `CODE` | RxNorm code |
| `description` | `TEXT` | No | `DESCRIPTION` | Drug name/dose/form; max observed length 288 chars |
| `start`, `stop` | `TIMESTAMP` | No / Yes | `START`, `STOP` | `NULL` stop = medication still active |
| `dispenses` | `INTEGER` | Yes | `DISPENSES` | Refill count; used in the adherence query |
| `reasoncode` | `VARCHAR(20)` | Yes | `REASONCODE` | Condition code this medication was prescribed for |
| `reasondescription` | `TEXT` | Yes | `REASONDESCRIPTION` | |

**Dropped columns**: `PAYER`, `BASE_COST`, `PAYER_COVERAGE`, `TOTALCOST`. Billing detail, out of scope.

---

## `observations`

Labs, vitals, and survey results. One row per recorded observation. Source: `data/synthea/observations.csv`. This is the largest table (~4M rows). Not queried by the three Phase 2 analysis queries (adherence, adverse events, drug interactions). It was loaded and validated in Phase 1 for completeness, not because a query needs it.

| Column | Type | Nullable | Source column | Notes |
|---|---|---|---|---|
| `id` | `BIGSERIAL` | No | *(no source column, surrogate key)* | Same reasoning as `conditions.id`. 9,672 duplicate rows were found on the 4-column natural key |
| `patient_id` | `VARCHAR(36)` | No | `PATIENT` | FK → `patients.id` |
| `encounter_id` | `VARCHAR(36)` | **Yes** | `ENCOUNTER` | FK → `encounters.id`. About 155,000 rows have no encounter value in the source, likely historical readings not tied to a specific visit. This is the only table where the encounter FK is optional |
| `date` | `TIMESTAMP` | No | `DATE` | |
| `category` | `VARCHAR(20)` | Yes | `CATEGORY` | laboratory, survey, vital-signs, social-history, exam, procedure, imaging, therapy |
| `code` | `VARCHAR(20)` | No | `CODE` | LOINC code |
| `description` | `TEXT` | No | `DESCRIPTION` | |
| `value_numeric` | `NUMERIC` | Yes | `VALUE` | Populated when the source `TYPE` is `numeric` |
| `value_text` | `TEXT` | Yes | `VALUE` | Populated when the source `TYPE` is `text`; max observed length 135 chars |
| `units` | `VARCHAR(20)` | Yes | `UNITS` | Max observed length 16 chars |

**Dropped columns**: `TYPE`. It isn't stored directly. Instead, during ETL, it determines which of `value_numeric` or `value_text` gets populated for each row. Splitting the source's single mixed-type `VALUE` column into two typed columns means later queries can do arithmetic on lab values without needing to cast text.

---

## `careplans`

Care plan / therapy context. One row per care plan assigned to a patient. Source: `data/synthea/careplans.csv`. Not queried by the three Phase 2 analysis queries. It was loaded and validated in Phase 1 for completeness, not because a query needs it.

| Column | Type | Nullable | Source column | Notes |
|---|---|---|---|---|
| `id` | `VARCHAR(36)` | No | `Id` | Synthea UUID (primary key) |
| `patient_id` | `VARCHAR(36)` | No | `PATIENT` | FK → `patients.id` |
| `encounter_id` | `VARCHAR(36)` | No | `ENCOUNTER` | FK → `encounters.id` |
| `start`, `stop` | `DATE` | No / Yes | `START`, `STOP` | `NULL` stop = care plan still active |
| `description` | `VARCHAR(100)` | No | `DESCRIPTION` | Max observed length 80 chars |
| `reasondescription` | `VARCHAR(100)` | Yes | `REASONDESCRIPTION` | e.g. prediabetes, essential hypertension, CHF |

**Dropped columns**: `CODE`, `REASONCODE`. These are raw SNOMED codes for the care plan and its reason. None of the three analysis queries need to join on them, so the human-readable `description`/`reasondescription` text is enough here.

---

## `allergies`

Medication and environmental allergy history. One row per recorded allergy/intolerance, with up to two reactions flattened into the same row. Source: `data/synthea/allergies.csv`. Not queried by the three Phase 2 analysis queries. It was loaded and validated in Phase 1 for completeness, not because a query needs it.

| Column | Type | Nullable | Source column | Notes |
|---|---|---|---|---|
| `id` | `BIGSERIAL` | No | *(no source column, surrogate key)* | Same reasoning as `conditions.id`. No duplicates were found on the natural key here, but this keeps the table consistent with the other event tables |
| `patient_id` | `VARCHAR(36)` | No | `PATIENT` | FK → `patients.id` |
| `encounter_id` | `VARCHAR(36)` | No | `ENCOUNTER` | FK → `encounters.id` |
| `start`, `stop` | `DATE` | No / Yes | `START`, `STOP` | `STOP` is blank in all 5,504 rows. Every recorded allergy is still active in the simulation, so a `NULL` stop is normal here, not an exception |
| `code` | `VARCHAR(20)` | No | `CODE` | |
| `description` | `TEXT` | No | `DESCRIPTION` | Allergen name |
| `type` | `VARCHAR(20)` | Yes | `TYPE` | allergy / intolerance |
| `category` | `VARCHAR(20)` | Yes | `CATEGORY` | environment, food, medication. `medication` is the relevant subset for medication-safety analysis |
| `reaction1`, `reaction2` | `VARCHAR(20)` | Yes | `REACTION1`, `REACTION2` | SNOMED codes for up to two reactions |
| `description1`, `description2` | `TEXT` | Yes | `DESCRIPTION1`, `DESCRIPTION2` | |
| `severity1`, `severity2` | `VARCHAR(20)` | Yes | `SEVERITY1`, `SEVERITY2` | MILD / MODERATE / SEVERE |

**Dropped columns**: `SYSTEM`. Every row has the same value (`Unknown`), so it carries no information.

**Design note**: the source flattens up to two reactions per allergy into side-by-side columns instead of one row per reaction. This was kept as-is rather than split into a separate reactions table, since none of the three analysis queries need to join on individual reactions.
