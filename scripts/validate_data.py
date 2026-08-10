"""Print the findings from sql/02_validation.sql: row counts, per-check violation
counts and rates, and the reasoncode rates behind the check we evaluated and
rejected. reports/validation_report.md is written by hand using this output —
this script's job stops at surfacing the numbers, not authoring the write-up.
"""

import logging
import os

from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

TABLES = ["patients", "encounters", "conditions", "medications", "observations", "careplans", "allergies"]

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)

# One entry per check defined in sql/02_validation.sql. "applicable_sql" computes
# the population that check could actually flag (e.g. the stop-before-start check
# on medications only applies to medications that HAVE a stop date), so the rate
# printed below is meaningful rather than violations / whole-table size.
CHECKS = [
    {
        "check_name": "missing_units_on_measurement",
        "table_name": "observations",
        "category": "Completeness",
        "applicable_sql": "SELECT COUNT(*) FROM observations WHERE category IN ('laboratory', 'vital-signs')",
    },
    {
        "check_name": "deathdate_before_birthdate",
        "table_name": "patients",
        "category": "Consistency",
        "applicable_sql": "SELECT COUNT(*) FROM patients",
    },
    {
        "check_name": "stop_before_start",
        "table_name": "conditions",
        "category": "Consistency",
        "applicable_sql": "SELECT COUNT(*) FROM conditions WHERE stop IS NOT NULL",
    },
    {
        "check_name": "stop_before_start",
        "table_name": "medications",
        "category": "Consistency",
        "applicable_sql": "SELECT COUNT(*) FROM medications WHERE stop IS NOT NULL",
    },
    {
        "check_name": "stop_before_start",
        "table_name": "careplans",
        "category": "Consistency",
        "applicable_sql": "SELECT COUNT(*) FROM careplans WHERE stop IS NOT NULL",
    },
    {
        "check_name": "stop_before_start",
        "table_name": "encounters",
        "category": "Consistency",
        "applicable_sql": "SELECT COUNT(*) FROM encounters WHERE stop IS NOT NULL",
    },
    {
        "check_name": "encounter_after_death",
        "table_name": "encounters",
        "category": "Consistency",
        "applicable_sql": """
            SELECT COUNT(*) FROM encounters enc
            JOIN patients pat ON enc.patient_id = pat.id
            WHERE pat.deathdate IS NOT NULL
        """,
    },
    {
        "check_name": "negative_dollar_amount",
        "table_name": "patients",
        "category": "Plausibility",
        "applicable_sql": "SELECT COUNT(*) FROM patients",
    },
    {
        "check_name": "implausible_age_at_death",
        "table_name": "patients",
        "category": "Plausibility",
        "applicable_sql": "SELECT COUNT(*) FROM patients WHERE deathdate IS NOT NULL",
    },
    {
        "check_name": "implausible_height",
        "table_name": "observations",
        "category": "Plausibility",
        "applicable_sql": "SELECT COUNT(*) FROM observations WHERE code = '8302-2'",
    },
    {
        "check_name": "implausible_pain_severity",
        "table_name": "observations",
        "category": "Plausibility",
        "applicable_sql": "SELECT COUNT(*) FROM observations WHERE code = '72514-3'",
    },
]


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


def get_row_counts(engine: Engine) -> dict[str, int]:
    counts = {}
    with engine.connect() as conn:
        for table in TABLES:
            counts[table] = conn.execute(text(f"SELECT COUNT(*) FROM {table}")).scalar()
    return counts


def get_check_results(engine: Engine) -> list[dict]:
    """Attach live violation counts and applicable-population rates to each check in CHECKS."""
    results = []
    with engine.connect() as conn:
        for check in CHECKS:
            violations = conn.execute(
                text("SELECT COUNT(*) FROM validation_log WHERE check_name = :name AND table_name = :table"),
                {"name": check["check_name"], "table": check["table_name"]},
            ).scalar()
            applicable = conn.execute(text(check["applicable_sql"])).scalar()
            rate = (violations / applicable * 100) if applicable else 0.0
            results.append({**check, "violations": violations, "applicable": applicable, "rate": rate})
    return results


def get_reasoncode_rates(engine: Engine) -> tuple[float, float]:
    """Live numbers behind the reasoncode check we evaluated and rejected (see validation_report.md)."""
    with engine.connect() as conn:
        overall = conn.execute(text("""
            SELECT 100.0 * COUNT(*) FILTER (WHERE reasoncode IS NULL) / COUNT(*) FROM medications
        """)).scalar()
        active = conn.execute(text("""
            SELECT 100.0 * COUNT(*) FILTER (WHERE reasoncode IS NULL) / COUNT(*)
            FROM medications WHERE stop IS NULL
        """)).scalar()
    return float(overall), float(active)


def print_findings(row_counts: dict[str, int], check_results: list[dict], reasoncode_rates: tuple[float, float]) -> None:
    total_rows = sum(row_counts.values())
    total_violations = sum(c["violations"] for c in check_results)

    logger.info("=== Row counts ===")
    for table, count in row_counts.items():
        logger.info("%-15s %10d", table, count)
    logger.info("%-15s %10d", "TOTAL", total_rows)

    logger.info("")
    logger.info("=== Check results ===")
    logger.info("%-32s %-13s %-13s %12s %12s %8s", "check_name", "table", "category", "violations", "applicable", "rate")
    for c in check_results:
        logger.info(
            "%-32s %-13s %-13s %12d %12d %7.2f%%",
            c["check_name"], c["table_name"], c["category"], c["violations"], c["applicable"], c["rate"],
        )

    logger.info("")
    logger.info("=== Overall ===")
    logger.info("Data quality score: %.2f%% (%d / %d rows passed)", (total_rows - total_violations) / total_rows * 100, total_rows - total_violations, total_rows)

    logger.info("")
    logger.info("=== reasoncode check considered and rejected ===")
    overall_rate, active_rate = reasoncode_rates
    logger.info("Overall null rate: %.1f%% | Active-medication null rate: %.1f%%", overall_rate, active_rate)


def main() -> None:
    engine = get_engine()
    row_counts = get_row_counts(engine)
    check_results = get_check_results(engine)
    reasoncode_rates = get_reasoncode_rates(engine)
    print_findings(row_counts, check_results, reasoncode_rates)


if __name__ == "__main__":
    main()
