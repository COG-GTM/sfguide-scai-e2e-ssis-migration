/*******************************************************************************
 * TASTY BYTES — Converted Snowflake DDL (from source_db/00_ddl.sql, T-SQL)
 *
 * Type mappings and EWI resolutions are documented in docs/EWI_RESOLUTIONS.md.
 * Run after snowflake/init.sql (database/schemas already exist).
 ******************************************************************************/
USE DATABASE tastybytesdb;
USE SCHEMA tastybytes;

-- ----------------------------------------------------------------------------
-- etl_results.etl_logs
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE etl_results.etl_logs (
    LogID           INT IDENTITY(1,1),
    name            VARCHAR(200) NOT NULL,
    execution_date  TIMESTAMP_NTZ NOT NULL
);

-- ----------------------------------------------------------------------------
-- 1. Country
--    FDM-TS0014: computed column DisplayName replaced by the same expression
--    evaluated at INSERT time via DEFAULT; the loader recomputes it explicitly.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE tastybytes.Country (
    CountryID       INT IDENTITY(1,1),
    CountryName     VARCHAR(100) NOT NULL,
    CountryCode     CHAR(3) NOT NULL,
    CurrencyCode    CHAR(3) NOT NULL,
    TaxRate         DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    DisplayName     VARCHAR(9),           -- was: AS (CountryCode + N' - ' + CurrencyCode)
    IsActive        BOOLEAN NOT NULL DEFAULT TRUE,
    CreatedAt       TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    ModifiedAt      TIMESTAMP_NTZ NULL
);

-- ----------------------------------------------------------------------------
-- 2. City
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE tastybytes.City (
    CityID          INT IDENTITY(1,1),
    CityName        VARCHAR(150) NOT NULL,
    CountryID       INT NOT NULL,
    StateProvince   VARCHAR(100) NULL,
    Latitude        DECIMAL(9,6) NULL,
    Longitude       DECIMAL(9,6) NULL,
    PopulationSize  INT NULL,
    CreatedAt       TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- ----------------------------------------------------------------------------
-- 3. FoodTruck
--    ROWGUIDCOL dropped (no Snowflake equivalent);
--    UNIQUEIDENTIFIER DEFAULT NEWID() -> VARCHAR(36) DEFAULT UUID_STRING().
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE tastybytes.FoodTruck (
    TruckID         INT IDENTITY(1,1),
    TruckGUID       VARCHAR(36) NOT NULL DEFAULT UUID_STRING(),
    TruckName       VARCHAR(200) NOT NULL,
    LicensePlate    VARCHAR(20) NOT NULL,
    CityID          INT NOT NULL,
    TruckConfig     VARCHAR NULL,
    YearPurchased   INT NULL,
    MaxCapacity     INT NOT NULL DEFAULT 500,
    IsOperational   BOOLEAN NOT NULL DEFAULT TRUE,
    CreatedAt       TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    ModifiedAt      TIMESTAMP_NTZ NULL
);

-- ----------------------------------------------------------------------------
-- 4. Menu
--    NTEXT (deprecated) -> VARCHAR; MONEY -> NUMBER(19,4).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE tastybytes.Menu (
    MenuID          INT IDENTITY(1,1),
    MenuName        VARCHAR(200) NOT NULL,
    TruckID         INT NOT NULL,
    CuisineType     VARCHAR(100) NOT NULL,
    MenuDescription VARCHAR NULL,
    BasePriceTier   NUMBER(19,4) NOT NULL DEFAULT 0.00,
    IsSeasonalMenu  BOOLEAN NOT NULL DEFAULT FALSE,
    EffectiveFrom   DATE NOT NULL DEFAULT CURRENT_DATE(),
    EffectiveTo     DATE NULL,
    CreatedAt       TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- ----------------------------------------------------------------------------
-- 5. MenuItem
--    FDM-TS0014: computed column PriceWithTax materialized by the loader.
--    ROWVERSION has no Snowflake equivalent: kept as BINARY(8) so migrated
--    values survive; new rows rely on Time Travel / streams for concurrency.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE tastybytes.MenuItem (
    MenuItemID      INT IDENTITY(1,1),
    MenuID          INT NOT NULL,
    ItemName        VARCHAR(200) NOT NULL,
    ItemDescription VARCHAR NULL,
    BasePrice       NUMBER(19,4) NOT NULL,
    CalorieCount    INT NULL,
    IsVegetarian    BOOLEAN NOT NULL DEFAULT FALSE,
    IsGlutenFree    BOOLEAN NOT NULL DEFAULT FALSE,
    IsSpicy         BOOLEAN NOT NULL DEFAULT FALSE,
    PriceWithTax    DECIMAL(10,2),        -- was: AS (CAST(BasePrice * 1.08 AS DECIMAL(10,2)))
    RowVer          BINARY(8),            -- was: ROWVERSION
    CreatedAt       TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- ----------------------------------------------------------------------------
-- 6. Customer
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE tastybytes.Customer (
    CustomerID      INT IDENTITY(1,1),
    CustomerGUID    VARCHAR(36) NOT NULL DEFAULT UUID_STRING(),
    FirstName       VARCHAR(100) NOT NULL,
    LastName        VARCHAR(100) NOT NULL,
    Email           VARCHAR(255) NULL,
    PhoneNumber     VARCHAR(20) NULL,
    PreferredCityID INT NULL,
    LoyaltyPoints   INT NOT NULL DEFAULT 0,
    MemberSince     DATE NOT NULL DEFAULT CURRENT_DATE(),
    IsActive        BOOLEAN NOT NULL DEFAULT TRUE,
    CreatedAt       TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    ModifiedAt      TIMESTAMP_NTZ NULL
);

-- ----------------------------------------------------------------------------
-- 7. OrderHeader
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE tastybytes.OrderHeader (
    OrderID         INT IDENTITY(1,1),
    CustomerID      INT NOT NULL,
    TruckID         INT NOT NULL,
    OrderDate       TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CompletedAt     TIMESTAMP_NTZ NULL,
    OrderStatus     VARCHAR(20) NOT NULL DEFAULT 'Pending',
    TotalAmount     NUMBER(19,4) NOT NULL DEFAULT 0.00,
    TipAmount       NUMBER(19,4) NULL DEFAULT 0.00,
    PaymentMethod   VARCHAR(30) NULL,
    OrderNotes      VARCHAR(500) NULL,
    CreatedAt       TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    ModifiedAt      TIMESTAMP_NTZ NULL
);

-- ----------------------------------------------------------------------------
-- 8. OrderDetail
--    SMALLMONEY -> NUMBER(10,4); computed LineTotal materialized by the loader.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE tastybytes.OrderDetail (
    OrderID         INT NOT NULL,
    LineNumber      INT NOT NULL,
    MenuItemID      INT NOT NULL,
    Quantity        INT NOT NULL DEFAULT 1,
    UnitPrice       NUMBER(10,4) NOT NULL,
    Discount        NUMBER(10,4) NOT NULL DEFAULT 0.00,
    LineTotal       DECIMAL(10,2),        -- was: AS (CAST((Quantity * UnitPrice) - Discount AS DECIMAL(10,2)))
    SpecialRequests VARCHAR(300) NULL
);

-- ----------------------------------------------------------------------------
-- 9. Inventory
--    SPARSE storage attribute dropped (Snowflake columnar storage handles
--    sparse data natively).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE tastybytes.Inventory (
    InventoryID     INT IDENTITY(1,1),
    TruckID         INT NOT NULL,
    IngredientName  VARCHAR(200) NOT NULL,
    QuantityOnHand  DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    UnitOfMeasure   VARCHAR(20) NOT NULL,
    ReorderLevel    DECIMAL(10,2) NOT NULL DEFAULT 10.00,
    SupplierNotes   VARCHAR(500) NULL
);

-- ----------------------------------------------------------------------------
-- 10. EmployeeShift
--     Computed HoursWorked materialized by the loader.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE tastybytes.EmployeeShift (
    ShiftID         INT IDENTITY(1,1),
    EmployeeName    VARCHAR(200) NOT NULL,
    TruckID         INT NOT NULL,
    ShiftDate       DATE NOT NULL,
    StartTime       TIMESTAMP_NTZ NOT NULL,
    EndTime         TIMESTAMP_NTZ NOT NULL,
    HoursWorked     NUMBER(20,6),         -- was: AS (DATEDIFF(MINUTE, StartTime, EndTime) / 60.0)
    Role            VARCHAR(50) NOT NULL DEFAULT 'Cook',
    HourlyRate      NUMBER(10,4) NOT NULL,
    CreatedAt       TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- ----------------------------------------------------------------------------
-- 11. DailySalesAgg — reporting table targeted by the daily_sales_agg SSIS
--     package (created implicitly on SQL Server; defined explicitly here from
--     the package's OLE DB Destination external metadata).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE tastybytes.DailySalesAgg (
    SaleDate        DATE NOT NULL,
    TruckID         INT NOT NULL,
    OrderCount      INT NOT NULL,
    GrossRevenue    NUMBER(18,4) NOT NULL,
    TotalTips       NUMBER(18,4) NOT NULL,
    ItemsSold       INT NOT NULL,
    LoadedAt        TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
);
