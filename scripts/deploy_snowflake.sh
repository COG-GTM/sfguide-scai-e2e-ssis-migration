#!/usr/bin/env bash
# Deploy the converted Tasty Bytes objects to Snowflake and run the migration.
#
# Prereqs: `snow` CLI (pip install snowflake-cli) with an ACCOUNTADMIN-capable
# connection configured (default name: sf_bifrost, matching
# migration/.scai/config/project.yml):
#   snow connection add sf_bifrost --account <acct> --user <user> ...
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONNECTION="${SNOWFLAKE_CONNECTION:-sf_bifrost}"

run_sql() {
    echo "--- applying $1"
    snow sql -c "$CONNECTION" -f "$1"
}

# 1. Infrastructure: database, schemas, warehouse, compute pool
run_sql "${REPO_ROOT}/snowflake/init.sql"

# 2. Converted schema and code
run_sql "${REPO_ROOT}/migration/target/tastybytesdb/01_tables.sql"
run_sql "${REPO_ROOT}/migration/target/tastybytesdb/02_views.sql"
run_sql "${REPO_ROOT}/migration/target/tastybytesdb/03_functions.sql"
run_sql "${REPO_ROOT}/migration/target/tastybytesdb/04_procedures.sql"
run_sql "${REPO_ROOT}/migration/target/tastybytesdb/05_etl_daily_sales_agg.sql"
run_sql "${REPO_ROOT}/migration/target/tastybytesdb/06_access_control.sql"

# 3. Data migration from the local SQL Server source
python3 "${REPO_ROOT}/scripts/migrate_data.py" --connection "$CONNECTION"

# 4. Run the converted ETL once, then validate
snow sql -c "$CONNECTION" -q "CALL tastybytesdb.etl_results.sp_daily_sales_aggregate();"
python3 "${REPO_ROOT}/scripts/validate_migration.py" --connection "$CONNECTION"

echo "Deployment and validation complete."
