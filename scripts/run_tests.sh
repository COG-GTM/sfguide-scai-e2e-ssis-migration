#!/usr/bin/env bash
# Run the SQL smoke tests against the deployed Tasty Bytes source database.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MSSQL_PORT="${MSSQL_PORT:-1433}"
MSSQL_SA_PASSWORD="${MSSQL_SA_PASSWORD:-SnowflakeMigrations2026!}"
SQLCMD="${SQLCMD:-/opt/mssql-tools18/bin/sqlcmd}"

"$SQLCMD" -S "localhost,${MSSQL_PORT}" -U sa -P "$MSSQL_SA_PASSWORD" -C -N -b \
    -d TastyBytesDB -i "${REPO_ROOT}/tests/smoke_tests.sql"
