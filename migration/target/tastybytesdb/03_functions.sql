/*******************************************************************************
 * TASTY BYTES — Converted user-defined functions
 *
 * fn_FormatCustomerName: T-SQL scalar UDF with an embedded SELECT converted to
 * a Snowflake scalar SQL UDF using a subquery. ISNULL -> COALESCE,
 * RTRIM(LTRIM()) -> TRIM, + concatenation -> ||.
 ******************************************************************************/
USE DATABASE tastybytesdb;

CREATE OR REPLACE FUNCTION tastybytes.fn_FormatCustomerName(P_CUSTOMERID INT)
RETURNS VARCHAR(402)
AS
$$
    (
        SELECT CAST(
                   UPPER(TRIM(COALESCE(LastName, ''))) ||
                   ', ' ||
                   TRIM(COALESCE(FirstName, ''))
               AS VARCHAR(402))
        FROM tastybytes.Customer
        WHERE CustomerID = P_CUSTOMERID
    )
$$;
