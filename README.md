# Clinical Data Pipeline: Real-World Evidence & Pharmacovigilance Analysis

## Overview

This project is an end-to-end clinical data management pipeline built on synthetic
electronic health record (EHR) data. It demonstrates the core responsibilities of a
SQL Programmer in a healthcare research environment: ingesting and transforming raw
patient data, validating data quality before analysis, and running complex SQL
queries to answer clinically relevant questions about medication safety.

It was built as a portfolio project for a SQL Programmer interview at the VA Boston
Healthcare System, and stands on its own as a demonstration of ETL, data validation,
and SQL analysis skills in a healthcare context.

### A note on framing: real-world evidence, not a clinical trial

[Synthea](https://synthetichealth.github.io/synthea/) generates synthetic
**electronic health record and claims data**: encounters, diagnoses, medications,
labs, and vitals for a simulated patient population. It does not generate randomized
controlled trial (RCT) data. There are no study arms, randomization, protocol visit
schedules, or enrollment/consent records in this dataset.

This project is therefore framed as a **real-world evidence (RWE) and
pharmacovigilance analysis** rather than a clinical trial analysis. It answers
observational, EHR-based questions: medication adherence, adverse events linked to
active medications, and drug interaction exposure. Post-market safety surveillance,
pharmacoepidemiology, and observational outcomes research rely on the same SQL
skill set (multi-table joins, window functions, CTEs, cohort definition) as trial
data management.

Three concepts the data doesn't provide directly use a proxy definition instead.
Each is documented explicitly, not presented as if it came from the source data:

- **Adverse events**: Synthea has no adverse event flag. This project defines the
  proxy as an inpatient or emergency encounter that overlaps a patient's active
  medication window, excluding the encounter that prescribed the medication. This
  is a modeled proxy, documented in `data-dictionary.md`, not a literal adverse
  event report. Unlike the adherence query below, it is not restricted to oral
  tablets: concurrent drug exposure during a hospitalization applies to an
  injectable or IV medication just as much as an oral one. Severity is bucketed by
  concurrent active-medication count, using standard pharmacoepidemiology
  polypharmacy thresholds (5+, 10+) rather than an invented cutoff. See
  `sql/queries/02_adverse_events.sql`.
- **Drug interactions**: Synthea does not encode contraindications between
  medications. A small, hand-curated reference table of known interacting drug
  class pairs (warfarin + NSAIDs, clopidogrel + NSAIDs, ACE inhibitors + NSAIDs,
  benzodiazepines + opioids, verapamil + statins) is built from established
  clinical knowledge, using only drug names verified to appear in this dataset. An
  ACE-inhibitor/potassium-sparing-diuretic pair was considered and dropped, since
  no potassium-sparing diuretic exists in this data. Medications are classified by
  ingredient name (`ILIKE` on `description`) rather than `code`, since the same
  drug has a different RxNorm code per dose or form. This reference table is
  curated domain data, not derived from Synthea. See
  `sql/queries/03_drug_interactions.sql`.
- **Medication adherence**: Synthea doesn't label fills as adherent or
  non-adherent. This project defines a treatment gap as more than 30 days between
  one fill's `stop` date and the next fill of the same drug, assessed per
  patient-drug pair rather than per patient overall. Analysis is scoped to oral
  tablets with 5+ total fills. Injectables and gels (dental fluoride gel, IV
  antibiotics given during a hospital stay) are administered episodically, not
  taken continuously at home, so a multi-year gap between them isn't a real lapse
  in therapy. The 5+ fill requirement also filters out a coincidental pair of
  one-off prescriptions taken years apart. See
  `sql/queries/01_medication_history.sql`.

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
  `.gitignore`; regenerate locally using the command above)

### Tables in scope

This project uses only the tables relevant to the medication safety questions
below. Billing and claims detail, imaging, payer, and organization/provider tables
were profiled but excluded as out of scope.

| Table | Purpose |
|---|---|
| `patients` | Demographics, cohort definition |
| `encounters` | Visit backbone; hospitalization/ED proxy for adverse events |
| `conditions` | Diagnoses and comorbidities |
| `medications` | Drug exposure, dosing, dispensing, indication |
| `observations` | Labs and vitals |
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

1. **Data profiling**: explore the Synthea CSVs to understand structure, column
   names, data types, and relationships before assuming a schema.
2. **Python ETL** (`scripts/load_data.py`): load Synthea CSVs into PostgreSQL
   using Pandas and SQLAlchemy. Clean column names, standardize formatting, handle
   type conversion and missing values. Log all transformations and row counts.
3. **SQL schema & validation** (`sql/01_schema.sql`, `sql/02_validation.sql`):
   define tables with appropriate indexes and constraints. Implement
   completeness, consistency, and plausibility checks. Log validation issues to a
   dedicated validation log table.
4. **Validation report** (`scripts/validate_data.py` → `reports/validation_report.md`):
   the script queries `validation_log` and the source tables directly and prints
   the findings (row counts, per-check violations and rates). The report is
   written by hand from that printed output, keeping narrative interpretation out
   of the script.

### Phase 2: SQL Analysis

Three queries answering clinically relevant questions, covering multi-table
JOINs, aggregations, window functions, CTEs, date arithmetic, and CASE logic.
Scoped to three (down from an original plan of seven) to allow deeper, unhurried
treatment of each query. These three also map onto the three proxy definitions
documented above, forming one narrative: adherence, adverse events, interaction
risk.

1. Medication history & adherence (`sql/queries/01_medication_history.sql`)
2. Adverse event identification (`sql/queries/02_adverse_events.sql`)
3. Drug interaction flags (`sql/queries/03_drug_interactions.sql`)

## Project Timeline

A running log of progress by day.

- **Day 1 (Aug 5)**: Project ideation, repo setup, Synthea investigation.
- **Day 2 (Aug 6)**: Generated Synthea data. Started `sql/01_schema.sql`.
- **Day 3 (Aug 7)**: Finalized `sql/01_schema.sql`. Created `data-dictionary.md`.
- **Day 4 (Aug 10)**: Fixed schema gaps from a full audit. Set up PostgreSQL and
  the Python environment. Loaded ~4.86M rows via `scripts/load_data.py`. Built
  `sql/02_validation.sql` and `reports/validation_report.md` (99.87% quality
  score). Phase 1 complete. Started Phase 2 with
  `sql/queries/01_medication_history.sql`.
- **Day 5 (Aug 11)**: Built `sql/queries/02_adverse_events.sql` and
  `sql/queries/03_drug_interactions.sql`. Narrowed Phase 2 scope from seven
  queries to three. Phase 2 complete.
- **Day 6 (Aug 12)**: Wrote `reports/analysis_summary.md` and updated Key
  Findings. Tightened README and `validation_report.md` language. Full repo
  audit: re-verified every reported number against the live database, fixed
  stale references and typos, corrected a data-dictionary count, and made
  `sql/02_validation.sql` safe to re-run.

## Key Findings

- Medication adherence: 296 of 4,696 patient-drug pairs (188 patients) showed a
  30+ day treatment gap. Lisinopril, hydrochlorothiazide, and amlodipine (blood
  pressure medications) had the most non-adherent patients.
- Adverse events: 12,311 inpatient or emergency encounters overlapped an active
  medication window. 988 involved 10+ concurrent medications (excessive
  polypharmacy).
- Drug interactions: 13,739 concurrent medication pairs matched a known
  interacting drug class combination, affecting 714 patients. ACE inhibitor +
  NSAID was the most common pair. Benzodiazepine + opioid was rarest but carries
  the highest clinical risk.

See `reports/analysis_summary.md` for the full write-up, including limitations
and recommendations.

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
   `python scripts/validate_data.py` to print the findings.
   `reports/validation_report.md` is written by hand using that output.
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
