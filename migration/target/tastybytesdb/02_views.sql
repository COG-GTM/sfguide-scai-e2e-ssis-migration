/*******************************************************************************
 * TASTY BYTES — Converted views
 *
 * SSC-EWI-TS0006 resolution: T-SQL `SELECT TOP 1 PERCENT ... ORDER BY` has no
 * direct Snowflake equivalent. Each branch is rewritten with window functions:
 * ROW_NUMBER() over the same ORDER BY, kept while rank <= CEIL(1% of rows).
 * This matches SQL Server TOP PERCENT semantics (at least one row returned).
 ******************************************************************************/
USE DATABASE tastybytesdb;

CREATE OR REPLACE VIEW tastybytes.vw_TopSellingItems
AS
    WITH item_sales AS (
        SELECT
            mi.MenuItemID, mi.ItemName,
            SUM(od.Quantity)                AS TotalQuantitySold,
            SUM(od.Quantity * od.UnitPrice) AS TotalRevenue
        FROM tastybytes.OrderDetail od
        INNER JOIN tastybytes.OrderHeader oh ON od.OrderID = oh.OrderID
        INNER JOIN tastybytes.MenuItem  mi ON od.MenuItemID = mi.MenuItemID
        WHERE oh.OrderStatus = 'Completed'
        GROUP BY mi.MenuItemID, mi.ItemName
    )
    SELECT MenuItemID, ItemName, TotalQuantitySold, TotalRevenue,
           'By Quantity' AS RankingBasis
    FROM item_sales
    QUALIFY ROW_NUMBER() OVER (ORDER BY TotalQuantitySold DESC, MenuItemID)
            <= CEIL(COUNT(*) OVER () * 0.01)
    UNION
    SELECT MenuItemID, ItemName, TotalQuantitySold, TotalRevenue,
           'By Revenue' AS RankingBasis
    FROM item_sales
    QUALIFY ROW_NUMBER() OVER (ORDER BY TotalRevenue DESC, MenuItemID)
            <= CEIL(COUNT(*) OVER () * 0.01);
