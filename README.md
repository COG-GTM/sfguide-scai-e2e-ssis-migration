# sfguide-scai-e2e-ssis-migration

Sample code for an End-to-End migration of SQL Server and SSIS using SnowConvert AI.

## Repository structure

```
sfguide-scai-e2e-ssis-migration/
├── source_db/      SQL Server source database scripts (DDL + sample data)
│   ├── 00_ddl.sql        Schema, tables, views, functions, and stored procedures
│   └── 01_data.sql       Sample data inserts for all tables
├── snowflake/      Snowflake target setup
│   └── init.sql          Database, schemas, warehouse, and compute pool
└── etl/            SSIS package samples
    ├── daily_sales_agg.dtsx          Aggregates daily sales into reporting tables
    └── update_truck_inventories.dtsx Refreshes per-truck inventory levels
```

## Source SQL Server database

The source workload is the fictional **Tasty Bytes** global food truck network: localized menus, customer loyalty, order management, inventory tracking, and employee scheduling. The DDL deliberately uses T-SQL constructs (computed columns, `ROWVERSION`, `MONEY`, `NTEXT`, `UNIQUEIDENTIFIER`, NOLOCK hints, GLOBAL cursors, etc.) that surface SnowConvert EWIs during migration.

To deploy the SQL Server sample database, run the following scripts in order against your SQL Server instance:

1. `source_db/00_ddl.sql` — creates the `TastyBytesDB` database, the `TastyBytes` and `etl_results` schemas, and all tables, views, user-defined functions, and stored procedures.
2. `source_db/01_data.sql` — populates the tables with sample data in dependency order.
3. `source_db/02_user.sql` — creates the read-only + execute `demo_user` login used by the migration tooling.

### Local setup (Docker)

Prerequisites: Docker and the Microsoft SQL Server command line tools.

```bash
curl -sSL -o /tmp/msprod.deb https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb
sudo dpkg -i /tmp/msprod.deb
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y mssql-tools18 unixodbc-dev
```

Then start SQL Server and deploy the sample database:

```bash
./scripts/setup_source_db.sh   # starts the mssql container and applies all three scripts
./scripts/run_tests.sh         # smoke tests: objects, sample data, view, UDF, procedure, grants
python3 scripts/validate_etl_packages.py
```

The scripts default to `localhost,1433` with the `sa` password `SnowflakeMigrations2026!`; override with
`MSSQL_PORT`, `MSSQL_SA_PASSWORD`, `MSSQL_CONTAINER`, or `SQLCMD`. `setup_source_db.sh` is idempotent —
`00_ddl.sql` recreates `TastyBytesDB` from scratch on every run.

Query the running database as the demo user:

```bash
/opt/mssql-tools18/bin/sqlcmd -S localhost,1433 -U demo_user -P 'SnowflakeMigrations2026!' -C -N \
    -d TastyBytesDB -Q "SELECT * FROM TastyBytes.vw_TopSellingItems"
```

## Snowflake target

On the Snowflake side, only run `snowflake/init.sql`. It uses `ACCOUNTADMIN` to create:

- The `tastybytesdb` database with `tastybytes` and `etl_results` schemas
- The `XSMALL_WH` warehouse
- The `TASTYBYTES_MIG_POOL` compute pool used by the data migration job

## ETL (SSIS) packages

The `etl/` folder contains the source SSIS packages used in the migration walkthrough:

- **`daily_sales_agg.dtsx`** — Reads completed orders from `TastyBytes.OrderHeader` / `OrderDetail`, aggregates daily revenue and order counts per truck, and writes the rollups to a reporting table. Brackets the run with `start execution` / `endexecution` markers in `etl_results.etl_logs`.
- **`update_truck_inventories.dtsx`** — Iterates over operational food trucks, applies inventory adjustments based on recent orders, and updates `TastyBytes.Inventory` (quantity on hand, last restocked, reorder triggers).

These `.dtsx` files are the inputs migrated by SnowConvert AI to equivalent Snowflake-native ETL.
