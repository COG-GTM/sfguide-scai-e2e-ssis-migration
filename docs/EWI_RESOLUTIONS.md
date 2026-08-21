# SnowConvert EWI Resolutions — Tasty Bytes Migration

Converted output lives in `migration/target/tastybytesdb/`. Every deliberately
problematic T-SQL construct in `source_db/00_ddl.sql` is resolved as follows.

| # | Construct (EWI) | Location | Resolution |
|---|-----------------|----------|------------|
| 1 | Computed columns (FDM-TS0014): `DisplayName`, `PriceWithTax`, `LineTotal`, `HoursWorked` | Country, MenuItem, OrderDetail, EmployeeShift | Snowflake has no computed columns. Converted to regular columns; `scripts/migrate_data.py` exports the *evaluated* values from SQL Server so migrated data is fully materialized. New inserts must compute the expressions (documented inline in `01_tables.sql`); parity is asserted by the "computed column parity" checks in `scripts/validate_migration.py`. |
| 2 | `ROWVERSION` (`MenuItem.RowVer`) | MenuItem | No Snowflake equivalent. Mapped to `BINARY(8)`; source values migrated as hex so history is preserved. Optimistic-concurrency semantics are replaced by Snowflake Time Travel / streams. |
| 3 | `MONEY` / `SMALLMONEY` | Menu, MenuItem, OrderHeader, OrderDetail, EmployeeShift | Mapped to `NUMBER(19,4)` / `NUMBER(10,4)` (exact scale of the SQL Server types — no precision loss). |
| 4 | `NTEXT` (deprecated) (`Menu.MenuDescription`) | Menu | Mapped to `VARCHAR` (16 MB max). Export casts to `NVARCHAR(MAX)` since `NTEXT` cannot be concatenated/compared directly. |
| 5 | `UNIQUEIDENTIFIER` + `NEWID()` (`TruckGUID`, `CustomerGUID`) | FoodTruck, Customer | Mapped to `VARCHAR(36) DEFAULT UUID_STRING()`. Values migrated lowercased for canonical comparison. |
| 6 | `ROWGUIDCOL` | FoodTruck.TruckGUID | Attribute dropped — replication-oriented, no Snowflake meaning. |
| 7 | `SPARSE` (`Inventory.SupplierNotes`) | Inventory | Keyword dropped — Snowflake columnar storage compresses sparse data natively. |
| 8 | `IDENTITY(1,1)` | all tables | Kept as Snowflake `IDENTITY(1,1)` (autoincrement). Existing key values are bulk-loaded verbatim; note Snowflake sequences may leave gaps and the loaded values do not advance the sequence — reseed with `ALTER TABLE ... ALTER COLUMN ... SET` or start sequences above MAX(id) before accepting new writes. |
| 9 | `BIT` | all tables | Mapped to `BOOLEAN`. |
| 10 | `DATETIME` / `GETDATE()` | all tables | Mapped to `TIMESTAMP_NTZ` / `CURRENT_TIMESTAMP()` (`CURRENT_DATE()` for `DATE` defaults). |
| 11 | `TOP 1 PERCENT ... ORDER BY` (SSC-EWI-TS0006) | vw_TopSellingItems | Rewritten with `QUALIFY ROW_NUMBER() OVER (ORDER BY ...) <= CEIL(COUNT(*) OVER () * 0.01)`, matching SQL Server TOP PERCENT semantics (ceiling, at least 1 row). |
| 12 | Scalar UDF with embedded SELECT | fn_FormatCustomerName | Converted to a Snowflake scalar SQL UDF with a subquery. `ISNULL`→`COALESCE`, `RTRIM(LTRIM())`→`TRIM`, `+`→`||`. |
| 13 | `SET NOCOUNT ON`, bare `RETURN` | sp_UpdateInventory | Converted to SQL Scripting procedure; `SET NOCOUNT` dropped (no-op), `RETURN`→`RETURN NULL`. |
| 14 | `SET ANSI_PADDING/ANSI_WARNINGS OFF` (TS0002/TS0003) | end of 00_ddl.sql | Session-setting statements removed — not applicable to Snowflake. |
| 15 | `NOLOCK` hints / GLOBAL cursors | *(README only)* | Mentioned in README.md but **not present** in the current `source_db/00_ddl.sql` — nothing to convert. |

## SSIS packages

* **`etl/daily_sales_agg.dtsx`** → `migration/target/tastybytesdb/05_etl_daily_sales_agg.sql`:
  a SQL Scripting procedure `etl_results.sp_daily_sales_aggregate()` reproducing
  the package (start log → join/filter/convert/aggregate → FastLoad insert into
  `tastybytes.DailySalesAgg` → end log) plus a suspended serverless `TASK`
  (`tsk_daily_sales_aggregate`) for daily scheduling. Known source-package bug:
  both Execute SQL tasks insert the literal `'pkg_daily_sales_aggregate start'`;
  the conversion writes distinct `start`/`end` markers per the documented intent.
* **`etl/update_truck_inventories.dtsx`**: referenced in README.md but **missing
  from the repository** (`etl/` only contains `daily_sales_agg.dtsx`). Not
  converted; see note at the end of `05_etl_daily_sales_agg.sql`.

## Access control

`source_db/02_user.sql` (`demo_user`: database-wide SELECT + EXECUTE + VIEW
DEFINITION) → `06_access_control.sql`: role `TASTYBYTES_READER` with USAGE on
database/schemas/warehouse, SELECT on all current+future tables/views, USAGE on
all current+future functions/procedures, granted to user `DEMO_USER`.

## Deployment & validation

Live deployment was **not** executed in this change (no Snowflake credentials
provisioned — user opted to skip). When credentials are available:

```bash
snow connection add sf_bifrost ...   # ACCOUNTADMIN-capable
./scripts/deploy_snowflake.sh        # init + DDL + data migration + ETL run + validation
```

`scripts/validate_migration.py` implements the metrics validation configured in
`migration/.scai/settings/test_config.yaml` (row counts + key aggregates,
tolerance 0.001). Row-level validation remains available through SnowConvert
AI's cloud validation using the `sf_bifrost` connection.
