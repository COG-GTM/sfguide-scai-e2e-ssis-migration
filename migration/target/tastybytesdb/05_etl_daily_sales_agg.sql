/*******************************************************************************
 * TASTY BYTES — Snowflake-native ETL replacing etl/daily_sales_agg.dtsx
 *
 * Original SSIS control flow:
 *   insert_start_log (Execute SQL) -> df_load_daily_sales (Data Flow)
 *                                  -> insert_end_log (Execute SQL)
 *
 * Data flow: OrderHeader + OrderDetail (Merge Join on OrderID)
 *   -> Conditional Split (OrderStatus == "Completed")
 *   -> Data Conversion (OrderDate DT_DBTIMESTAMP -> SaleDate DT_DBDATE)
 *   -> Aggregate (GROUP BY TruckID, SaleDate; COUNT DISTINCT OrderID;
 *                 SUM TotalAmount / TipAmount / Quantity)
 *   -> OLE DB Destination FastLoad into [TastyBytes].[DailySalesAgg]
 *
 * Note: in the source package BOTH Execute SQL tasks insert the literal
 * 'pkg_daily_sales_aggregate start' (the end task was never updated). The
 * conversion honors the documented intent: distinct start/end markers.
 ******************************************************************************/
USE DATABASE tastybytesdb;

CREATE OR REPLACE PROCEDURE etl_results.sp_daily_sales_aggregate()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    -- insert_start_log
    INSERT INTO etl_results.etl_logs (name, execution_date)
    VALUES ('pkg_daily_sales_aggregate start', CURRENT_TIMESTAMP);

    -- df_load_daily_sales (FastLoad emulated as set-based INSERT ... SELECT)
    INSERT INTO tastybytes.DailySalesAgg
        (SaleDate, TruckID, OrderCount, GrossRevenue, TotalTips, ItemsSold, LoadedAt)
    SELECT
        CAST(oh.OrderDate AS DATE)          AS SaleDate,
        oh.TruckID                          AS TruckID,
        COUNT(DISTINCT oh.OrderID)          AS OrderCount,
        SUM(oh.TotalAmount)                 AS GrossRevenue,
        SUM(oh.TipAmount)                   AS TotalTips,
        SUM(od.Quantity)                    AS ItemsSold,
        CURRENT_TIMESTAMP()                 AS LoadedAt
    FROM tastybytes.OrderHeader oh
    INNER JOIN tastybytes.OrderDetail od ON od.OrderID = oh.OrderID
    WHERE oh.OrderStatus = 'Completed'
    GROUP BY CAST(oh.OrderDate AS DATE), oh.TruckID;

    -- insert_end_log
    INSERT INTO etl_results.etl_logs (name, execution_date)
    VALUES ('pkg_daily_sales_aggregate end', CURRENT_TIMESTAMP);

    RETURN 'pkg_daily_sales_aggregate completed';
END;
$$;

-- Scheduled equivalent of the SQL Agent / SSIS daily trigger. Created
-- suspended; enable with ALTER TASK ... RESUME after deployment.
CREATE OR REPLACE TASK etl_results.tsk_daily_sales_aggregate
    WAREHOUSE = XSMALL_WH
    SCHEDULE = 'USING CRON 0 2 * * * UTC'
AS
    CALL etl_results.sp_daily_sales_aggregate();

/*
 * NOTE: README.md also references etl/update_truck_inventories.dtsx, but that
 * package is NOT present in the repository (etl/ contains only
 * daily_sales_agg.dtsx). It was not converted; if the package is recovered,
 * mirror this pattern (log markers + set-based MERGE into tastybytes.Inventory
 * calling tastybytes.sp_UpdateInventory per truck).
 */
