/*******************************************************************************
 * TASTY BYTES — Access controls (converted from source_db/02_user.sql)
 *
 * SQL Server demo_user had database-wide SELECT + EXECUTE + VIEW DEFINITION
 * on TastyBytesDB. Snowflake equivalent: DEMO_USER login + TASTYBYTES_READER
 * role with USAGE on db/schemas/warehouse, SELECT on all current and FUTURE
 * tables/views, and USAGE on all current and future functions/procedures.
 ******************************************************************************/
USE ROLE accountadmin;

CREATE ROLE IF NOT EXISTS TASTYBYTES_READER
    COMMENT = 'Read-only + execute role equivalent to SQL Server demo_user';

GRANT USAGE ON DATABASE tastybytesdb TO ROLE TASTYBYTES_READER;
GRANT USAGE ON ALL SCHEMAS IN DATABASE tastybytesdb TO ROLE TASTYBYTES_READER;
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE tastybytesdb TO ROLE TASTYBYTES_READER;
GRANT USAGE ON WAREHOUSE XSMALL_WH TO ROLE TASTYBYTES_READER;

-- SELECT on all tables and views (existing + future) — mirrors
-- GRANT SELECT ON DATABASE::[tastybytesdb]
GRANT SELECT ON ALL TABLES IN DATABASE tastybytesdb TO ROLE TASTYBYTES_READER;
GRANT SELECT ON FUTURE TABLES IN DATABASE tastybytesdb TO ROLE TASTYBYTES_READER;
GRANT SELECT ON ALL VIEWS IN DATABASE tastybytesdb TO ROLE TASTYBYTES_READER;
GRANT SELECT ON FUTURE VIEWS IN DATABASE tastybytesdb TO ROLE TASTYBYTES_READER;

-- EXECUTE on procs/UDFs (existing + future) — mirrors
-- GRANT EXECUTE ON DATABASE::[tastybytesdb]
GRANT USAGE ON ALL FUNCTIONS IN DATABASE tastybytesdb TO ROLE TASTYBYTES_READER;
GRANT USAGE ON FUTURE FUNCTIONS IN DATABASE tastybytesdb TO ROLE TASTYBYTES_READER;
GRANT USAGE ON ALL PROCEDURES IN DATABASE tastybytesdb TO ROLE TASTYBYTES_READER;
GRANT USAGE ON FUTURE PROCEDURES IN DATABASE tastybytesdb TO ROLE TASTYBYTES_READER;

-- VIEW DEFINITION has no direct equivalent; USAGE on the database/schemas
-- already exposes object metadata to the role.

-- Login equivalent of the SQL Server demo_user (set a real password at deploy
-- time; do not commit credentials).
CREATE USER IF NOT EXISTS DEMO_USER
    DEFAULT_ROLE = TASTYBYTES_READER
    DEFAULT_WAREHOUSE = XSMALL_WH
    DEFAULT_NAMESPACE = 'TASTYBYTESDB.TASTYBYTES'
    MUST_CHANGE_PASSWORD = TRUE;

GRANT ROLE TASTYBYTES_READER TO USER DEMO_USER;
