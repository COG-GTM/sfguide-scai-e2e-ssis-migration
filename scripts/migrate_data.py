#!/usr/bin/env python3
"""Migrate table data from the local SQL Server TastyBytesDB to Snowflake.

Exports each table via sqlcmd to CSV (computing the T-SQL computed columns so
the Snowflake copies are fully materialized), then loads them into Snowflake
with PUT + COPY INTO via the `snow` CLI (Snowflake CLI).

Prereqs:
  * ./scripts/setup_source_db.sh has been run (SQL Server in Docker).
  * `snow` CLI installed and a connection configured (default: sf_bifrost):
      snow connection add sf_bifrost ...
  * Snowflake objects deployed: snowflake/init.sql then migration/target/*.sql

Usage:
  python3 scripts/migrate_data.py [--connection sf_bifrost] [--dry-run]
"""
import argparse
import csv
import io
import pathlib
import subprocess
import sys
import tempfile

SQLCMD = "/opt/mssql-tools18/bin/sqlcmd"
MSSQL = ["-S", "localhost,1433", "-U", "sa", "-P", "SnowflakeMigrations2026!",
         "-C", "-N", "-d", "TastyBytesDB"]

# table -> explicit SELECT (computed columns materialized, GUIDs lowercased,
# ROWVERSION rendered as hex so it round-trips into BINARY(8)).
TABLES = {
    "etl_results.etl_logs":
        "SELECT LogID, name, CONVERT(VARCHAR(23), execution_date, 121) AS execution_date "
        "FROM etl_results.etl_logs",
    "tastybytes.Country":
        "SELECT CountryID, CountryName, CountryCode, CurrencyCode, TaxRate, DisplayName, "
        "IsActive, CONVERT(VARCHAR(23), CreatedAt, 121) AS CreatedAt, "
        "CONVERT(VARCHAR(23), ModifiedAt, 121) AS ModifiedAt FROM TastyBytes.Country",
    "tastybytes.City":
        "SELECT CityID, CityName, CountryID, StateProvince, Latitude, Longitude, "
        "PopulationSize, CONVERT(VARCHAR(23), CreatedAt, 121) AS CreatedAt FROM TastyBytes.City",
    "tastybytes.FoodTruck":
        "SELECT TruckID, LOWER(CONVERT(VARCHAR(36), TruckGUID)) AS TruckGUID, TruckName, "
        "LicensePlate, CityID, TruckConfig, YearPurchased, MaxCapacity, IsOperational, "
        "CONVERT(VARCHAR(23), CreatedAt, 121) AS CreatedAt, "
        "CONVERT(VARCHAR(23), ModifiedAt, 121) AS ModifiedAt FROM TastyBytes.FoodTruck",
    "tastybytes.Menu":
        "SELECT MenuID, MenuName, TruckID, CuisineType, CAST(MenuDescription AS NVARCHAR(MAX)) "
        "AS MenuDescription, BasePriceTier, IsSeasonalMenu, CONVERT(VARCHAR(10), EffectiveFrom, 120) "
        "AS EffectiveFrom, CONVERT(VARCHAR(10), EffectiveTo, 120) AS EffectiveTo, "
        "CONVERT(VARCHAR(23), CreatedAt, 121) AS CreatedAt FROM TastyBytes.Menu",
    "tastybytes.MenuItem":
        "SELECT MenuItemID, MenuID, ItemName, ItemDescription, BasePrice, CalorieCount, "
        "IsVegetarian, IsGlutenFree, IsSpicy, PriceWithTax, "
        "CONVERT(VARCHAR(16), CAST(RowVer AS BINARY(8)), 2) AS RowVer, "  # hex without 0x prefix
        "CONVERT(VARCHAR(23), CreatedAt, 121) AS CreatedAt FROM TastyBytes.MenuItem",
    "tastybytes.Customer":
        "SELECT CustomerID, LOWER(CONVERT(VARCHAR(36), CustomerGUID)) AS CustomerGUID, FirstName, "
        "LastName, Email, PhoneNumber, PreferredCityID, LoyaltyPoints, "
        "CONVERT(VARCHAR(10), MemberSince, 120) AS MemberSince, IsActive, "
        "CONVERT(VARCHAR(23), CreatedAt, 121) AS CreatedAt, "
        "CONVERT(VARCHAR(23), ModifiedAt, 121) AS ModifiedAt FROM TastyBytes.Customer",
    "tastybytes.OrderHeader":
        "SELECT OrderID, CustomerID, TruckID, CONVERT(VARCHAR(23), OrderDate, 121) AS OrderDate, "
        "CONVERT(VARCHAR(23), CompletedAt, 121) AS CompletedAt, OrderStatus, TotalAmount, "
        "TipAmount, PaymentMethod, OrderNotes, CONVERT(VARCHAR(23), CreatedAt, 121) AS CreatedAt, "
        "CONVERT(VARCHAR(23), ModifiedAt, 121) AS ModifiedAt FROM TastyBytes.OrderHeader",
    "tastybytes.OrderDetail":
        "SELECT OrderID, LineNumber, MenuItemID, Quantity, UnitPrice, Discount, LineTotal, "
        "SpecialRequests FROM TastyBytes.OrderDetail",
    "tastybytes.Inventory":
        "SELECT InventoryID, TruckID, IngredientName, QuantityOnHand, UnitOfMeasure, "
        "ReorderLevel, SupplierNotes FROM TastyBytes.Inventory",
    "tastybytes.EmployeeShift":
        "SELECT ShiftID, EmployeeName, TruckID, CONVERT(VARCHAR(10), ShiftDate, 120) AS ShiftDate, "
        "CONVERT(VARCHAR(23), StartTime, 121) AS StartTime, "
        "CONVERT(VARCHAR(23), EndTime, 121) AS EndTime, HoursWorked, Role, HourlyRate, "
        "CONVERT(VARCHAR(23), CreatedAt, 121) AS CreatedAt FROM TastyBytes.EmployeeShift",
}


def export_table(query: str, out_path: pathlib.Path) -> int:
    result = subprocess.run(
        [SQLCMD, *MSSQL, "-Q", f"SET NOCOUNT ON; {query}", "-s", "\x1f", "-W", "-h", "-1", "-b"],
        capture_output=True, text=True, check=True)
    rows = 0
    with out_path.open("w", newline="") as f:
        writer = csv.writer(f)
        for line in result.stdout.splitlines():
            if not line.strip():
                continue
            fields = [None if v == "NULL" else v for v in line.split("\x1f")]
            writer.writerow(fields)
            rows += 1
    return rows


def snow_sql(connection: str, query: str) -> None:
    subprocess.run(["snow", "sql", "-c", connection, "-q", query], check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--connection", default="sf_bifrost")
    parser.add_argument("--dry-run", action="store_true",
                        help="export from SQL Server only; skip Snowflake load")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="tastybytes_mig_") as tmp:
        tmpdir = pathlib.Path(tmp)
        if not args.dry_run:
            snow_sql(args.connection,
                     "CREATE STAGE IF NOT EXISTS tastybytesdb.etl_results.mig_stage "
                     "FILE_FORMAT=(TYPE=CSV FIELD_OPTIONALLY_ENCLOSED_BY='\"' EMPTY_FIELD_AS_NULL=TRUE)")
        for table, query in TABLES.items():
            csv_path = tmpdir / (table.replace(".", "_") + ".csv")
            rows = export_table(query, csv_path)
            print(f"exported {table}: {rows} rows")
            if args.dry_run:
                continue
            snow_sql(args.connection,
                     f"PUT file://{csv_path} @tastybytesdb.etl_results.mig_stage "
                     "AUTO_COMPRESS=TRUE OVERWRITE=TRUE")
            binary_opt = " BINARY_FORMAT=HEX" if table == "tastybytes.MenuItem" else ""
            snow_sql(args.connection,
                     f"COPY INTO tastybytesdb.{table} FROM @tastybytesdb.etl_results.mig_stage/"
                     f"{csv_path.name}.gz FILE_FORMAT=(TYPE=CSV "
                     f"FIELD_OPTIONALLY_ENCLOSED_BY='\"' EMPTY_FIELD_AS_NULL=TRUE NULL_IF=('')"
                     f"{binary_opt}) ON_ERROR=ABORT_STATEMENT FORCE=TRUE")
            print(f"loaded {table}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
