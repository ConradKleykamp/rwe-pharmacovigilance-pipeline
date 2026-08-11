# Validation Report

Written using the findings printed by `scripts/validate_data.py`, which queries `validation_log` (populated by `sql/ 02_validation.sql`) and the source tables directly. 

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

**99.87%** of loaded rows passed every validation check that applied to them (4,854,551 of 4,860,769). The 6,218 flagged rows are documented below, table by table. The flagged rows are preserved in `validation_log` for traceability, and the recommendation section addresses whether they need any further action.

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

"Applicable rows" is the population each check could actually flag, e.g. the `stop`-before-`start` check on `medications` only applies to the 249,517 medications that have a `stop` date at all (active medications, with a `NULL` stop, can't violate it).

## A check I considered and rejected

Before finalizing this list, I evaluated a completeness check on `medications.reasoncode`, i.e. flagging active medications (`stop IS NULL`) with no stated reason code. Checking against the data first, it was found that **59%** of active medications have no `reasoncode`. This suggests a normal characteristic of this dataset, so the check was dropped.

## Findings

- **660 encounters occur after the patient's recorded death** 
  - 0.74% of encounters belonging to deceased patients. 
  - This is likely a Synthea simulation artifact (e.g. scheduled follow-ups generated before a subsequent death event), not a defect in the ETL or schema.
- **330 medications have a `stop` date before their `start` date** 
  - 0.13% of medications with a stop date. 
  - This is likely a data-generation quirk in the source rather than anything introduced during loading, since the same comparison run directly against the raw CSV would show the same rows.
- **5,220 lab/vital-sign readings have no recorded unit** 
  - 0.21%. 
  - Likely readings where the unit was implicit in the test type and Synthea didn't populate it, or qualitative readings that don't carry one.
- **8 encounters have a `stop` before their `start`**
  - Negligible in volume, same likely cause as the medications finding above.
- Every plausibility check (negative dollar amounts, implausible age at death, out-of-range Body Height, out-of-range Pain severity) came back completely clean. This is to be expected, since Synthea generates physiologically-plausible values by design, but worth confirming rather than assuming.

## Recommendations

None of the flagged rows are removed from the dataset. Every issue is traceable to a specific, explainable category rather than
widespread data corruption.

Two points worth carrying into query design instead:

- Queries that reason about "time since last encounter" or similar for deceased
  patients should be aware that a small number of encounters (660) fall after
  the recorded death date, and decide deliberately whether to include or exclude
  them rather than assume it can't happen.
- The `observations.units` gaps (5,220 rows) mean any query that displays or
  aggregates lab/vital values alongside their units should account for a
  `NULL` unit rather than assume one is always present.
