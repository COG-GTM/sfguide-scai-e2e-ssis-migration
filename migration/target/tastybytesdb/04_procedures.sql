/*******************************************************************************
 * TASTY BYTES — Converted stored procedures
 *
 * sp_UpdateInventory: converted to Snowflake SQL Scripting.
 * SET NOCOUNT ON dropped (no-op in Snowflake); BIT parameter -> BOOLEAN;
 * bare RETURN -> RETURN NULL.
 ******************************************************************************/
USE DATABASE tastybytesdb;

CREATE OR REPLACE PROCEDURE tastybytes.sp_UpdateInventory(
    TRUCKID     INT             DEFAULT NULL,
    STOCKCOUNT  DECIMAL(10, 2)  DEFAULT 0,
    OVERRIDE    BOOLEAN         DEFAULT TRUE
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    IF (:TRUCKID IS NULL) THEN
        RETURN NULL;
    END IF;

    IF (:OVERRIDE) THEN
        UPDATE tastybytes.Inventory
        SET QuantityOnHand = :STOCKCOUNT
        WHERE TruckID = :TRUCKID;
    ELSE
        UPDATE tastybytes.Inventory
        SET QuantityOnHand = QuantityOnHand + :STOCKCOUNT
        WHERE TruckID = :TRUCKID;
    END IF;

    RETURN NULL;
END;
$$;
