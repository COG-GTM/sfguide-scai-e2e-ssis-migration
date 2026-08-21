#!/usr/bin/env bash
# Start a local SQL Server instance in Docker and deploy the Tasty Bytes source database.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER_NAME="${MSSQL_CONTAINER:-mssql}"
MSSQL_IMAGE="${MSSQL_IMAGE:-mcr.microsoft.com/mssql/server:2022-latest}"
MSSQL_PORT="${MSSQL_PORT:-1433}"
MSSQL_SA_PASSWORD="${MSSQL_SA_PASSWORD:-SnowflakeMigrations2026!}"
SQLCMD="${SQLCMD:-/opt/mssql-tools18/bin/sqlcmd}"

if ! command -v "$SQLCMD" >/dev/null 2>&1 && [ ! -x "$SQLCMD" ]; then
    echo "sqlcmd not found at $SQLCMD. Install mssql-tools18 (see README)." >&2
    exit 1
fi

if [ -z "$(docker ps -q -f "name=^${CONTAINER_NAME}$")" ]; then
    if [ -n "$(docker ps -aq -f "name=^${CONTAINER_NAME}$")" ]; then
        docker start "$CONTAINER_NAME" >/dev/null
    else
        docker run -d --name "$CONTAINER_NAME" \
            -e ACCEPT_EULA=Y \
            -e MSSQL_SA_PASSWORD="$MSSQL_SA_PASSWORD" \
            -e MSSQL_PID=Developer \
            -p "${MSSQL_PORT}:1433" \
            "$MSSQL_IMAGE" >/dev/null
    fi
fi

echo "Waiting for SQL Server on localhost,${MSSQL_PORT} ..."
for _ in $(seq 1 60); do
    if "$SQLCMD" -S "localhost,${MSSQL_PORT}" -U sa -P "$MSSQL_SA_PASSWORD" -C -N -Q "SELECT 1" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
"$SQLCMD" -S "localhost,${MSSQL_PORT}" -U sa -P "$MSSQL_SA_PASSWORD" -C -N -b -Q "SELECT @@VERSION" >/dev/null

for script in 00_ddl.sql 01_data.sql 02_user.sql; do
    echo "--- applying source_db/${script}"
    "$SQLCMD" -S "localhost,${MSSQL_PORT}" -U sa -P "$MSSQL_SA_PASSWORD" -C -N -b \
        -i "${REPO_ROOT}/source_db/${script}" >/dev/null
done

echo "Tasty Bytes source database is deployed and ready."
