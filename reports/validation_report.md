# Validation Report

Written using the findings printed by `scripts/validate_data.py`, which queries `validation_log` (populated by `sql/02_validation.sql`) and the source tables directly.

Every check targets data that is structurally valid (it already satisfied the constraints in `sql/01_schema.sql`) but may still be logically wrong in ways constraints can't catch. See `data-dictionary.md` for the schema these rows loaded into.

## Rows loaded

| Table | Rows |
|---|---|
| `patients` | 5,727 |
| `encounters` | 327,233 |
| `conditions` | 199,635 |
| `medications` | 264,383 |
| `observations` | 4,039,627 |
| `careplans` | 18,660 |
| `allergies` | 5,504 |
| **Total** | **4,860,769** |

## Data quality score

Calculation: Data quality score = (total_rows - total_violations) / total_rows * 100

**99.87%** of loaded rows passed every validation check that applied to them (4,854,551 of 4,860,769). The 6,218 flagged rows are listed below by check. They remain in `validation_log` for traceability; see Recommendations for next steps.

## Checks run

| Check | Category | Table | Violations | Applicable rows | Rate |
|---|---|---|---|---|---|
| Missing units on a lab/vital reading | Completeness | `observations` | 5,220 | 2,516,720 | 0.21% |
| `deathdate` before `birthdate` | Consistency | `patients` | 0 | 5,727 | 0.00% |
| `stop` before `start` | Consistency | `conditions` | 0 | 146,883 | 0.00% |
| `stop` before `start` | Consistency | `medications` | 330 | 249,517 | 0.13% |
| `stop` before `start` | Consistency | `careplans` | 0 | 9,494 | 0.00% |
| `stop` before `start` | Consistency | `encounters` | 8 | 327,233 | 0.00% |
| Encounter after patient's death | Consistency | `encounters` | 660 | 88,627 | 0.74% |
| Negative income/expenses/coverage | Plausibility | `patients` | 0 | 5,727 | 0.00% |
| Age at death over 120 years | Plausibility | `patients` | 0 | 727 | 0.00% |
| Body Height outside 0–300cm | Plausibility | `observations` | 0 | 71,557 | 0.00% |
| Pain severity outside 0–10 | Plausibility | `observations` | 0 | 136,958 | 0.00% |

"Applicable rows" is the population each check could actually flag. For example, the `stop`-before-`start` check on `medications` only applies to the 249,517 medications with a `stop` date; active medications with a `NULL` stop can't violate it.

## A check I considered and rejected

Before finalizing this list, a completeness check on `medications.reasoncode` was evaluated: flagging active medications (`stop IS NULL`) with no stated reason code. **59%** of active medications have no `reasoncode`. That's a normal characteristic of this dataset, not a data quality issue, so the check was dropped.

## Findings

- **660 encounters occur after the patient's recorded death**
  - 0.74% of encounters belonging to deceased patients.
  - Likely a Synthea simulation artifact (e.g. a scheduled follow-up generated before a later death event), not a defect in the ETL or schema.
- **330 medications have a `stop` date before their `start` date**
  - 0.13% of medications with a stop date.
  - Likely a data-generation quirk in the source, not something introduced during loading. The raw CSV shows the same rows.
- **5,220 lab/vital-sign readings have no recorded unit**
  - 0.21%.
  - Likely readings where the unit was implicit in the test type and Synthea didn't populate it, or qualitative readings that don't carry one.
- **8 encounters have a `stop` before their `start`**
  - Negligible in volume, same likely cause as the medications finding above.
- Every plausibility check (negative dollar amounts, implausible age at death, out-of-range Body Height, out-of-range Pain severity) came back clean. Expected, since Synthea generates physiologically plausible values by design, but worth confirming rather than assuming.

## Recommendations

None of the flagged rows are removed from the dataset. Every issue traces to a specific, explainable category, not widespread data corruption.

Two points worth carrying into query design instead:

- A small number of encounters (660) fall after the patient's recorded death
  date. Queries that reason about time since last encounter for deceased
  patients should decide whether to include or exclude them, not assume it
  can't happen.
- The `observations.units` gaps (5,220 rows) mean any query that displays or
  aggregates lab/vital values alongside their units should account for a
  `NULL` unit.
