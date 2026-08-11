# Clinical Data Pipeline: Real-World Evidence & Pharmacovigilance Analysis

## Overview

This project is an end-to-end clinical data management pipeline built on synthetic
electronic health record (EHR) data. It demonstrates the core responsibilities of a
SQL Programmer in a healthcare research environment: ingesting and transforming raw
patient data, validating data quality before analysis, and running complex SQL
queries to answer clinically relevant questions about medication safety and
treatment outcomes.

It was built as a portfolio project to support a SQL Programmer interview at the
VA Boston Healthcare System, and to stand on its own as a demonstration of ETL,
data validation, and SQL analysis skills in a healthcare context.

### A note on framing: real-world evidence, not a clinical trial

[Synthea](https://synthetichealth.github.io/synthea/) generates synthetic
**electronic health record and claims data** — encounters, diagnoses, medications,
labs, vitals — for a simulated patient population. It does not generate randomized
controlled trial (RCT) data: there are no study arms, randomization, protocol
visit schedules, or enrollment/consent records in this dataset.

This project is therefore framed as a **real-world evidence (RWE) and
pharmacovigilance analysis** rather than a clinical trial analysis. The questions
it answers — medication adherence, adverse events linked to active medications,
and drug interaction exposure — are exactly the kind of observational, EHR-based
analyses a clinical data programmer performs
when working with real-world patient data rather than a controlled trial dataset.
This is a closely related and highly relevant discipline: post-market safety
surveillance, pharmacoepidemiology, and observational outcomes research all rely
on the same SQL skill set (multi-table joins, window functions, CTEs, cohort
definition) as trial data management.

Three places where the data itself doesn't provide a concept directly, and a
proxy/reference definition is used instead, are documented explicitly rather than
presented as if they came from the source data:

- **Adverse events**: Synthea has no "adverse event" flag. This project defines an
  adverse event proxy as an inpatient or emergency encounter that overlaps a
  patient's active medication window, excluding the encounter that prescribed the
  medication itself. This is documented as a modeled proxy in `data-dictionary.md`,
  not a literal adverse event report. Unlike the medication-adherence query below,
  this one is **not** restricted to oral tablets — adherence only makes sense for
  drugs taken continuously at home, but concurrent drug exposure during a
  hospitalization applies just as much to an injectable or IV medication.
  Severity is bucketed by concurrent active-medication count, using the standard
  pharmacoepidemiology polypharmacy thresholds (5+, 10+) rather than an invented
  cutoff. See `sql/queries/02_adverse_events.sql`.
- **Drug interactions**: Synthea does not encode contraindications between
  medications. A small, hand-curated reference table of known interacting drug
  class pairs (warfarin + NSAIDs, clopidogrel + NSAIDs, ACE inhibitors + NSAIDs,
  benzodiazepines + opioids, verapamil + statins) is built from established
  clinical knowledge, using only drug names verified to actually appear in this
  dataset — e.g. an ACE-inhibitor/potassium-sparing-diuretic pair was considered
  and dropped since no potassium-sparing diuretic exists in this data. Medications
  are classified by ingredient name (`ILIKE` on `description`) rather than by
  `code`, since the same drug has a different RxNorm code per dose/form. This
  reference table is documented as curated domain data, not derived from Synthea.
  See `sql/queries/03_drug_interactions.sql`.
- **Medication adherence**: Synthea doesn't label fills as adherent or
  non-adherent. This project defines a treatment gap as more than 30 days between
  one fill's `stop` date and the next fill of the same drug for the same patient,
  assessed per patient-drug pair rather than per patient overall. Analysis is
  scoped to oral tablets with 5+ total fills — injectables/gels (e.g. dental
  fluoride gel, IV antibiotics given during a hospital stay) are administered
  episodically rather than taken continuously at home, so a multi-year gap between
  them isn't a real lapse in therapy, and a coincidental pair of one-off
  prescriptions years apart isn't either. See `sql/queries/01_medication_history.sql`.

## Data

- **Source**: [Synthea](https://synthetichealth.github.io/synthea/) synthetic
  patient data generator
- **Generation command**:
  ```bash
  ./run_synthea -p 5000 -s 42 --exporter.fhir.export=false --exporter.csv.export=true Massachusetts
  ```
- **Population**: ~5,000 synthetic patients
- **Geography**: Massachusetts
- **Seed**: 42 (for reproducibility)
- **Format**: CSV files located in `data/synthea/` (excluded from git via
  `.gitignore` — regenerate locally using the command above)

### Tables in scope

This project uses only the tables relevant to the medication safety and treatment
outcomes questions below. Billing/claims detail, imaging, payer, and
organization/provider tables were profiled but excluded from scope as
out-of-scope noise for a clinical analysis project.

| Table | Purpose |
|---|---|
| `patients` | Demographics, cohort definition |
| `encounters` | Visit backbone; hospitalization/ED proxy for adverse events |
| `conditions` | Diagnoses and comorbidities |
| `medications` | Drug exposure, dosing, dispensing, indication |
| `observations` | Labs and vitals for treatment outcome measurement |
| `careplans` | Care plan / therapy context |
| `allergies` | Medication and environmental allergy history |

## Tech Stack

| Component | Technology |
|---|---|
| Data generation | Synthea |
| Database | PostgreSQL |
| ETL & Validation (Python) | Python, Pandas, SQLAlchemy |
| ETL & Validation (SQL) | PostgreSQL |
| SQL Analysis | PostgreSQL |
| Version control | Git/GitHub |
| Documentation | Markdown |

## Methodology

### Phase 1: ETL & Data Validation

1. **Data profiling** — explore the Synthea CSVs to understand structure, column
   names, data types, and relationships before assuming a schema.
2. **Python ETL** (`scripts/load_data.py`) — load Synthea CSVs into PostgreSQL
   using Pandas and SQLAlchemy; clean column names, standardize formatting, handle
   type conversion and missing values; log all transformations and row counts.
3. **SQL schema & validation** (`sql/01_schema.sql`, `sql/02_validation.sql`) —
   define tables with appropriate indexes and constraints; implement completeness,
   consistency, and plausibility checks; log validation issues to a dedicated
   validation log table.
4. **Validation report** (`scripts/validate_data.py` → `reports/validation_report.md`) —
   the script queries `validation_log` and the source tables directly and prints
   the findings (row counts, per-check violations and rates); the report itself
   is written by hand using that printed output as its source of truth, keeping
   narrative interpretation out of the script.

### Phase 2: SQL Analysis

Three queries answering clinically relevant questions, covering multi-table
JOINs, aggregations, window functions, CTEs, date arithmetic, and CASE logic.
Scoped to three (down from an original plan of seven) to allow deeper, unhurried
treatment of each query, rather than moving fast across a longer list — and
because these three map directly onto the three proxy definitions documented
above, forming one coherent narrative: adherence → adverse events → interaction
risk.

1. Medication history & adherence (`sql/queries/01_medication_history.sql`)
2. Adverse event identification (`sql/queries/02_adverse_events.sql`)
3. Drug interaction flags (`sql/queries/03_drug_interactions.sql`)

## Project Timeline

A running log of progress by day.

- **Day 1 (Aug 5)**: Project ideation; repo/README setup; Synthea setup/investigation
- **Day 2 (Aug 6)**: Synthea patient generation; NOTES.md creation; SQL schema design (`sql/01_schema.sql`)
- **Day 3 (Aug 7)**: Finalized and annotated `sql/01_schema.sql`; created `data-dictionary.md`
- **Day 4 (Aug 10)**: Fixed schema gaps found in a full audit (`allergies.start/stop`, `patients.FIPS` documentation); set up local PostgreSQL; `.env` credentials, and Python virtual environment; built and successfully ran `scripts/load_data.py`; loading all ~4.86M rows across 7 tables; built `sql/02_validation.sql` (11 checks across completeness/consistency/plausibility) and `reports/validation_report.md` (99.87% data quality score) — Phase 1 (ETL & Data Validation) complete. Reworked `scripts/validate_data.py` to only print findings, with `validation_report.md` written by hand from that output. Started Phase 2: built `sql/queries/01_medication_history.sql` (medication history & adherence), scoped to oral tablets with 5+ fills after catching false positives from episodic/injectable medications in the initial version.
- **Day 5 (Aug 11)**: Built `sql/queries/02_adverse_events.sql` (adverse event identification — inpatient/emergency encounters overlapping active medication windows, deliberately not restricted to oral tablets, severity bucketed by polypharmacy thresholds). Narrowed Phase 2 scope from seven queries to three (medication adherence, adverse events, drug interactions) to allow deeper focus on each and align with the three proxy definitions already documented above. Built `sql/queries/03_drug_interactions.sql` (drug interaction flags — classifies medications into drug classes by ingredient name, self-joins on overlapping active windows, matches against a curated reference table of 5 known-interacting class pairs verified against drugs actually present in the data) — Phase 2 (SQL Analysis) complete.

## Key Findings

_To be populated after analysis is complete — see `reports/analysis_summary.md`._

## How to Reproduce

1. Install [Synthea](https://github.com/synthetichealth/synthea) and generate the
   dataset using the command above; place the CSVs in `data/synthea/`.
2. Create a Python virtual environment and install dependencies:
   `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt`.
3. Create a PostgreSQL database, copy `.env.example` to `.env`, and fill in your
   connection details.
4. Run `sql/01_schema.sql` to create the schema.
5. Run `python scripts/load_data.py` to load and clean the data.
6. Run `sql/02_validation.sql` to execute validation checks, then
   `python scripts/validate_data.py` to print the findings — `reports/validation_report.md`
   is written by hand using that output.
7. Run the queries in `sql/queries/` to reproduce the analysis.

## Project Structure

```
rwe-pharmacovigilance-pipeline/
├── README.md                          # Project overview and documentation
├── data-dictionary.md                 # Schema documentation, field definitions
├── NOTES.md                           # Personal working notes
├── requirements.txt                   # Pinned Python dependencies
├── .env.example                       # Template for local DB credentials (.env is gitignored)
├── .gitignore                         # Excludes data/synthea/, .env, .venv/
│
├── data/
│   └── synthea/                       # Synthea CSV files (excluded from git)
│
├── sql/
│   ├── 01_schema.sql                  # Table creation, indexes, constraints
│   ├── 02_validation.sql              # Validation checks; logs issues to validation_log
│   │
│   └── queries/
│       ├── 01_medication_history.sql
│       ├── 02_adverse_events.sql
│       └── 03_drug_interactions.sql
│
├── scripts/
│   ├── load_data.py                   # Python ETL: loading CSVs into PostgreSQL
│   └── validate_data.py               # Prints validation_log findings (row counts, violations, rates)
│
└── reports/
    ├── validation_report.md           # Written by hand from validate_data.py's output
    └── analysis_summary.md            # Key results from SQL queries
```
