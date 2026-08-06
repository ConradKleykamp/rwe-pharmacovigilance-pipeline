-- Schema for the RWE / pharmacovigilance pipeline.
-- Source: Synthea synthetic EHR data (data/synthea/*.csv), loaded via scripts/load_data.py.
-- Design decisions (surrogate vs. natural keys, DATE vs. TIMESTAMP, dropped columns)
-- were made against profiled data — see data-dictionary.md for the reasoning.

-- Tables are created in dependency order: patients first, then encounters
-- (which reference patients), then the event tables (which reference both).

CREATE TABLE patients (
    id                   VARCHAR(36) PRIMARY KEY,
    birthdate            DATE NOT NULL,
    deathdate            DATE,
    marital              VARCHAR(1),
    race                 VARCHAR(20) NOT NULL,
    ethnicity            VARCHAR(20) NOT NULL,
    gender               VARCHAR(1) NOT NULL,
    city                 VARCHAR(100),
    state                VARCHAR(100),
    county               VARCHAR(100),
    zip                  VARCHAR(10),
    lat                  NUMERIC,
    lon                  NUMERIC,
    healthcare_expenses  NUMERIC(10, 2),
    healthcare_coverage  NUMERIC(10, 2),
    income               NUMERIC(10, 2)
);

CREATE TABLE encounters (
    id                  VARCHAR(36) PRIMARY KEY,
    patient_id          VARCHAR(36) NOT NULL REFERENCES patients (id),
    start               TIMESTAMP NOT NULL,
    stop                TIMESTAMP,
    encounterclass      VARCHAR(20) NOT NULL,
    description         TEXT,
    reasondescription   TEXT
);

CREATE INDEX idx_encounters_patient_id ON encounters (patient_id);

CREATE TABLE conditions (
    id            BIGSERIAL PRIMARY KEY,
    patient_id    VARCHAR(36) NOT NULL REFERENCES patients (id),
    encounter_id  VARCHAR(36) NOT NULL REFERENCES encounters (id),
    start         DATE NOT NULL,
    stop          DATE,
    code          VARCHAR(20) NOT NULL,
    description   VARCHAR(100) NOT NULL
);

CREATE INDEX idx_conditions_patient_id ON conditions (patient_id);
CREATE INDEX idx_conditions_encounter_id ON conditions (encounter_id);
CREATE INDEX idx_conditions_code ON conditions (code);

CREATE TABLE medications (
    id                 BIGSERIAL PRIMARY KEY,
    patient_id         VARCHAR(36) NOT NULL REFERENCES patients (id),
    encounter_id       VARCHAR(36) NOT NULL REFERENCES encounters (id),
    code               VARCHAR(20) NOT NULL,
    description        TEXT NOT NULL,
    start              TIMESTAMP NOT NULL,
    stop               TIMESTAMP,
    dispenses          INTEGER,
    reasoncode         VARCHAR(20),
    reasondescription  TEXT
);

CREATE INDEX idx_medications_patient_id ON medications (patient_id);
CREATE INDEX idx_medications_encounter_id ON medications (encounter_id);
CREATE INDEX idx_medications_code ON medications (code);

-- encounter_id is nullable: ~155k rows in the source have no ENCOUNTER value
-- (likely historical/imported readings not tied to a specific visit).
CREATE TABLE observations (
    id             BIGSERIAL PRIMARY KEY,
    patient_id     VARCHAR(36) NOT NULL REFERENCES patients (id),
    encounter_id   VARCHAR(36) REFERENCES encounters (id),
    date           TIMESTAMP NOT NULL,
    category       VARCHAR(20),
    code           VARCHAR(20) NOT NULL,
    description    TEXT NOT NULL,
    value_numeric  NUMERIC,
    value_text     TEXT,
    units          VARCHAR(20)
);

CREATE INDEX idx_observations_patient_id ON observations (patient_id);
CREATE INDEX idx_observations_encounter_id ON observations (encounter_id);
CREATE INDEX idx_observations_code ON observations (code);

CREATE TABLE careplans (
    id                 VARCHAR(36) PRIMARY KEY,
    patient_id         VARCHAR(36) NOT NULL REFERENCES patients (id),
    encounter_id       VARCHAR(36) NOT NULL REFERENCES encounters (id),
    start              DATE NOT NULL,
    stop               DATE,
    description        VARCHAR(100) NOT NULL,
    reasondescription  VARCHAR(100)
);

CREATE INDEX idx_careplans_patient_id ON careplans (patient_id);
CREATE INDEX idx_careplans_encounter_id ON careplans (encounter_id);

CREATE TABLE allergies (
    id            BIGSERIAL PRIMARY KEY,
    patient_id    VARCHAR(36) NOT NULL REFERENCES patients (id),
    encounter_id  VARCHAR(36) NOT NULL REFERENCES encounters (id),
    code          VARCHAR(20) NOT NULL,
    description   TEXT NOT NULL,
    type          VARCHAR(20),
    category      VARCHAR(20),
    reaction1     VARCHAR(20),
    description1  TEXT,
    severity1     VARCHAR(20),
    reaction2     VARCHAR(20),
    description2  TEXT,
    severity2     VARCHAR(20)
);

CREATE INDEX idx_allergies_patient_id ON allergies (patient_id);
CREATE INDEX idx_allergies_encounter_id ON allergies (encounter_id);
