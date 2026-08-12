# ETL: load Synthea CSVs (data/synthea/) into PostgreSQL, per sql/01_schema.sql

# Imports
import logging
import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

# Setting path, chunk size
DATA_DIR = Path(__file__).resolve().parent.parent / "data" / "synthea"
CHUNK_SIZE = 5000

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

# Building SQLAlchemy engine; loading credentials from env
def get_engine() -> Engine:
    """Build a SQLAlchemy engine from credentials in .env (never hardcoded — see .env.example)."""
    load_dotenv()
    user = os.environ["DB_USER"]
    password = os.environ["DB_PASSWORD"]
    host = os.environ["DB_HOST"]
    port = os.environ["DB_PORT"]
    name = os.environ["DB_NAME"]
    url = f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{name}"
    return create_engine(url)

# Converting Nan/NaT/NA from blank CSV fields to None; Ensures Postgres stores true NULLs
def clean_nulls(df: pd.DataFrame) -> pd.DataFrame:
    return df.astype(object).where(pd.notnull(df), None)

# Emptying all tables before loading; Ensures we can re-run the script if needed without duplicate-key errors
def truncate_all(engine: Engine) -> None:
    tables = "patients, encounters, conditions, medications, observations, careplans, allergies"
    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE {tables} RESTART IDENTITY CASCADE;"))
    logger.info("Truncated all tables")

# Shared helper function that every "load_..." function calls
def load_table(df: pd.DataFrame, table_name: str, engine: Engine) -> None:
    row_count = len(df)
    df = clean_nulls(df)
    df.to_sql(table_name, engine, if_exists="append", index=False, method="multi", chunksize=CHUNK_SIZE)
    logger.info("Loaded %d rows into %s", row_count, table_name)

# Loading in patients data
def load_patients(engine: Engine) -> None:
    df = pd.read_csv(
        DATA_DIR / "patients.csv",
        usecols=["Id", "BIRTHDATE", "DEATHDATE", "MARITAL", "RACE", "ETHNICITY", "GENDER",
                 "CITY", "STATE", "COUNTY", "ZIP", "LAT", "LON",
                 "HEALTHCARE_EXPENSES", "HEALTHCARE_COVERAGE", "INCOME"],
        dtype={"ZIP": str},  # prevents pandas from stripping leading zeros (e.g. "00000")
    )
    df["BIRTHDATE"] = pd.to_datetime(df["BIRTHDATE"]).dt.date
    df["DEATHDATE"] = pd.to_datetime(df["DEATHDATE"]).dt.date
    df.columns = df.columns.str.lower()
    load_table(df, "patients", engine)


def load_encounters(engine: Engine) -> None:
    df = pd.read_csv(
        DATA_DIR / "encounters.csv",
        usecols=["Id", "PATIENT", "START", "STOP", "ENCOUNTERCLASS", "DESCRIPTION", "REASONDESCRIPTION"],
    )
    df["START"] = pd.to_datetime(df["START"])
    df["STOP"] = pd.to_datetime(df["STOP"])
    df.columns = df.columns.str.lower()
    df = df.rename(columns={"patient": "patient_id"})
    load_table(df, "encounters", engine)


def load_conditions(engine: Engine) -> None:
    df = pd.read_csv(
        DATA_DIR / "conditions.csv",
        usecols=["PATIENT", "ENCOUNTER", "START", "STOP", "CODE", "DESCRIPTION"],
    )
    df["START"] = pd.to_datetime(df["START"]).dt.date
    df["STOP"] = pd.to_datetime(df["STOP"]).dt.date
    df.columns = df.columns.str.lower()
    df = df.rename(columns={"patient": "patient_id", "encounter": "encounter_id"})
    load_table(df, "conditions", engine)


def load_medications(engine: Engine) -> None:
    df = pd.read_csv(
        DATA_DIR / "medications.csv",
        usecols=["PATIENT", "ENCOUNTER", "CODE", "DESCRIPTION", "START", "STOP",
                 "DISPENSES", "REASONCODE", "REASONDESCRIPTION"],
    )
    df["START"] = pd.to_datetime(df["START"])
    df["STOP"] = pd.to_datetime(df["STOP"])
    df["DISPENSES"] = df["DISPENSES"].astype("Int64")  # nullable integer dtype
    df.columns = df.columns.str.lower()
    df = df.rename(columns={"patient": "patient_id", "encounter": "encounter_id"})
    load_table(df, "medications", engine)


def load_observations(engine: Engine) -> None:
    df = pd.read_csv(
        DATA_DIR / "observations.csv",
        usecols=["PATIENT", "ENCOUNTER", "DATE", "CATEGORY", "CODE", "DESCRIPTION",
                 "VALUE", "UNITS", "TYPE"],
    )
    df["DATE"] = pd.to_datetime(df["DATE"])

    # VALUE is mixed-type in the source; split into value_numeric / value_text per row,
    # driven by TYPE, so downstream SQL never needs to cast text to do arithmetic on labs.
    is_numeric = df["TYPE"] == "numeric"
    df["value_numeric"] = pd.to_numeric(df["VALUE"].where(is_numeric), errors="coerce")
    df["value_text"] = df["VALUE"].where(~is_numeric)
    df = df.drop(columns=["VALUE", "TYPE"])

    df.columns = df.columns.str.lower()
    df = df.rename(columns={"patient": "patient_id", "encounter": "encounter_id"})
    load_table(df, "observations", engine)


def load_careplans(engine: Engine) -> None:
    df = pd.read_csv(
        DATA_DIR / "careplans.csv",
        usecols=["Id", "PATIENT", "ENCOUNTER", "START", "STOP", "DESCRIPTION", "REASONDESCRIPTION"],
    )
    df["START"] = pd.to_datetime(df["START"]).dt.date
    df["STOP"] = pd.to_datetime(df["STOP"]).dt.date
    df.columns = df.columns.str.lower()
    df = df.rename(columns={"patient": "patient_id", "encounter": "encounter_id"})
    load_table(df, "careplans", engine)


def load_allergies(engine: Engine) -> None:
    df = pd.read_csv(
        DATA_DIR / "allergies.csv",
        usecols=["PATIENT", "ENCOUNTER", "START", "STOP", "CODE", "DESCRIPTION", "TYPE", "CATEGORY",
                 "REACTION1", "DESCRIPTION1", "SEVERITY1", "REACTION2", "DESCRIPTION2", "SEVERITY2"],
    )
    df["START"] = pd.to_datetime(df["START"]).dt.date
    df["STOP"] = pd.to_datetime(df["STOP"]).dt.date
    df.columns = df.columns.str.lower()
    df = df.rename(columns={"patient": "patient_id", "encounter": "encounter_id"})
    load_table(df, "allergies", engine)

# Main load function
def main() -> None:
    engine = get_engine()
    truncate_all(engine)

    # Load order follows the foreign-key dependency chain in sql/01_schema.sql:
    # patients -> encounters -> the five event tables.
    try:
        load_patients(engine)
        load_encounters(engine)
        load_conditions(engine)
        load_medications(engine)
        load_observations(engine)
        load_careplans(engine)
        load_allergies(engine)
    except Exception:
        logger.error("ETL failed — see traceback below", exc_info=True)
        raise

    logger.info("ETL complete")


if __name__ == "__main__":
    main()
