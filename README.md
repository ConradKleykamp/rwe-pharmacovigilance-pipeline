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
drug interaction exposure, safety signals, and treatment outcomes — are exactly
the kind of observational, EHR-based analyses a clinical data programmer performs
when working with real-world patient data rather than a controlled trial dataset.
This is a closely related and highly relevant discipline: post-market safety
surveillance, pharmacoepidemiology, and observational outcomes research all rely
on the same SQL skill set (multi-table joins, window functions, CTEs, cohort
definition) as trial data management.

Two places where the data itself doesn't provide a concept directly, and a
proxy/reference definition is used instead, are documented explicitly rather than
presented as if they came from the source data:

- **Adverse events**: Synthea has no "adverse event" flag. This project defines an
  adverse event proxy as an inpatient or emergency encounter that overlaps a
  patient's active medication window. This is documented as a modeled proxy in
  `data-dictionary.md`, not a literal adverse event report.
- **Drug interactions**: Synthea does not encode contraindications between
  medications. A small, hand-curated reference table of known interacting drug
  pairs (e.g., warfarin + NSAIDs, ACE inhibitors + potassium-sparing diuretics) is
  built from established clinical knowledge, using drug names that actually appear
  in this dataset. This reference table is documented as curated domain data, not
  derived from Synthea.

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
4. **Validation report** (`reports/validation_report.md`) — summarize data quality
   findings, report a data quality score, and document actions taken.

### Phase 2: SQL Analysis

Seven queries answering clinically relevant questions, covering multi-table
JOINs, aggregations, window functions (ROW_NUMBER, LAG, FIRST_VALUE, LAST_VALUE,
RANK), CTEs, date arithmetic, CASE logic, and subqueries:

1. Medication history & adherence (`sql/queries/01_medication_history.sql`)
2. Adverse event identification (`sql/queries/02_adverse_events.sql`)
3. Drug interaction flags (`sql/queries/03_drug_interactions.sql`)
4. Safety signal detection (`sql/queries/04_safety_signals.sql`)
5. Treatment outcomes (`sql/queries/05_treatment_outcomes.sql`)
6. Cohort characteristics (`sql/queries/06_cohort_characteristics.sql`)
7. Data quality summary (`sql/queries/07_data_quality_summary.sql`)

## Project Timeline

A running log of progress by day.

- **Day 1 (Aug 5)**: Project ideation, repo/README setup, Synthea setup/investigation
- **Day 2 (Aug 6)**: Synthea patient generation, NOTES.md creation, SQL schema design (`sql/01_schema.sql`)
- **Day 3 (Aug 7)**: Finalized and annotated `sql/01_schema.sql`, created `data-dictionary.md`

## Key Findings

_To be populated after analysis is complete — see `reports/analysis_summary.md`._

## How to Reproduce

1. Install [Synthea](https://github.com/synthetichealth/synthea) and generate the
   dataset using the command above; place the CSVs in `data/synthea/`.
2. Create a PostgreSQL database and set connection details (see
   `scripts/load_data.py`).
3. Run `sql/01_schema.sql` to create the schema.
4. Run `python scripts/load_data.py` to load and clean the data.
5. Run `sql/02_validation.sql` to execute validation checks, and
   `python scripts/validate_data.py` to generate the validation report.
6. Run the queries in `sql/queries/` to reproduce the analysis.

## Project Structure

```
clinical-trial-data/
├── README.md                          # Project overview and documentation
├── data-dictionary.md                 # Schema documentation, field definitions
├── .gitignore                         # Excludes data/synthea/ CSVs
│
├── data/
│   └── synthea/                       # Synthea CSV files (excluded from git)
│
├── sql/
│   ├── 01_schema.sql                  # Table creation, indexes, constraints
│   ├── 02_validation.sql              # SQL-based validation rules and quality checks
│   │
│   └── queries/
│       ├── 01_medication_history.sql
│       ├── 02_adverse_events.sql
│       ├── 03_drug_interactions.sql
│       ├── 04_safety_signals.sql
│       ├── 05_treatment_outcomes.sql
│       ├── 06_cohort_characteristics.sql
│       └── 07_data_quality_summary.sql
│
├── scripts/
│   ├── load_data.py                   # Python ETL: loading CSVs into PostgreSQL
│   └── validate_data.py               # Python: running validation, generating report
│
└── reports/
    ├── validation_report.md           # Data quality findings and summary
    └── analysis_summary.md            # Key results from SQL queries
```
