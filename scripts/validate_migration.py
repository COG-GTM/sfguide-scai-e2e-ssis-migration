#!/usr/bin/env python3
"""Data validation between SQL Server source and Snowflake target.

Implements the checks configured in migration/.scai/settings/test_config.yaml:
  * metrics_validation: row counts + key numeric aggregates per table,
    compared within `tolerance` (default 0.001).
  * row_validation is delegated to SnowConvert AI's cloud validation when the
    sf_bifrost connection is available; this script covers metrics parity.

Usage:
  python3 scripts/validate_migration.py [--connection sf_bifrost]

Exit code 0 = all checks passed, 1 = at least one mismatch.
"""
import argparse
import json
import pathlib
import subprocess
import sys

import yaml

SQLCMD = "/opt/mssql-tools18/bin/sqlcmd"
MSSQL = ["-S", "localhost,1433", "-U", "sa", "-P", "SnowflakeMigrations2026!",
         "-C", "-N", "-d", "TastyBytesDB"]

CONFIG = pathlib.Path(__file__).resolve().parents[1] / "migration/.scai/settings/test_config.yaml"

# (label, T-SQL query, Snowflake query) — each returns a single numeric value.
CHECKS = [
    ("Country row count",
     "SELECT COUNT(*) FROM TastyBytes.Country",
     "SELECT COUNT(*) FROM tastybytesdb.tastybytes.Country"),
    ("City row count",
     "SELECT COUNT(*) FROM TastyBytes.City",
     "SELECT COUNT(*) FROM tastybytesdb.tastybytes.City"),
    ("FoodTruck row count",
     "SELECT COUNT(*) FROM TastyBytes.FoodTruck",
     "SELECT COUNT(*) FROM tastybytesdb.tastybytes.FoodTruck"),
    ("Menu row count",
     "SELECT COUNT(*) FROM TastyBytes.Menu",
     "SELECT COUNT(*) FROM tastybytesdb.tastybytes.Menu"),
    ("MenuItem row count",
     "SELECT COUNT(*) FROM TastyBytes.MenuItem",
     "SELECT COUNT(*) FROM tastybytesdb.tastybytes.MenuItem"),
    ("Customer row count",
     "SELECT COUNT(*) FROM TastyBytes.Customer",
     "SELECT COUNT(*) FROM tastybytesdb.tastybytes.Customer"),
    ("OrderHeader row count",
     "SELECT COUNT(*) FROM TastyBytes.OrderHeader",
     "SELECT COUNT(*) FROM tastybytesdb.tastybytes.OrderHeader"),
    ("OrderDetail row count",
     "SELECT COUNT(*) FROM TastyBytes.OrderDetail",
     "SELECT COUNT(*) FROM tastybytesdb.tastybytes.OrderDetail"),
    ("Inventory row count",
     "SELECT COUNT(*) FROM TastyBytes.Inventory",
     "SELECT COUNT(*) FROM tastybytesdb.tastybytes.Inventory"),
    ("EmployeeShift row count",
     "SELECT COUNT(*) FROM TastyBytes.EmployeeShift",
     "SELECT COUNT(*) FROM tastybytesdb.tastybytes.EmployeeShift"),
    ("OrderHeader total revenue (completed)",
     "SELECT ISNULL(SUM(TotalAmount), 0) FROM TastyBytes.OrderHeader WHERE OrderStatus = 'Completed'",
     "SELECT COALESCE(SUM(TotalAmount), 0) FROM tastybytesdb.tastybytes.OrderHeader WHERE OrderStatus = 'Completed'"),
    ("OrderHeader total tips",
     "SELECT ISNULL(SUM(TipAmount), 0) FROM TastyBytes.OrderHeader",
     "SELECT COALESCE(SUM(TipAmount), 0) FROM tastybytesdb.tastybytes.OrderHeader"),
    ("OrderDetail quantity sum",
     "SELECT ISNULL(SUM(Quantity), 0) FROM TastyBytes.OrderDetail",
     "SELECT COALESCE(SUM(Quantity), 0) FROM tastybytesdb.tastybytes.OrderDetail"),
    ("OrderDetail line total sum (computed column parity)",
     "SELECT ISNULL(SUM(LineTotal), 0) FROM TastyBytes.OrderDetail",
     "SELECT COALESCE(SUM(LineTotal), 0) FROM tastybytesdb.tastybytes.OrderDetail"),
    ("MenuItem price-with-tax sum (computed column parity)",
     "SELECT ISNULL(SUM(PriceWithTax), 0) FROM TastyBytes.MenuItem",
     "SELECT COALESCE(SUM(PriceWithTax), 0) FROM tastybytesdb.tastybytes.MenuItem"),
    ("Inventory quantity-on-hand sum",
     "SELECT ISNULL(SUM(QuantityOnHand), 0) FROM TastyBytes.Inventory",
     "SELECT COALESCE(SUM(QuantityOnHand), 0) FROM tastybytesdb.tastybytes.Inventory"),
    ("EmployeeShift hours-worked sum (computed column parity)",
     "SELECT ISNULL(SUM(HoursWorked), 0) FROM TastyBytes.EmployeeShift",
     "SELECT COALESCE(SUM(HoursWorked), 0) FROM tastybytesdb.tastybytes.EmployeeShift"),
    ("vw_TopSellingItems row count",
     "SELECT COUNT(*) FROM TastyBytes.vw_TopSellingItems",
     "SELECT COUNT(*) FROM tastybytesdb.tastybytes.vw_TopSellingItems"),
]


def mssql_scalar(query: str) -> float:
    result = subprocess.run(
        [SQLCMD, *MSSQL, "-Q", f"SET NOCOUNT ON; {query}", "-W", "-h", "-1", "-b"],
        capture_output=True, text=True, check=True)
    return float(result.stdout.strip().splitlines()[0])


def snowflake_scalar(connection: str, query: str) -> float:
    result = subprocess.run(
        ["snow", "sql", "-c", connection, "-q", query, "--format", "json"],
        capture_output=True, text=True, check=True)
    rows = json.loads(result.stdout)
    return float(next(iter(rows[0].values())))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--connection", default="sf_bifrost")
    args = parser.parse_args()

    config = yaml.safe_load(CONFIG.read_text())
    tolerance = float(config["validation_configuration"]["tolerance"])

    failures = 0
    for label, mssql_q, sf_q in CHECKS:
        src = mssql_scalar(mssql_q)
        tgt = snowflake_scalar(args.connection, sf_q)
        denom = max(abs(src), 1.0)
        ok = abs(src - tgt) / denom <= tolerance
        status = "PASS" if ok else "FAIL"
        print(f"[{status}] {label}: source={src} target={tgt}")
        if not ok:
            failures += 1

    print(f"\n{len(CHECKS) - failures}/{len(CHECKS)} checks passed (tolerance={tolerance})")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
