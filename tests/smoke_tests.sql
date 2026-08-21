-- =============================================================================
-- Smoke tests for the Tasty Bytes SQL Server source database.
-- Run with scripts/run_tests.sh. Any failed assertion raises a fatal error so
-- sqlcmd -b exits non-zero.
-- =============================================================================
SET NOCOUNT ON;
USE [TastyBytesDB];
GO

DECLARE @failures INT = 0;

-- ---------------------------------------------------------------------------
-- 1. Schemas and object inventory
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'TastyBytes')
BEGIN PRINT 'FAIL: schema TastyBytes missing'; SET @failures += 1; END
ELSE PRINT 'PASS: schema TastyBytes exists';

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'etl_results')
BEGIN PRINT 'FAIL: schema etl_results missing'; SET @failures += 1; END
ELSE PRINT 'PASS: schema etl_results exists';

DECLARE @tables INT = (
    SELECT COUNT(*) FROM sys.tables t
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE s.name IN ('TastyBytes', 'etl_results'));
IF @tables < 11
BEGIN PRINT CONCAT('FAIL: expected >= 11 tables, found ', @tables); SET @failures += 1; END
ELSE PRINT CONCAT('PASS: ', @tables, ' tables deployed');

IF OBJECT_ID('TastyBytes.vw_TopSellingItems', 'V') IS NULL
BEGIN PRINT 'FAIL: view vw_TopSellingItems missing'; SET @failures += 1; END
ELSE PRINT 'PASS: view vw_TopSellingItems exists';

IF OBJECT_ID('TastyBytes.fn_FormatCustomerName', 'FN') IS NULL
BEGIN PRINT 'FAIL: function fn_FormatCustomerName missing'; SET @failures += 1; END
ELSE PRINT 'PASS: function fn_FormatCustomerName exists';

IF OBJECT_ID('TastyBytes.sp_UpdateInventory', 'P') IS NULL
BEGIN PRINT 'FAIL: procedure sp_UpdateInventory missing'; SET @failures += 1; END
ELSE PRINT 'PASS: procedure sp_UpdateInventory exists';

-- ---------------------------------------------------------------------------
-- 2. Sample data loaded in every table
-- ---------------------------------------------------------------------------
DECLARE @empty NVARCHAR(MAX) = '';
SELECT @empty = @empty + s.name + '.' + t.name + ' '
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
CROSS APPLY (
    SELECT SUM(p.rows) AS rows
    FROM sys.partitions p
    WHERE p.object_id = t.object_id AND p.index_id IN (0, 1)
) c
WHERE s.name = 'TastyBytes' AND ISNULL(c.rows, 0) = 0;

IF LEN(@empty) > 0
BEGIN PRINT CONCAT('FAIL: empty TastyBytes tables: ', @empty); SET @failures += 1; END
ELSE PRINT 'PASS: every TastyBytes table has rows';

-- ---------------------------------------------------------------------------
-- 3. Referential integrity of the order data
-- ---------------------------------------------------------------------------
IF EXISTS (
    SELECT 1 FROM TastyBytes.OrderDetail od
    LEFT JOIN TastyBytes.OrderHeader oh ON oh.OrderID = od.OrderID
    WHERE oh.OrderID IS NULL)
BEGIN PRINT 'FAIL: OrderDetail rows without a parent OrderHeader'; SET @failures += 1; END
ELSE PRINT 'PASS: OrderDetail references resolve to OrderHeader';

IF EXISTS (
    SELECT 1 FROM TastyBytes.OrderDetail od
    LEFT JOIN TastyBytes.MenuItem mi ON mi.MenuItemID = od.MenuItemID
    WHERE mi.MenuItemID IS NULL)
BEGIN PRINT 'FAIL: OrderDetail rows without a MenuItem'; SET @failures += 1; END
ELSE PRINT 'PASS: OrderDetail references resolve to MenuItem';

-- ---------------------------------------------------------------------------
-- 4. View returns data
-- ---------------------------------------------------------------------------
DECLARE @topSellers INT;
IF OBJECT_ID('TastyBytes.vw_TopSellingItems', 'V') IS NOT NULL
BEGIN
    SET @topSellers = (SELECT COUNT(*) FROM TastyBytes.vw_TopSellingItems);
    IF @topSellers = 0
    BEGIN PRINT 'FAIL: vw_TopSellingItems returned no rows'; SET @failures += 1; END
    ELSE PRINT CONCAT('PASS: vw_TopSellingItems returned ', @topSellers, ' rows');
END
ELSE PRINT 'SKIP: vw_TopSellingItems query (view missing)';

-- ---------------------------------------------------------------------------
-- 5. Scalar UDF formats "LASTNAME, Firstname"
-- ---------------------------------------------------------------------------
DECLARE @customerID INT, @expected NVARCHAR(402), @actual NVARCHAR(402);
IF OBJECT_ID('TastyBytes.fn_FormatCustomerName', 'FN') IS NOT NULL
BEGIN
    SET @customerID = (SELECT MIN(CustomerID) FROM TastyBytes.Customer);
    SET @expected = (
        SELECT UPPER(RTRIM(LTRIM(ISNULL(LastName, '')))) + ', ' + RTRIM(LTRIM(ISNULL(FirstName, '')))
        FROM TastyBytes.Customer WHERE CustomerID = @customerID);
    SET @actual = TastyBytes.fn_FormatCustomerName(@customerID);
    IF @actual IS NULL OR @actual <> @expected
    BEGIN PRINT CONCAT('FAIL: fn_FormatCustomerName returned ', ISNULL(@actual, 'NULL'), ' expected ', @expected); SET @failures += 1; END
    ELSE PRINT CONCAT('PASS: fn_FormatCustomerName returned ', @actual);
END
ELSE PRINT 'SKIP: fn_FormatCustomerName call (function missing)';

-- ---------------------------------------------------------------------------
-- 6. sp_UpdateInventory override and increment modes
-- ---------------------------------------------------------------------------
DECLARE @truckID INT = (SELECT MIN(TruckID) FROM TastyBytes.Inventory);

IF OBJECT_ID('TastyBytes.sp_UpdateInventory', 'P') IS NULL
    PRINT 'SKIP: sp_UpdateInventory behaviour (procedure missing)';
ELSE
BEGIN
BEGIN TRANSACTION;
    EXEC TastyBytes.sp_UpdateInventory @TruckID = @truckID, @StockCount = 500, @Override = 1;
    IF EXISTS (SELECT 1 FROM TastyBytes.Inventory WHERE TruckID = @truckID AND QuantityOnHand <> 500)
    BEGIN PRINT 'FAIL: sp_UpdateInventory @Override = 1 did not set QuantityOnHand'; SET @failures += 1; END
    ELSE PRINT 'PASS: sp_UpdateInventory @Override = 1 sets QuantityOnHand';

    EXEC TastyBytes.sp_UpdateInventory @TruckID = @truckID, @StockCount = 25, @Override = 0;
    IF EXISTS (SELECT 1 FROM TastyBytes.Inventory WHERE TruckID = @truckID AND QuantityOnHand <> 525)
    BEGIN PRINT 'FAIL: sp_UpdateInventory @Override = 0 did not increment QuantityOnHand'; SET @failures += 1; END
    ELSE PRINT 'PASS: sp_UpdateInventory @Override = 0 increments QuantityOnHand';
ROLLBACK TRANSACTION;
END

-- ---------------------------------------------------------------------------
-- 7. ETL log table is writable (used by the SSIS packages)
-- ---------------------------------------------------------------------------
BEGIN TRANSACTION;
    INSERT INTO etl_results.etl_logs (name, execution_date)
    VALUES ('smoke_test start execution', CURRENT_TIMESTAMP);
    IF NOT EXISTS (SELECT 1 FROM etl_results.etl_logs WHERE name = 'smoke_test start execution')
    BEGIN PRINT 'FAIL: could not insert into etl_results.etl_logs'; SET @failures += 1; END
    ELSE PRINT 'PASS: etl_results.etl_logs accepts ETL markers';
ROLLBACK TRANSACTION;

-- ---------------------------------------------------------------------------
-- 8. demo_user login exists with SELECT/EXECUTE grants
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'demo_user')
BEGIN PRINT 'FAIL: demo_user database principal missing'; SET @failures += 1; END
ELSE IF (
    SELECT COUNT(*) FROM sys.database_permissions perm
    JOIN sys.database_principals p ON p.principal_id = perm.grantee_principal_id
    WHERE p.name = 'demo_user' AND perm.permission_name IN ('SELECT', 'EXECUTE')
      AND perm.state_desc = 'GRANT') < 2
BEGIN PRINT 'FAIL: demo_user is missing SELECT/EXECUTE grants'; SET @failures += 1; END
ELSE PRINT 'PASS: demo_user exists with SELECT and EXECUTE grants';

-- ---------------------------------------------------------------------------
IF @failures > 0
    RAISERROR('%d smoke test(s) failed', 16, 1, @failures);
ELSE
    PRINT 'All smoke tests passed.';
GO
