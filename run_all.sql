/* run_all.sql: builds RetailDWH and loads + tests it in one go (SSMS: open and press F5). */

/* ######## sql/00_setup.sql ######## */
/* =====================================================================
   00_setup.sql
   Creates the RetailDWH database, the medallion schemas, and the ETL
   log used by every load procedure.

   Safe to run more than once. Uses a NEW database so your original
   DataWarehouse database is left untouched for comparison.
   ===================================================================== */

IF DB_ID('RetailDWH') IS NULL
    CREATE DATABASE RetailDWH;
GO

USE RetailDWH;
GO

IF SCHEMA_ID('bronze') IS NULL EXEC('CREATE SCHEMA bronze');
GO
IF SCHEMA_ID('silver') IS NULL EXEC('CREATE SCHEMA silver');
GO
IF SCHEMA_ID('gold')   IS NULL EXEC('CREATE SCHEMA gold');
GO
IF SCHEMA_ID('etl')    IS NULL EXEC('CREATE SCHEMA etl');
GO

/* ---------- One row per table per load step ---------- */
IF OBJECT_ID('etl.load_log', 'U') IS NULL
CREATE TABLE etl.load_log (
    log_id        INT IDENTITY(1,1) PRIMARY KEY,
    run_id        UNIQUEIDENTIFIER NOT NULL,
    layer         VARCHAR(10)      NOT NULL,   -- bronze / silver / gold
    table_name    VARCHAR(100)     NOT NULL,
    rows_in       INT              NULL,       -- rows read from the layer below
    rows_loaded   INT              NULL,
    rows_rejected AS (rows_in - rows_loaded),  -- dropped by cleaning rules
    status        VARCHAR(10)      NOT NULL,   -- Success / Failed
    message       NVARCHAR(2000)   NULL,
    started_at    DATETIME2(0)     NOT NULL,
    finished_at   DATETIME2(0)     NOT NULL DEFAULT SYSDATETIME()
);
GO

CREATE OR ALTER PROCEDURE etl.log_step
    @run_id      UNIQUEIDENTIFIER,
    @layer       VARCHAR(10),
    @table_name  VARCHAR(100),
    @rows_in     INT,
    @rows_loaded INT,
    @status      VARCHAR(10),
    @started_at  DATETIME2(0),
    @message     NVARCHAR(2000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO etl.load_log
        (run_id, layer, table_name, rows_in, rows_loaded, status, message, started_at)
    VALUES
        (@run_id, @layer, @table_name, @rows_in, @rows_loaded, @status, @message, @started_at);
END;
GO

GO

/* ######## sql/01_bronze_ddl.sql ######## */
/* =====================================================================
   01_bronze_ddl.sql
   Bronze = raw copy of the 19 source CSV files.

   Rules
   - One table per file, same columns in the same order as the file.
   - Every column is text (NVARCHAR) so a bad value never stops a load.
     Types are applied in silver, where bad values are counted and handled.
   - Table name = file name in lower case (CUSTOMERS.csv -> bronze.customers).
   ===================================================================== */

USE RetailDWH;
GO

DROP TABLE IF EXISTS
    bronze.brands, bronze.customers, bronze.deliveries, bronze.delivery_providers,
    bronze.departments, bronze.employees, bronze.inventory, bronze.online_orders,
    bronze.online_order_items, bronze.payments, bronze.pos_transactions,
    bronze.products, bronze.product_suppliers, bronze.promotions, bronze.registers,
    bronze.stores, bronze.suppliers, bronze.transaction_items, bronze.warehouses;
GO

CREATE TABLE bronze.brands (
    Brand_ID           NVARCHAR(50),
    Brand_Name         NVARCHAR(255)
);

CREATE TABLE bronze.customers (
    Customer_ID        NVARCHAR(50),
    First_Name         NVARCHAR(100),
    Last_Name          NVARCHAR(100),
    Gender             NVARCHAR(50),
    City               NVARCHAR(100),
    Loyalty_Level      NVARCHAR(50),
    Email              NVARCHAR(255)
);

CREATE TABLE bronze.deliveries (
    Delivery_ID        NVARCHAR(50),
    Order_ID           NVARCHAR(50),
    Provider_ID        NVARCHAR(50),
    Ship_Date          NVARCHAR(50),
    Delivery_Date      NVARCHAR(50),
    Delivery_Status    NVARCHAR(50)
);

CREATE TABLE bronze.delivery_providers (
    Provider_ID        NVARCHAR(50),
    Provider_Name      NVARCHAR(255),
    Phone              NVARCHAR(50)
);

CREATE TABLE bronze.departments (
    Department_ID      NVARCHAR(50),
    Department_Name    NVARCHAR(255)
);

CREATE TABLE bronze.employees (
    Employee_ID        NVARCHAR(50),
    Name               NVARCHAR(255),
    Gender             NVARCHAR(50),
    Position           NVARCHAR(100),
    Store_ID           NVARCHAR(50),
    Hire_Date          NVARCHAR(50)
);

CREATE TABLE bronze.inventory (
    Inventory_ID       NVARCHAR(50),
    Store_ID           NVARCHAR(50),
    Product_ID         NVARCHAR(50),
    Stock_Level        NVARCHAR(50),
    Last_Updated       NVARCHAR(50)
);

CREATE TABLE bronze.online_orders (
    Order_ID           NVARCHAR(50),
    Customer_ID        NVARCHAR(50),
    Warehouse_ID       NVARCHAR(50),
    Order_Time         NVARCHAR(50),
    Order_Status       NVARCHAR(50),
    Order_Total        NVARCHAR(50)
);

CREATE TABLE bronze.online_order_items (
    Order_Item_ID      NVARCHAR(50),
    Order_ID           NVARCHAR(50),
    Product_ID         NVARCHAR(50),
    Promotion_ID       NVARCHAR(50),
    Quantity           NVARCHAR(50),
    Unit_Price         NVARCHAR(50)
);

CREATE TABLE bronze.payments (
    Payment_ID         NVARCHAR(50),
    Order_ID           NVARCHAR(50),
    Payment_Method     NVARCHAR(100),
    Payment_Amount     NVARCHAR(50),
    Payment_Time       NVARCHAR(50)
);

CREATE TABLE bronze.pos_transactions (
    Transaction_ID     NVARCHAR(50),
    Store_ID           NVARCHAR(50),
    Register_ID        NVARCHAR(50),
    Employee_ID        NVARCHAR(50),
    Customer_ID        NVARCHAR(50),
    Transaction_Time   NVARCHAR(50)
);

CREATE TABLE bronze.products (
    Product_ID         NVARCHAR(50),
    SKU                NVARCHAR(100),
    Product_Name       NVARCHAR(255),
    Brand_ID           NVARCHAR(50),
    Department_ID      NVARCHAR(50),
    Package_Size       NVARCHAR(100)
);

CREATE TABLE bronze.product_suppliers (
    Product_ID         NVARCHAR(50),
    Supplier_ID        NVARCHAR(50),
    Supply_Price       NVARCHAR(50)
);

CREATE TABLE bronze.promotions (
    Promotion_ID       NVARCHAR(50),
    Promo_Type         NVARCHAR(100),
    Discount_Percent   NVARCHAR(50),
    Start_Date         NVARCHAR(50),
    End_Date           NVARCHAR(50)
);

CREATE TABLE bronze.registers (
    Register_ID        NVARCHAR(50),
    Store_ID           NVARCHAR(50),
    Register_Number    NVARCHAR(50)
);

CREATE TABLE bronze.stores (
    Store_ID           NVARCHAR(50),
    Store_Name         NVARCHAR(255),
    City               NVARCHAR(100),
    State              NVARCHAR(50),
    Region             NVARCHAR(50),
    Opening_Date       NVARCHAR(50)
);

CREATE TABLE bronze.suppliers (
    Supplier_ID        NVARCHAR(50),
    Supplier_Name      NVARCHAR(255),
    Country            NVARCHAR(100),
    Phone              NVARCHAR(50)
);

CREATE TABLE bronze.transaction_items (
    Line_ID            NVARCHAR(50),
    Transaction_ID     NVARCHAR(50),
    Product_ID         NVARCHAR(50),
    Promotion_ID       NVARCHAR(50),
    Quantity           NVARCHAR(50),
    Unit_Price         NVARCHAR(50)
);

CREATE TABLE bronze.warehouses (
    Warehouse_ID       NVARCHAR(50),
    Warehouse_Name     NVARCHAR(255),
    City               NVARCHAR(100),
    State              NVARCHAR(50)
);
GO

GO

/* ######## sql/02_bronze_load.sql ######## */
/* =====================================================================
   02_bronze_load.sql
   bronze.load_bronze: truncates and reloads all 19 bronze tables from
   the CSV folder you pass in.

   Usage
     EXEC bronze.load_bronze @source_path = N'D:\Projects\RetailDWH\datasets\';

   Notes
   - The path is read by the SQL Server service, so it must exist on the
     machine where SQL Server runs and the service account needs read access.
   - Files are UTF-8 with Windows line endings: CODEPAGE 65001, and '\n',
     which BULK INSERT reads as CR+LF.
   - One file failing does not stop the others. Every table is logged in
     etl.load_log, and the procedure raises an error at the end if any
     file failed, so the pipeline stops before silver.
   ===================================================================== */

USE RetailDWH;
GO

CREATE OR ALTER PROCEDURE bronze.load_bronze
    @source_path NVARCHAR(400),
    @run_id      UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @run_id IS NULL SET @run_id = NEWID();
    IF RIGHT(@source_path, 1) <> N'\' SET @source_path = @source_path + N'\';

    DECLARE @tables TABLE (table_name SYSNAME PRIMARY KEY);
    INSERT INTO @tables (table_name) VALUES
        ('brands'), ('customers'), ('deliveries'), ('delivery_providers'),
        ('departments'), ('employees'), ('inventory'), ('online_orders'),
        ('online_order_items'), ('payments'), ('pos_transactions'),
        ('products'), ('product_suppliers'), ('promotions'), ('registers'),
        ('stores'), ('suppliers'), ('transaction_items'), ('warehouses');

    DECLARE @table   SYSNAME,
            @file    NVARCHAR(600),
            @sql     NVARCHAR(MAX),
            @rows    INT,
            @started DATETIME2(0),
            @failed  INT = 0;

    DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT table_name FROM @tables ORDER BY table_name;

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @table;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @started = SYSDATETIME();
        SET @file = @source_path + UPPER(@table) + N'.csv';

        SET @sql = N'
            TRUNCATE TABLE bronze.' + QUOTENAME(@table) + N';
            BULK INSERT bronze.' + QUOTENAME(@table) + N'
            FROM ''' + REPLACE(@file, N'''', N'''''') + N'''
            WITH (
                FIRSTROW        = 2,
                FIELDTERMINATOR = '','',
                ROWTERMINATOR   = ''\n'',
                CODEPAGE        = ''65001'',
                TABLOCK
            );
            SELECT @rows = COUNT(*) FROM bronze.' + QUOTENAME(@table) + N';';

        BEGIN TRY
            EXEC sp_executesql @sql, N'@rows INT OUTPUT', @rows = @rows OUTPUT;
            EXEC etl.log_step @run_id, 'bronze', @table, NULL, @rows,
                 'Success', @started, @file;
        END TRY
        BEGIN CATCH
            SET @failed += 1;
            DECLARE @err NVARCHAR(2000) = LEFT(@file + N' | ' + ERROR_MESSAGE(), 2000);
            EXEC etl.log_step @run_id, 'bronze', @table, NULL, 0,
                 'Failed', @started, @err;
        END CATCH;

        FETCH NEXT FROM table_cursor INTO @table;
    END;

    CLOSE table_cursor;
    DEALLOCATE table_cursor;

    IF @failed > 0
    BEGIN
        DECLARE @msg NVARCHAR(400) =
            CONCAT(N'Bronze load: ', @failed, N' file(s) failed. See etl.load_log for run ', @run_id, N'.');
        THROW 50001, @msg, 1;
    END;
END;
GO

GO

/* ######## sql/03_silver_ddl.sql ######## */
/* =====================================================================
   03_silver_ddl.sql
   Silver = cleaned, typed, one row per business key.

   Rules
   - Proper data types and a primary key on every table.
   - snake_case column names.
   - Fix-up columns show HOW a value was obtained (e.g. price_source),
     so nothing is changed silently.
   - dwh_load_date records when each row was loaded.
   ===================================================================== */

USE RetailDWH;
GO

DROP TABLE IF EXISTS
    silver.brands, silver.customers, silver.deliveries, silver.delivery_providers,
    silver.departments, silver.employees, silver.inventory, silver.online_orders,
    silver.online_order_items, silver.payments, silver.pos_transactions,
    silver.pos_transaction_items, silver.products, silver.product_suppliers,
    silver.promotions, silver.registers, silver.stores, silver.suppliers,
    silver.warehouses;
GO

/* ---------------- Reference tables ---------------- */

CREATE TABLE silver.brands (
    brand_id         INT           NOT NULL PRIMARY KEY,
    brand_name       NVARCHAR(100) NOT NULL,
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.departments (
    department_id    INT           NOT NULL PRIMARY KEY,
    department_name  NVARCHAR(100) NOT NULL,
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.products (
    product_id       INT           NOT NULL PRIMARY KEY,
    sku              NVARCHAR(50)  NOT NULL,
    product_name     NVARCHAR(150) NOT NULL,
    brand_id         INT           NULL,
    department_id    INT           NULL,
    package_size     NVARCHAR(50)  NOT NULL,
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.suppliers (
    supplier_id      INT           NOT NULL PRIMARY KEY,
    supplier_name    NVARCHAR(150) NOT NULL,
    country          NVARCHAR(100) NOT NULL,
    phone            NVARCHAR(50)  NOT NULL,
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.product_suppliers (
    product_id       INT           NOT NULL,
    supplier_id      INT           NOT NULL,
    supply_price     DECIMAL(10,2) NULL,          -- 20 blanks in source, kept as NULL
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_product_suppliers PRIMARY KEY (product_id, supplier_id)
);

CREATE TABLE silver.customers (
    customer_id        INT           NOT NULL PRIMARY KEY,
    first_name         NVARCHAR(100) NOT NULL,
    last_name          NVARCHAR(100) NOT NULL,
    full_name          NVARCHAR(201) NOT NULL,
    gender             NVARCHAR(20)  NOT NULL,   -- Male / Female / Unknown
    city               NVARCHAR(100) NOT NULL,
    loyalty_level      NVARCHAR(20)  NOT NULL,   -- Bronze / Silver / Gold / Platinum / Unknown
    email              NVARCHAR(255) NULL,
    is_email_shared    BIT           NOT NULL,   -- 1 = another customer has the same email
    dwh_load_date      DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.stores (
    store_id         INT           NOT NULL PRIMARY KEY,
    store_name       NVARCHAR(150) NOT NULL,
    city             NVARCHAR(100) NOT NULL,
    state            NVARCHAR(10)  NOT NULL,
    region           NVARCHAR(50)  NOT NULL,
    opening_date     DATE          NULL,
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.registers (
    register_id      INT           NOT NULL PRIMARY KEY,
    store_id         INT           NOT NULL,
    register_number  INT           NOT NULL,
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.employees (
    employee_id      INT           NOT NULL PRIMARY KEY,
    full_name        NVARCHAR(201) NOT NULL,
    gender           NVARCHAR(20)  NOT NULL,
    position         NVARCHAR(100) NOT NULL,
    store_id         INT           NULL,
    hire_date        DATE          NULL,
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.warehouses (
    warehouse_id     INT           NOT NULL PRIMARY KEY,
    warehouse_name   NVARCHAR(150) NOT NULL,
    city             NVARCHAR(100) NOT NULL,
    state            NVARCHAR(10)  NOT NULL,
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.delivery_providers (
    provider_id      INT           NOT NULL PRIMARY KEY,
    provider_name    NVARCHAR(150) NOT NULL,
    phone            NVARCHAR(50)  NOT NULL,
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.promotions (
    promotion_id        INT           NOT NULL PRIMARY KEY,
    promo_type          NVARCHAR(50)  NOT NULL,
    discount_percent    DECIMAL(5,2)  NOT NULL,  -- blank in source -> 0
    start_date          DATE          NULL,
    end_date            DATE          NULL,
    is_discount_missing BIT           NOT NULL,  -- 1 = source had no discount value
    is_dates_swapped    BIT           NOT NULL,  -- 1 = source end date was before start date
    dwh_load_date       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.inventory (
    inventory_id     INT           NOT NULL PRIMARY KEY,
    store_id         INT           NOT NULL,
    product_id       INT           NOT NULL,
    stock_level      INT           NULL,         -- 180 blanks in source, kept as NULL
    last_updated     DATETIME2(0)  NULL,
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

/* ---------------- Online channel ---------------- */

CREATE TABLE silver.online_orders (
    order_id         INT           NOT NULL PRIMARY KEY,
    customer_id      INT           NULL,
    warehouse_id     INT           NULL,
    order_datetime   DATETIME2(0)  NOT NULL,
    order_status     NVARCHAR(30)  NOT NULL,
    order_total      DECIMAL(12,2) NULL,         -- = SUM(quantity x unit_price) of the order's items
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.online_order_items (
    order_item_id    INT           NOT NULL PRIMARY KEY,
    order_id         INT           NOT NULL,
    product_id       INT           NOT NULL,
    promotion_id     INT           NULL,         -- NULL = no promotion
    quantity         INT           NULL,
    unit_price       DECIMAL(10,2) NULL,
    quantity_source  VARCHAR(20)   NOT NULL,     -- source / order_total / default_1
    price_source     VARCHAR(20)   NOT NULL,     -- source / order_total / product_median
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.payments (
    payment_id       INT           NOT NULL PRIMARY KEY,
    order_id         INT           NOT NULL,
    payment_method   NVARCHAR(50)  NOT NULL,
    payment_amount   DECIMAL(12,2) NULL,         -- 206 blanks in source, kept as NULL
    payment_datetime DATETIME2(0)  NULL,
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.deliveries (
    delivery_id              INT          NOT NULL PRIMARY KEY,
    order_id                 INT          NOT NULL,
    provider_id              INT          NULL,
    ship_datetime            DATETIME2(0) NULL,
    delivery_datetime        DATETIME2(0) NULL,
    delivery_status          NVARCHAR(30) NOT NULL,
    is_delivery_before_ship  BIT          NOT NULL, -- 1 = delivery date earlier than ship date (bad data)
    dwh_load_date            DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);

/* ---------------- Store (POS) channel ---------------- */

CREATE TABLE silver.pos_transactions (
    transaction_id       VARCHAR(30)  NOT NULL PRIMARY KEY,   -- e.g. TXN-20250406-000001
    store_id             INT          NULL,
    register_id          INT          NULL,
    employee_id          INT          NULL,
    customer_id          INT          NULL,
    transaction_datetime DATETIME2(0) NOT NULL,
    dwh_load_date        DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE silver.pos_transaction_items (
    line_id          INT           NOT NULL PRIMARY KEY,
    transaction_id   VARCHAR(30)   NOT NULL,
    product_id       INT           NOT NULL,
    promotion_id     INT           NULL,
    quantity         INT           NULL,
    unit_price       DECIMAL(10,2) NULL,
    quantity_source  VARCHAR(20)   NOT NULL,     -- source / default_1
    price_source     VARCHAR(20)   NOT NULL,     -- source / product_median
    dwh_load_date    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO

GO

/* ######## sql/04_silver_load.sql ######## */
/* =====================================================================
   04_silver_load.sql
   silver.load_silver: bronze -> silver for all 19 tables.

   Cleaning rules applied to every table
   - TRIM text; blank strings become NULL (NULLIF(TRIM(x), '')).
   - Types with explicit styles: dates 'yyyy-mm-dd' (style 23),
     date-times 'yyyy-mm-dd hh:mi:ss' (style 120).
   - One row per business key: ROW_NUMBER() keeps one row per ID.
   - Rows without a valid key (or a required date) are dropped and
     counted: etl.load_log.rows_rejected = rows_in - rows_loaded.

   Business rules (see README "Data decisions")
   - Gender     -> Male / Female / Unknown.
   - Loyalty    -> Bronze / Silver / Gold / Platinum / Unknown.
   - Promotions -> blank discount = 0 (flagged); start/end swapped when
                   end < start (flagged).
   - Missing online quantity or price on ONE line of an order is
     recovered exactly from Order_Total (Order_Total = SUM(qty x price)).
     Anything still missing: price = product median price in the same
     channel, quantity = 1. Every filled value is labelled in
     quantity_source / price_source.
   - Deliveries where the delivery date is before the ship date are
     flagged; gold leaves their delivery_days empty.

   The whole load runs in one transaction: if any step fails, silver is
   rolled back to its previous state and the error is logged.
   ===================================================================== */

USE RetailDWH;
GO

CREATE OR ALTER PROCEDURE silver.load_silver
    @run_id UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @run_id IS NULL SET @run_id = NEWID();

    DECLARE @step    VARCHAR(100),
            @started DATETIME2(0),
            @in      INT,
            @out     INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* =========================== brands =========================== */
        SELECT @step = 'brands', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.brands;
        TRUNCATE TABLE silver.brands;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Brand_ID) AS INT)     AS brand_id,
                   NULLIF(TRIM(Brand_Name), '')        AS brand_name
            FROM bronze.brands
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY brand_id ORDER BY brand_name) AS rn
            FROM src WHERE brand_id IS NOT NULL
        )
        INSERT INTO silver.brands (brand_id, brand_name)
        SELECT brand_id, ISNULL(brand_name, 'Unknown')
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* ========================= departments ======================== */
        SELECT @step = 'departments', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.departments;
        TRUNCATE TABLE silver.departments;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Department_ID) AS INT) AS department_id,
                   NULLIF(TRIM(Department_Name), '')    AS department_name
            FROM bronze.departments
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY department_id ORDER BY department_name) AS rn
            FROM src WHERE department_id IS NOT NULL
        )
        INSERT INTO silver.departments (department_id, department_name)
        SELECT department_id, ISNULL(department_name, 'Unknown')
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* =========================== products ========================= */
        SELECT @step = 'products', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.products;
        TRUNCATE TABLE silver.products;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Product_ID) AS INT)    AS product_id,
                   NULLIF(TRIM(SKU), '')                AS sku,
                   NULLIF(TRIM(Product_Name), '')       AS product_name,
                   TRY_CAST(TRIM(Brand_ID) AS INT)      AS brand_id,
                   TRY_CAST(TRIM(Department_ID) AS INT) AS department_id,
                   NULLIF(TRIM(Package_Size), '')       AS package_size
            FROM bronze.products
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY sku) AS rn
            FROM src WHERE product_id IS NOT NULL
        )
        INSERT INTO silver.products (product_id, sku, product_name, brand_id, department_id, package_size)
        SELECT product_id, ISNULL(sku, 'N/A'), ISNULL(product_name, 'Unknown'),
               brand_id, department_id, ISNULL(package_size, 'N/A')
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* =========================== suppliers ======================== */
        SELECT @step = 'suppliers', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.suppliers;
        TRUNCATE TABLE silver.suppliers;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Supplier_ID) AS INT) AS supplier_id,
                   NULLIF(TRIM(Supplier_Name), '')    AS supplier_name,
                   NULLIF(TRIM(Country), '')          AS country,
                   NULLIF(TRIM(Phone), '')            AS phone
            FROM bronze.suppliers
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY supplier_id ORDER BY supplier_name) AS rn
            FROM src WHERE supplier_id IS NOT NULL
        )
        INSERT INTO silver.suppliers (supplier_id, supplier_name, country, phone)
        SELECT supplier_id, ISNULL(supplier_name, 'Unknown'), ISNULL(country, 'Unknown'), ISNULL(phone, 'N/A')
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* ======================= product_suppliers ==================== */
        SELECT @step = 'product_suppliers', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.product_suppliers;
        TRUNCATE TABLE silver.product_suppliers;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Product_ID) AS INT)            AS product_id,
                   TRY_CAST(TRIM(Supplier_ID) AS INT)           AS supplier_id,
                   TRY_CAST(NULLIF(TRIM(Supply_Price), '') AS DECIMAL(10,2)) AS supply_price
            FROM bronze.product_suppliers
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY product_id, supplier_id
                                         ORDER BY CASE WHEN supply_price IS NULL THEN 1 ELSE 0 END) AS rn
            FROM src WHERE product_id IS NOT NULL AND supplier_id IS NOT NULL
        )
        INSERT INTO silver.product_suppliers (product_id, supplier_id, supply_price)
        SELECT product_id, supplier_id, supply_price
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* =========================== customers ======================== */
        SELECT @step = 'customers', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.customers;
        TRUNCATE TABLE silver.customers;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Customer_ID) AS INT)  AS customer_id,
                   NULLIF(TRIM(First_Name), '')        AS first_name,
                   NULLIF(TRIM(Last_Name), '')         AS last_name,
                   UPPER(NULLIF(TRIM(Gender), ''))     AS gender_raw,
                   NULLIF(TRIM(City), '')              AS city,
                   NULLIF(TRIM(Loyalty_Level), '')     AS loyalty_raw,
                   LOWER(NULLIF(TRIM(Email), ''))      AS email
            FROM bronze.customers
        ), ranked AS (
            SELECT *,
                   ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY email) AS rn
            FROM src WHERE customer_id IS NOT NULL
        ), deduped AS (
            SELECT *,
                   CASE WHEN email IS NOT NULL
                         AND COUNT(*) OVER (PARTITION BY email) > 1 THEN 1 ELSE 0 END AS is_email_shared
            FROM ranked WHERE rn = 1
        )
        INSERT INTO silver.customers
            (customer_id, first_name, last_name, full_name, gender, city, loyalty_level, email, is_email_shared)
        SELECT customer_id,
               ISNULL(first_name, 'Unknown'),
               ISNULL(last_name, 'Unknown'),
               CONCAT_WS(' ', first_name, last_name),
               CASE WHEN gender_raw IN ('M', 'MALE')   THEN 'Male'
                    WHEN gender_raw IN ('F', 'FEMALE') THEN 'Female'
                    ELSE 'Unknown' END,
               ISNULL(city, 'Unknown'),
               CASE WHEN loyalty_raw IN ('Bronze', 'Silver', 'Gold', 'Platinum') THEN loyalty_raw
                    ELSE 'Unknown' END,
               email,
               is_email_shared
        FROM deduped;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* ============================ stores ========================== */
        SELECT @step = 'stores', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.stores;
        TRUNCATE TABLE silver.stores;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Store_ID) AS INT)                  AS store_id,
                   NULLIF(TRIM(Store_Name), '')                     AS store_name,
                   NULLIF(TRIM(City), '')                           AS city,
                   NULLIF(TRIM(State), '')                          AS state,
                   NULLIF(TRIM(Region), '')                         AS region,
                   TRY_CONVERT(DATE, NULLIF(TRIM(Opening_Date), ''), 23) AS opening_date
            FROM bronze.stores
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY store_id ORDER BY store_name) AS rn
            FROM src WHERE store_id IS NOT NULL
        )
        INSERT INTO silver.stores (store_id, store_name, city, state, region, opening_date)
        SELECT store_id, ISNULL(store_name, 'Unknown'), ISNULL(city, 'Unknown'),
               ISNULL(state, 'N/A'), ISNULL(region, 'Unknown'), opening_date
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* =========================== registers ======================== */
        SELECT @step = 'registers', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.registers;
        TRUNCATE TABLE silver.registers;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Register_ID) AS INT)     AS register_id,
                   TRY_CAST(TRIM(Store_ID) AS INT)        AS store_id,
                   TRY_CAST(TRIM(Register_Number) AS INT) AS register_number
            FROM bronze.registers
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY register_id ORDER BY store_id) AS rn
            FROM src WHERE register_id IS NOT NULL AND store_id IS NOT NULL AND register_number IS NOT NULL
        )
        INSERT INTO silver.registers (register_id, store_id, register_number)
        SELECT register_id, store_id, register_number
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* =========================== employees ======================== */
        SELECT @step = 'employees', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.employees;
        TRUNCATE TABLE silver.employees;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Employee_ID) AS INT)               AS employee_id,
                   NULLIF(TRIM(Name), '')                           AS full_name,
                   UPPER(NULLIF(TRIM(Gender), ''))                  AS gender_raw,
                   NULLIF(TRIM(Position), '')                       AS position,
                   TRY_CAST(TRIM(Store_ID) AS INT)                  AS store_id,
                   TRY_CONVERT(DATE, NULLIF(TRIM(Hire_Date), ''), 23) AS hire_date
            FROM bronze.employees
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY employee_id ORDER BY hire_date DESC) AS rn
            FROM src WHERE employee_id IS NOT NULL
        )
        INSERT INTO silver.employees (employee_id, full_name, gender, position, store_id, hire_date)
        SELECT employee_id,
               ISNULL(full_name, 'Unknown'),
               CASE WHEN gender_raw IN ('M', 'MALE')   THEN 'Male'
                    WHEN gender_raw IN ('F', 'FEMALE') THEN 'Female'
                    ELSE 'Unknown' END,
               ISNULL(position, 'Unknown'),
               store_id,
               hire_date
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* =========================== warehouses ======================= */
        SELECT @step = 'warehouses', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.warehouses;
        TRUNCATE TABLE silver.warehouses;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Warehouse_ID) AS INT) AS warehouse_id,
                   NULLIF(TRIM(Warehouse_Name), '')    AS warehouse_name,
                   NULLIF(TRIM(City), '')              AS city,
                   NULLIF(TRIM(State), '')             AS state
            FROM bronze.warehouses
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY warehouse_id ORDER BY warehouse_name) AS rn
            FROM src WHERE warehouse_id IS NOT NULL
        )
        INSERT INTO silver.warehouses (warehouse_id, warehouse_name, city, state)
        SELECT warehouse_id, ISNULL(warehouse_name, 'Unknown'), ISNULL(city, 'Unknown'), ISNULL(state, 'N/A')
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* ======================= delivery_providers =================== */
        SELECT @step = 'delivery_providers', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.delivery_providers;
        TRUNCATE TABLE silver.delivery_providers;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Provider_ID) AS INT) AS provider_id,
                   NULLIF(TRIM(Provider_Name), '')    AS provider_name,
                   NULLIF(TRIM(Phone), '')            AS phone
            FROM bronze.delivery_providers
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY provider_id ORDER BY provider_name) AS rn
            FROM src WHERE provider_id IS NOT NULL
        )
        INSERT INTO silver.delivery_providers (provider_id, provider_name, phone)
        SELECT provider_id, ISNULL(provider_name, 'Unknown'), ISNULL(phone, 'N/A')
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* =========================== promotions ======================= */
        SELECT @step = 'promotions', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.promotions;
        TRUNCATE TABLE silver.promotions;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Promotion_ID) AS INT)                            AS promotion_id,
                   NULLIF(TRIM(Promo_Type), '')                                   AS promo_type,
                   TRY_CAST(NULLIF(TRIM(Discount_Percent), '') AS DECIMAL(5,2))   AS discount_percent,
                   TRY_CONVERT(DATE, NULLIF(TRIM(Start_Date), ''), 23)            AS start_raw,
                   TRY_CONVERT(DATE, NULLIF(TRIM(End_Date), ''), 23)              AS end_raw
            FROM bronze.promotions
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY promotion_id ORDER BY start_raw) AS rn
            FROM src WHERE promotion_id IS NOT NULL
        )
        INSERT INTO silver.promotions
            (promotion_id, promo_type, discount_percent, start_date, end_date,
             is_discount_missing, is_dates_swapped)
        SELECT promotion_id,
               ISNULL(promo_type, 'Unknown'),
               CASE WHEN discount_percent BETWEEN 0 AND 100 THEN discount_percent ELSE 0 END,
               CASE WHEN end_raw < start_raw THEN end_raw   ELSE start_raw END,
               CASE WHEN end_raw < start_raw THEN start_raw ELSE end_raw   END,
               CASE WHEN discount_percent BETWEEN 0 AND 100 THEN 0 ELSE 1 END,
               CASE WHEN end_raw < start_raw THEN 1 ELSE 0 END
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* =========================== inventory ======================== */
        SELECT @step = 'inventory', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.inventory;
        TRUNCATE TABLE silver.inventory;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Inventory_ID) AS INT)                          AS inventory_id,
                   TRY_CAST(TRIM(Store_ID) AS INT)                              AS store_id,
                   TRY_CAST(TRIM(Product_ID) AS INT)                            AS product_id,
                   TRY_CAST(NULLIF(TRIM(Stock_Level), '') AS INT)               AS stock_level,
                   TRY_CONVERT(DATETIME2(0), NULLIF(TRIM(Last_Updated), ''), 120) AS last_updated
            FROM bronze.inventory
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY inventory_id ORDER BY last_updated DESC) AS rn
            FROM src WHERE inventory_id IS NOT NULL AND store_id IS NOT NULL AND product_id IS NOT NULL
        )
        INSERT INTO silver.inventory (inventory_id, store_id, product_id, stock_level, last_updated)
        SELECT inventory_id, store_id, product_id,
               CASE WHEN stock_level >= 0 THEN stock_level END,
               last_updated
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* ========================= online_orders ====================== */
        SELECT @step = 'online_orders', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.online_orders;
        TRUNCATE TABLE silver.online_orders;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Order_ID) AS INT)                              AS order_id,
                   TRY_CAST(TRIM(Customer_ID) AS INT)                           AS customer_id,
                   TRY_CAST(TRIM(Warehouse_ID) AS INT)                          AS warehouse_id,
                   TRY_CONVERT(DATETIME2(0), NULLIF(TRIM(Order_Time), ''), 120) AS order_datetime,
                   NULLIF(TRIM(Order_Status), '')                               AS order_status,
                   TRY_CAST(NULLIF(TRIM(Order_Total), '') AS DECIMAL(12,2))     AS order_total
            FROM bronze.online_orders
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY order_datetime DESC) AS rn
            FROM src WHERE order_id IS NOT NULL AND order_datetime IS NOT NULL
        )
        INSERT INTO silver.online_orders
            (order_id, customer_id, warehouse_id, order_datetime, order_status, order_total)
        SELECT order_id, customer_id, warehouse_id, order_datetime,
               ISNULL(order_status, 'Unknown'), order_total
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* ======================= online_order_items =================== */
        SELECT @step = 'online_order_items', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.online_order_items;
        TRUNCATE TABLE silver.online_order_items;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Order_Item_ID) AS INT)                       AS order_item_id,
                   TRY_CAST(TRIM(Order_ID) AS INT)                            AS order_id,
                   TRY_CAST(TRIM(Product_ID) AS INT)                          AS product_id,
                   TRY_CAST(NULLIF(TRIM(Promotion_ID), '') AS INT)            AS promotion_id,
                   TRY_CAST(NULLIF(TRIM(Quantity), '') AS INT)                AS quantity,
                   TRY_CAST(NULLIF(TRIM(Unit_Price), '') AS DECIMAL(10,2))    AS unit_price
            FROM bronze.online_order_items
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY order_item_id ORDER BY order_id) AS rn
            FROM src
            WHERE order_item_id IS NOT NULL AND order_id IS NOT NULL AND product_id IS NOT NULL
        )
        INSERT INTO silver.online_order_items
            (order_item_id, order_id, product_id, promotion_id, quantity, unit_price,
             quantity_source, price_source)
        SELECT order_item_id, order_id, product_id, promotion_id,
               CASE WHEN quantity > 0 THEN quantity END,
               CASE WHEN unit_price > 0 THEN unit_price END,
               CASE WHEN quantity > 0 THEN 'source' ELSE 'missing' END,
               CASE WHEN unit_price > 0 THEN 'source' ELSE 'missing' END
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;

        /* Fill 1: recover the single missing value of an order from Order_Total.
           Order_Total = SUM(quantity x unit_price), so
           missing line gross = Order_Total - SUM(gross of the complete lines). */
        DROP TABLE IF EXISTS #online_fix;
        SELECT i.order_item_id,
               i.quantity,
               i.unit_price,
               o.order_total - x.known_gross AS missing_gross
        INTO #online_fix
        FROM silver.online_order_items AS i
        JOIN silver.online_orders      AS o ON o.order_id = i.order_id
        JOIN (
            SELECT order_id,
                   SUM(CASE WHEN quantity IS NULL OR unit_price IS NULL THEN 1 ELSE 0 END) AS incomplete_lines,
                   SUM(ISNULL(quantity * unit_price, 0))                                    AS known_gross
            FROM silver.online_order_items
            GROUP BY order_id
        ) AS x ON x.order_id = i.order_id
        WHERE x.incomplete_lines = 1
          AND o.order_total IS NOT NULL
          AND (i.quantity IS NULL OR i.unit_price IS NULL)
          AND NOT (i.quantity IS NULL AND i.unit_price IS NULL);

        UPDATE i
        SET    i.unit_price   = ROUND(f.missing_gross / f.quantity, 2),
               i.price_source = 'order_total'
        FROM   silver.online_order_items AS i
        JOIN   #online_fix AS f ON f.order_item_id = i.order_item_id
        WHERE  f.unit_price IS NULL
          AND  f.missing_gross > 0;

        UPDATE i
        SET    i.quantity        = CAST(ROUND(f.missing_gross / f.unit_price, 0) AS INT),
               i.quantity_source = 'order_total'
        FROM   silver.online_order_items AS i
        JOIN   #online_fix AS f ON f.order_item_id = i.order_item_id
        WHERE  f.quantity IS NULL
          AND  f.missing_gross >= f.unit_price
          AND  ABS(f.missing_gross / f.unit_price - ROUND(f.missing_gross / f.unit_price, 0)) < 0.01;

        /* Fill 2: still-missing price -> median source price of the product (online). */
        DROP TABLE IF EXISTS #online_median;
        SELECT DISTINCT product_id,
               PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY unit_price)
                   OVER (PARTITION BY product_id) AS median_price
        INTO #online_median
        FROM silver.online_order_items
        WHERE price_source = 'source';

        UPDATE i
        SET    i.unit_price   = ROUND(m.median_price, 2),
               i.price_source = 'product_median'
        FROM   silver.online_order_items AS i
        JOIN   #online_median AS m ON m.product_id = i.product_id
        WHERE  i.unit_price IS NULL;

        /* Fill 3: still-missing quantity -> 1. */
        UPDATE silver.online_order_items
        SET    quantity = 1, quantity_source = 'default_1'
        WHERE  quantity IS NULL;

        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* ============================ payments ======================== */
        SELECT @step = 'payments', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.payments;
        TRUNCATE TABLE silver.payments;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Payment_ID) AS INT)                              AS payment_id,
                   TRY_CAST(TRIM(Order_ID) AS INT)                                AS order_id,
                   NULLIF(TRIM(Payment_Method), '')                               AS payment_method,
                   TRY_CAST(NULLIF(TRIM(Payment_Amount), '') AS DECIMAL(12,2))    AS payment_amount,
                   TRY_CONVERT(DATETIME2(0), NULLIF(TRIM(Payment_Time), ''), 120) AS payment_datetime
            FROM bronze.payments
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY payment_id ORDER BY payment_datetime DESC) AS rn
            FROM src WHERE payment_id IS NOT NULL AND order_id IS NOT NULL
        )
        INSERT INTO silver.payments (payment_id, order_id, payment_method, payment_amount, payment_datetime)
        SELECT payment_id, order_id, ISNULL(payment_method, 'Unknown'), payment_amount, payment_datetime
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* =========================== deliveries ======================= */
        SELECT @step = 'deliveries', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.deliveries;
        TRUNCATE TABLE silver.deliveries;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Delivery_ID) AS INT)                              AS delivery_id,
                   TRY_CAST(TRIM(Order_ID) AS INT)                                 AS order_id,
                   TRY_CAST(TRIM(Provider_ID) AS INT)                              AS provider_id,
                   TRY_CONVERT(DATETIME2(0), NULLIF(TRIM(Ship_Date), ''), 120)     AS ship_datetime,
                   TRY_CONVERT(DATETIME2(0), NULLIF(TRIM(Delivery_Date), ''), 120) AS delivery_datetime,
                   NULLIF(TRIM(Delivery_Status), '')                               AS delivery_status
            FROM bronze.deliveries
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY delivery_id ORDER BY ship_datetime DESC) AS rn
            FROM src WHERE delivery_id IS NOT NULL AND order_id IS NOT NULL
        )
        INSERT INTO silver.deliveries
            (delivery_id, order_id, provider_id, ship_datetime, delivery_datetime,
             delivery_status, is_delivery_before_ship)
        SELECT delivery_id, order_id, provider_id, ship_datetime, delivery_datetime,
               ISNULL(delivery_status, 'Unknown'),
               CASE WHEN delivery_datetime < ship_datetime THEN 1 ELSE 0 END
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* ======================== pos_transactions ==================== */
        SELECT @step = 'pos_transactions', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.pos_transactions;
        TRUNCATE TABLE silver.pos_transactions;
        WITH src AS (
            SELECT NULLIF(TRIM(Transaction_ID), '')                                    AS transaction_id,
                   TRY_CAST(TRIM(Store_ID) AS INT)                                     AS store_id,
                   TRY_CAST(TRIM(Register_ID) AS INT)                                  AS register_id,
                   TRY_CAST(TRIM(Employee_ID) AS INT)                                  AS employee_id,
                   TRY_CAST(TRIM(Customer_ID) AS INT)                                  AS customer_id,
                   TRY_CONVERT(DATETIME2(0), NULLIF(TRIM(Transaction_Time), ''), 120)  AS transaction_datetime
            FROM bronze.pos_transactions
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY transaction_datetime DESC) AS rn
            FROM src WHERE transaction_id IS NOT NULL AND transaction_datetime IS NOT NULL
        )
        INSERT INTO silver.pos_transactions
            (transaction_id, store_id, register_id, employee_id, customer_id, transaction_datetime)
        SELECT transaction_id, store_id, register_id, employee_id, customer_id, transaction_datetime
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;
        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        /* ===================== pos_transaction_items ================== */
        SELECT @step = 'pos_transaction_items', @started = SYSDATETIME(), @in = COUNT(*) FROM bronze.transaction_items;
        TRUNCATE TABLE silver.pos_transaction_items;
        WITH src AS (
            SELECT TRY_CAST(TRIM(Line_ID) AS INT)                          AS line_id,
                   NULLIF(TRIM(Transaction_ID), '')                        AS transaction_id,
                   TRY_CAST(TRIM(Product_ID) AS INT)                       AS product_id,
                   TRY_CAST(NULLIF(TRIM(Promotion_ID), '') AS INT)         AS promotion_id,
                   TRY_CAST(NULLIF(TRIM(Quantity), '') AS INT)             AS quantity,
                   TRY_CAST(NULLIF(TRIM(Unit_Price), '') AS DECIMAL(10,2)) AS unit_price
            FROM bronze.transaction_items
        ), ranked AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY line_id ORDER BY transaction_id) AS rn
            FROM src
            WHERE line_id IS NOT NULL AND transaction_id IS NOT NULL AND product_id IS NOT NULL
        )
        INSERT INTO silver.pos_transaction_items
            (line_id, transaction_id, product_id, promotion_id, quantity, unit_price,
             quantity_source, price_source)
        SELECT line_id, transaction_id, product_id, promotion_id,
               CASE WHEN quantity > 0 THEN quantity END,
               CASE WHEN unit_price > 0 THEN unit_price END,
               CASE WHEN quantity > 0 THEN 'source' ELSE 'missing' END,
               CASE WHEN unit_price > 0 THEN 'source' ELSE 'missing' END
        FROM ranked WHERE rn = 1;
        SET @out = @@ROWCOUNT;

        /* POS has no transaction total, so only the median / default fills apply. */
        DROP TABLE IF EXISTS #pos_median;
        SELECT DISTINCT product_id,
               PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY unit_price)
                   OVER (PARTITION BY product_id) AS median_price
        INTO #pos_median
        FROM silver.pos_transaction_items
        WHERE price_source = 'source';

        UPDATE i
        SET    i.unit_price   = ROUND(m.median_price, 2),
               i.price_source = 'product_median'
        FROM   silver.pos_transaction_items AS i
        JOIN   #pos_median AS m ON m.product_id = i.product_id
        WHERE  i.unit_price IS NULL;

        UPDATE silver.pos_transaction_items
        SET    quantity = 1, quantity_source = 'default_1'
        WHERE  quantity IS NULL;

        EXEC etl.log_step @run_id, 'silver', @step, @in, @out, 'Success', @started;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        DECLARE @err NVARCHAR(2000) = LEFT(ERROR_MESSAGE(), 2000);
        EXEC etl.log_step @run_id, 'silver', @step, @in, NULL, 'Failed', @started, @err;
        THROW;
    END CATCH;
END;
GO

GO

/* ######## sql/05_gold.sql ######## */
/* =====================================================================
   05_gold.sql
   Gold = star schema for Power BI.

   - gold.dim_date is a table, rebuilt by gold.load_dim_date to cover the
     full calendar years found in the data, plus a 1900-01-01 "Unknown" row.
   - Every other dimension and both facts are VIEWS on silver, so gold is
     always in step with the latest silver load.
   - Column names match the existing dashboard, so the .pbix only needs its
     data source pointed at RetailDWH. New columns are added at the end.
   - Surrogate key = source ID; -1 = "Unknown" member. Every fact key is
     mapped to -1 when the dimension row is missing, so there are no orphans.

   Business rules in the facts (see README "Data decisions")
   - net_amount = gross_amount - discount_amount, exactly.
   - Online order_status is reconciled with the delivery record:
       Cancelled / Returned on the order          -> kept
       otherwise delivery Delivered / Returned    -> Delivered / Returned
       otherwise                                  -> order status
     The original value stays in order_status_source.
   - delivery_status = 'Not Shipped' when the order has no delivery record.
   - delivery_days = calendar days from ship to delivery, only for
     Delivered orders with a valid (non-negative) gap.
   ===================================================================== */

USE RetailDWH;
GO

/* ============================ dim_date ============================ */

DROP TABLE IF EXISTS gold.dim_date;
GO

CREATE TABLE gold.dim_date (
    date_key       INT          NOT NULL PRIMARY KEY,   -- yyyymmdd
    full_date      DATE         NOT NULL,
    day_of_week    TINYINT      NOT NULL,              -- 1 = Sunday ... 7 = Saturday
    day_name       VARCHAR(10)  NOT NULL,
    day_of_month   TINYINT      NOT NULL,
    day_of_year    SMALLINT     NOT NULL,
    week_of_year   TINYINT      NOT NULL,
    month_number   TINYINT      NOT NULL,
    month_name     VARCHAR(10)  NOT NULL,
    quarter        TINYINT      NOT NULL,
    year           SMALLINT     NOT NULL,
    is_weekend     BIT          NOT NULL,
    year_month     INT          NOT NULL,              -- 202401: sort key for month labels
    month_short    CHAR(3)      NOT NULL,              -- Jan
    year_quarter   INT          NOT NULL               -- 20241: sort key for quarter labels
);
GO

CREATE OR ALTER PROCEDURE gold.load_dim_date
    @run_id UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @run_id IS NULL SET @run_id = NEWID();

    DECLARE @started DATETIME2(0) = SYSDATETIME(),
            @from    DATE,
            @to      DATE,
            @rows    INT;

    /* Full calendar years covering every date the facts can point to. */
    SELECT @from = DATEFROMPARTS(YEAR(MIN(d)), 1, 1),
           @to   = DATEFROMPARTS(YEAR(MAX(d)), 12, 31)
    FROM (
        SELECT CAST(order_datetime AS DATE)       AS d FROM silver.online_orders
        UNION ALL
        SELECT CAST(transaction_datetime AS DATE)      FROM silver.pos_transactions
        UNION ALL
        SELECT CAST(ship_datetime AS DATE)             FROM silver.deliveries
        UNION ALL
        SELECT CAST(delivery_datetime AS DATE)         FROM silver.deliveries
    ) AS all_dates
    WHERE d IS NOT NULL;

    IF @from IS NULL
        THROW 50002, 'gold.load_dim_date: no dates found in silver. Load silver first.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        TRUNCATE TABLE gold.dim_date;

        WITH n AS (            -- one row per day offset in the range
            SELECT TOP (DATEDIFF(DAY, @from, @to) + 1)
                   ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
            FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b
        ), d AS (
            SELECT DATEADD(DAY, i, @from) AS full_date FROM n
        )
        INSERT INTO gold.dim_date
        SELECT YEAR(full_date) * 10000 + MONTH(full_date) * 100 + DAY(full_date),
               full_date,
               DATEDIFF(DAY, '19000107', full_date) % 7 + 1,       -- 1900-01-07 was a Sunday; independent of DATEFIRST
               DATENAME(WEEKDAY, full_date),
               DAY(full_date),
               DATEPART(DAYOFYEAR, full_date),
               DATEPART(WEEK, full_date),
               MONTH(full_date),
               DATENAME(MONTH, full_date),
               DATEPART(QUARTER, full_date),
               YEAR(full_date),
               CASE WHEN DATEDIFF(DAY, '19000107', full_date) % 7 IN (0, 6) THEN 1 ELSE 0 END,
               YEAR(full_date) * 100 + MONTH(full_date),
               LEFT(DATENAME(MONTH, full_date), 3),
               YEAR(full_date) * 10 + DATEPART(QUARTER, full_date)
        FROM d;

        SET @rows = @@ROWCOUNT;

        /* Unknown member for facts with no date (e.g. orders never delivered). */
        INSERT INTO gold.dim_date
        VALUES (19000101, '1900-01-01', 1, 'Unknown', 1, 1, 1, 1, 'Unknown', 1, 1900, 0, 190001, 'N/A', 19001);

        COMMIT TRANSACTION;
        EXEC etl.log_step @run_id, 'gold', 'dim_date', NULL, @rows, 'Success', @started;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @err NVARCHAR(2000) = LEFT(ERROR_MESSAGE(), 2000);
        EXEC etl.log_step @run_id, 'gold', 'dim_date', NULL, NULL, 'Failed', @started, @err;
        THROW;
    END CATCH;
END;
GO

/* ========================== Dimensions =========================== */

CREATE OR ALTER VIEW gold.dim_customer AS
SELECT customer_id     AS customer_key,
       customer_id,
       full_name,
       gender,
       city,
       loyalty_level,
       email,
       is_email_shared,
       CONCAT(full_name, ' (#', customer_id, ')') AS customer_label   -- unique, use in tables
FROM silver.customers
UNION ALL
SELECT -1, 0, 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'N/A', 0, 'Unknown';
GO

CREATE OR ALTER VIEW gold.dim_product AS
SELECT p.product_id                         AS product_key,
       p.product_id,
       p.sku,
       p.product_name,
       ISNULL(b.brand_name, 'Unknown')      AS brand_name,
       ISNULL(d.department_name, 'Unknown') AS department_name,
       p.package_size,
       p.brand_id,
       p.department_id
FROM silver.products         AS p
LEFT JOIN silver.brands      AS b ON b.brand_id      = p.brand_id
LEFT JOIN silver.departments AS d ON d.department_id = p.department_id
UNION ALL
SELECT -1, 0, 'N/A', 'Unknown', 'Unknown', 'Unknown', 'N/A', NULL, NULL;
GO

CREATE OR ALTER VIEW gold.dim_promotion AS
SELECT promotion_id AS promotion_key,
       promotion_id,
       promo_type,
       discount_percent,
       start_date,
       end_date,
       is_discount_missing,
       is_dates_swapped
FROM silver.promotions
UNION ALL
SELECT -1, 0, 'No Promotion', 0, NULL, NULL, 0, 0;
GO

CREATE OR ALTER VIEW gold.dim_store AS
SELECT store_id AS store_key,
       store_id,
       store_name,
       city,
       state,
       region,
       opening_date
FROM silver.stores
UNION ALL
SELECT -1, 0, 'Unknown Store', 'Unknown', 'Unknown', 'Unknown', NULL;
GO

CREATE OR ALTER VIEW gold.dim_employee AS
SELECT employee_id AS employee_key,
       employee_id,
       full_name,
       gender,
       position,
       store_id,
       hire_date
FROM silver.employees
UNION ALL
SELECT -1, 0, 'Unknown Employee', 'Unknown', 'Unknown', 0, NULL;
GO

CREATE OR ALTER VIEW gold.dim_warehouse AS
SELECT warehouse_id AS warehouse_key,
       warehouse_id,
       warehouse_name,
       city,
       state
FROM silver.warehouses
UNION ALL
SELECT -1, 0, 'Unknown Warehouse', 'Unknown', 'Unknown';
GO

CREATE OR ALTER VIEW gold.dim_delivery_provider AS
SELECT provider_id AS delivery_provider_key,
       provider_id,
       provider_name,
       phone
FROM silver.delivery_providers
UNION ALL
SELECT -1, 0, 'Unknown Provider', 'N/A';
GO

/* ============================= Facts ============================= */

CREATE OR ALTER VIEW gold.fact_online_sales AS
WITH lines AS (
    SELECT i.order_item_id,
           i.order_id,
           i.product_id,
           i.promotion_id,
           i.quantity,
           i.unit_price,
           i.quantity_source,
           i.price_source,
           o.customer_id,
           o.warehouse_id,
           o.order_datetime,
           o.order_status                                  AS order_status_source,
           d.provider_id,
           d.ship_datetime,
           d.delivery_datetime,
           d.delivery_status                               AS delivery_status_source,
           d.is_delivery_before_ship,
           pay.payment_method,
           ISNULL(pr.discount_percent, 0)                  AS discount_percent,
           CAST(i.quantity * i.unit_price AS DECIMAL(12,2)) AS gross_amount
    FROM silver.online_order_items AS i
    JOIN silver.online_orders      AS o   ON o.order_id = i.order_id
    LEFT JOIN silver.deliveries    AS d   ON d.order_id = i.order_id
    LEFT JOIN silver.payments      AS pay ON pay.order_id = i.order_id
    LEFT JOIN silver.promotions    AS pr  ON pr.promotion_id = i.promotion_id
)
SELECT l.order_item_id                                                  AS online_sales_key,
       YEAR(l.order_datetime) * 10000 + MONTH(l.order_datetime) * 100 + DAY(l.order_datetime)
                                                                        AS order_date_key,
       ISNULL(YEAR(l.delivery_datetime) * 10000 + MONTH(l.delivery_datetime) * 100 + DAY(l.delivery_datetime),
              19000101)                                                 AS delivery_date_key,
       ISNULL(c.customer_id, -1)                                        AS customer_key,
       ISNULL(p.product_id, -1)                                         AS product_key,
       ISNULL(pr.promotion_id, -1)                                      AS promotion_key,
       ISNULL(w.warehouse_id, -1)                                       AS warehouse_key,
       ISNULL(dp.provider_id, -1)                                       AS delivery_provider_key,
       l.order_id,
       CASE
           WHEN l.order_status_source IN ('Cancelled', 'Returned')  THEN l.order_status_source
           WHEN l.delivery_status_source = 'Delivered'               THEN 'Delivered'
           WHEN l.delivery_status_source = 'Returned'                THEN 'Returned'
           ELSE l.order_status_source
       END                                                              AS order_status,
       ISNULL(l.delivery_status_source, 'Not Shipped')                  AS delivery_status,
       ISNULL(l.payment_method, 'Unknown')                              AS payment_method,
       l.quantity,
       l.unit_price,
       l.discount_percent,
       l.gross_amount,
       CAST(ROUND(l.gross_amount * l.discount_percent / 100, 2) AS DECIMAL(12,2))
                                                                        AS discount_amount,
       CAST(l.gross_amount - ROUND(l.gross_amount * l.discount_percent / 100, 2) AS DECIMAL(12,2))
                                                                        AS net_amount,
       CASE
           WHEN l.delivery_status_source = 'Delivered' AND l.is_delivery_before_ship = 0
           THEN DATEDIFF(DAY, CAST(l.ship_datetime AS DATE), CAST(l.delivery_datetime AS DATE))
       END                                                              AS delivery_days,
       /* ---- added columns ---- */
       l.order_status_source,
       DATEDIFF(DAY, CAST(l.order_datetime AS DATE), CAST(l.ship_datetime AS DATE))
                                                                        AS days_to_ship,
       ISNULL(l.is_delivery_before_ship, 0)                             AS is_delivery_date_invalid,
       l.quantity_source,
       l.price_source
FROM lines AS l
LEFT JOIN silver.customers          AS c  ON c.customer_id   = l.customer_id
LEFT JOIN silver.products           AS p  ON p.product_id    = l.product_id
LEFT JOIN silver.promotions         AS pr ON pr.promotion_id = l.promotion_id
LEFT JOIN silver.warehouses         AS w  ON w.warehouse_id  = l.warehouse_id
LEFT JOIN silver.delivery_providers AS dp ON dp.provider_id  = l.provider_id;
GO

CREATE OR ALTER VIEW gold.fact_pos_sales AS
WITH lines AS (
    SELECT i.line_id,
           i.transaction_id,
           i.product_id,
           i.promotion_id,
           i.quantity,
           i.unit_price,
           i.quantity_source,
           i.price_source,
           t.store_id,
           t.register_id,
           t.employee_id,
           t.customer_id,
           t.transaction_datetime,
           ISNULL(pr.discount_percent, 0)                   AS discount_percent,
           CAST(i.quantity * i.unit_price AS DECIMAL(12,2)) AS gross_amount
    FROM silver.pos_transaction_items AS i
    JOIN silver.pos_transactions      AS t  ON t.transaction_id = i.transaction_id
    LEFT JOIN silver.promotions       AS pr ON pr.promotion_id  = i.promotion_id
)
SELECT l.line_id                                                        AS pos_sales_key,
       YEAR(l.transaction_datetime) * 10000 + MONTH(l.transaction_datetime) * 100 + DAY(l.transaction_datetime)
                                                                        AS date_key,
       ISNULL(c.customer_id, -1)                                        AS customer_key,
       ISNULL(p.product_id, -1)                                         AS product_key,
       ISNULL(pr.promotion_id, -1)                                      AS promotion_key,
       ISNULL(s.store_id, -1)                                           AS store_key,
       ISNULL(e.employee_id, -1)                                        AS employee_key,
       l.transaction_id,
       l.quantity,
       l.unit_price,
       l.discount_percent,
       l.gross_amount,
       CAST(ROUND(l.gross_amount * l.discount_percent / 100, 2) AS DECIMAL(12,2))
                                                                        AS discount_amount,
       CAST(l.gross_amount - ROUND(l.gross_amount * l.discount_percent / 100, 2) AS DECIMAL(12,2))
                                                                        AS net_amount,
       /* ---- added columns ---- */
       l.register_id,
       l.quantity_source,
       l.price_source
FROM lines AS l
LEFT JOIN silver.customers  AS c  ON c.customer_id   = l.customer_id
LEFT JOIN silver.products   AS p  ON p.product_id    = l.product_id
LEFT JOIN silver.promotions AS pr ON pr.promotion_id = l.promotion_id
LEFT JOIN silver.stores     AS s  ON s.store_id      = l.store_id
LEFT JOIN silver.employees  AS e  ON e.employee_id   = l.employee_id;
GO

/* ======================== Pipeline runner ======================== */

CREATE OR ALTER PROCEDURE etl.run_pipeline
    @source_path NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id UNIQUEIDENTIFIER = NEWID();

    PRINT CONCAT('Run ', @run_id, ' started ', SYSDATETIME());

    EXEC bronze.load_bronze  @source_path = @source_path, @run_id = @run_id;
    EXEC silver.load_silver  @run_id = @run_id;
    EXEC gold.load_dim_date  @run_id = @run_id;

    PRINT CONCAT('Run ', @run_id, ' finished ', SYSDATETIME());

    SELECT layer, table_name, rows_in, rows_loaded, rows_rejected, status, message,
           DATEDIFF(SECOND, started_at, finished_at) AS seconds
    FROM etl.load_log
    WHERE run_id = @run_id
    ORDER BY log_id;
END;
GO

GO

/* ######## sql/06_qa_framework.sql ######## */
/* =====================================================================
   06_qa_framework.sql
   Reusable QA engine (same as qa_tests.sql Part 1), installed in RetailDWH.
   Run once. The project's checks are in 07_qa_suite.sql.
   ===================================================================== */

USE RetailDWH;
GO

IF SCHEMA_ID('qa') IS NULL
    EXEC('CREATE SCHEMA qa');
GO

IF OBJECT_ID('qa.test_run') IS NULL
CREATE TABLE qa.test_run (
    run_id       INT IDENTITY(1,1) PRIMARY KEY,
    project_name NVARCHAR(100) NOT NULL,
    started_at   DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    finished_at  DATETIME2(0)  NULL
);
GO

IF OBJECT_ID('qa.test_result') IS NULL
CREATE TABLE qa.test_result (
    result_id    INT IDENTITY(1,1) PRIMARY KEY,
    run_id       INT           NOT NULL REFERENCES qa.test_run(run_id),
    test_name    NVARCHAR(200) NOT NULL,
    layer        NVARCHAR(20)  NOT NULL,   -- bronze / silver / gold
    category     NVARCHAR(50)  NOT NULL,   -- completeness, uniqueness, ...
    severity     NVARCHAR(10)  NOT NULL,   -- error / warning
    status       NVARCHAR(10)  NOT NULL,   -- PASS / FAIL / WARN / ERROR
    bad_rows     BIGINT        NULL,
    details      NVARCHAR(400) NULL,
    bad_rows_sql NVARCHAR(MAX) NULL,       -- run this to see the bad rows
    checked_at   DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO

/* ---------- Start a test run ---------- */
CREATE OR ALTER PROCEDURE qa.start_run
    @project_name NVARCHAR(100),
    @run_id       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO qa.test_run (project_name) VALUES (@project_name);
    SET @run_id = SCOPE_IDENTITY();
END;
GO

/* ---------- Core engine: count bad rows and log the result ----------
   @bad_rows_sql must be a SELECT that returns the bad rows
   (no ORDER BY, unique column names). */
CREATE OR ALTER PROCEDURE qa.run_check
    @run_id       INT,
    @test_name    NVARCHAR(200),
    @layer        NVARCHAR(20),
    @category     NVARCHAR(50),
    @bad_rows_sql NVARCHAR(MAX),
    @severity     NVARCHAR(10)  = N'error',
    @details      NVARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @n BIGINT;
    DECLARE @count_sql NVARCHAR(MAX) =
        N'SELECT @n = COUNT_BIG(*) FROM (' + @bad_rows_sql + N') AS bad;';

    BEGIN TRY
        EXEC sp_executesql @count_sql, N'@n BIGINT OUTPUT', @n = @n OUTPUT;

        INSERT INTO qa.test_result
            (run_id, test_name, layer, category, severity, status, bad_rows, details, bad_rows_sql)
        VALUES
            (@run_id, @test_name, @layer, @category, @severity,
             CASE WHEN ISNULL(@n, 0) = 0  THEN N'PASS'
                  WHEN @severity = N'warning' THEN N'WARN'
                  ELSE N'FAIL' END,
             ISNULL(@n, 0), @details, @bad_rows_sql);
    END TRY
    BEGIN CATCH
        INSERT INTO qa.test_result
            (run_id, test_name, layer, category, severity, status, bad_rows, details, bad_rows_sql)
        VALUES
            (@run_id, @test_name, @layer, @category, @severity,
             N'ERROR', NULL, LEFT(ERROR_MESSAGE(), 400), @bad_rows_sql);
    END CATCH
END;
GO

/* ---------- Table must not be empty ---------- */
CREATE OR ALTER PROCEDURE qa.check_not_empty
    @run_id INT, @layer NVARCHAR(20),
    @schema SYSNAME, @table SYSNAME
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t NVARCHAR(300) = QUOTENAME(@schema) + N'.' + QUOTENAME(@table);
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT 1 AS table_is_empty WHERE NOT EXISTS (SELECT 1 FROM ' + @t + N')';
    DECLARE @name NVARCHAR(200) = N'Not empty: ' + @t;
    EXEC qa.run_check @run_id, @name, @layer, N'completeness', @sql;
END;
GO

/* ---------- Column must not contain NULLs ---------- */
CREATE OR ALTER PROCEDURE qa.check_not_null
    @run_id INT, @layer NVARCHAR(20),
    @schema SYSNAME, @table SYSNAME, @column SYSNAME,
    @severity NVARCHAR(10) = N'error'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t NVARCHAR(300) = QUOTENAME(@schema) + N'.' + QUOTENAME(@table);
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT * FROM ' + @t + N' WHERE ' + QUOTENAME(@column) + N' IS NULL';
    DECLARE @name NVARCHAR(200) = N'No NULLs: ' + @t + N'.' + QUOTENAME(@column);
    EXEC qa.run_check @run_id, @name, @layer, N'completeness', @sql, @severity;
END;
GO

/* ---------- Key must be unique (single or composite, comma-separated) ---------- */
CREATE OR ALTER PROCEDURE qa.check_unique
    @run_id INT, @layer NVARCHAR(20),
    @schema SYSNAME, @table SYSNAME, @key_columns NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t NVARCHAR(300) = QUOTENAME(@schema) + N'.' + QUOTENAME(@table);
    DECLARE @cols NVARCHAR(MAX) =
        (SELECT STRING_AGG(QUOTENAME(TRIM(value)), N', ')
         FROM STRING_SPLIT(@key_columns, N','));
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT ' + @cols + N', COUNT(*) AS duplicate_count FROM ' + @t +
        N' GROUP BY ' + @cols + N' HAVING COUNT(*) > 1';
    DECLARE @name NVARCHAR(200) = N'Unique key: ' + @t + N' (' + @cols + N')';
    EXEC qa.run_check @run_id, @name, @layer, N'uniqueness', @sql,
         N'error', N'bad_rows = number of duplicated key values';
END;
GO

/* ---------- Every fact key must exist in its dimension ---------- */
CREATE OR ALTER PROCEDURE qa.check_orphans
    @run_id INT, @layer NVARCHAR(20),
    @fact_schema SYSNAME, @fact_table SYSNAME, @fact_column SYSNAME,
    @dim_schema  SYSNAME, @dim_table  SYSNAME, @dim_column  SYSNAME
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @f NVARCHAR(300) = QUOTENAME(@fact_schema) + N'.' + QUOTENAME(@fact_table);
    DECLARE @d NVARCHAR(300) = QUOTENAME(@dim_schema)  + N'.' + QUOTENAME(@dim_table);
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT f.* FROM ' + @f + N' AS f LEFT JOIN ' + @d + N' AS d ' +
        N'ON f.' + QUOTENAME(@fact_column) + N' = d.' + QUOTENAME(@dim_column) +
        N' WHERE d.' + QUOTENAME(@dim_column) + N' IS NULL' +
        N' AND f.' + QUOTENAME(@fact_column) + N' IS NOT NULL';
    DECLARE @name NVARCHAR(200) =
        N'No orphans: ' + @f + N'.' + QUOTENAME(@fact_column) + N' -> ' + @d;
    EXEC qa.run_check @run_id, @name, @layer, N'integrity', @sql;
END;
GO

/* ---------- Row counts between layers (tolerance in %) ----------
   Use a tolerance when cleaning is expected to remove some rows. */
CREATE OR ALTER PROCEDURE qa.check_row_count
    @run_id INT, @layer NVARCHAR(20),
    @src_schema SYSNAME, @src_table SYSNAME,
    @tgt_schema SYSNAME, @tgt_table SYSNAME,
    @tolerance_pct DECIMAL(5,2) = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @s NVARCHAR(300) = QUOTENAME(@src_schema) + N'.' + QUOTENAME(@src_table);
    DECLARE @t NVARCHAR(300) = QUOTENAME(@tgt_schema) + N'.' + QUOTENAME(@tgt_table);
    DECLARE @tol NVARCHAR(20) = CONVERT(NVARCHAR(20), @tolerance_pct);
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT s.cnt AS source_rows, t.cnt AS target_rows ' +
        N'FROM (SELECT COUNT_BIG(*) AS cnt FROM ' + @s + N') AS s ' +
        N'CROSS JOIN (SELECT COUNT_BIG(*) AS cnt FROM ' + @t + N') AS t ' +
        N'WHERE ABS(s.cnt - t.cnt) > s.cnt * ' + @tol + N' / 100.0';
    DECLARE @name NVARCHAR(200) = N'Row count: ' + @s + N' vs ' + @t;
    DECLARE @det  NVARCHAR(400) = N'Allowed difference: ' + @tol + N'%';
    EXEC qa.run_check @run_id, @name, @layer, N'reconciliation', @sql, N'error', @det;
END;
GO

/* ---------- Totals must match between layers ---------- */
CREATE OR ALTER PROCEDURE qa.check_sum_match
    @run_id INT, @layer NVARCHAR(20),
    @src_schema SYSNAME, @src_table SYSNAME, @src_column SYSNAME,
    @tgt_schema SYSNAME, @tgt_table SYSNAME, @tgt_column SYSNAME,
    @tolerance DECIMAL(18,4) = 0.01
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @s NVARCHAR(300) = QUOTENAME(@src_schema) + N'.' + QUOTENAME(@src_table);
    DECLARE @t NVARCHAR(300) = QUOTENAME(@tgt_schema) + N'.' + QUOTENAME(@tgt_table);
    DECLARE @tol NVARCHAR(30) = CONVERT(NVARCHAR(30), @tolerance);
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT s.total AS source_total, t.total AS target_total ' +
        N'FROM (SELECT SUM(CAST(' + QUOTENAME(@src_column) + N' AS DECIMAL(38,4))) AS total FROM ' + @s + N') AS s ' +
        N'CROSS JOIN (SELECT SUM(CAST(' + QUOTENAME(@tgt_column) + N' AS DECIMAL(38,4))) AS total FROM ' + @t + N') AS t ' +
        N'WHERE ABS(ISNULL(s.total, 0) - ISNULL(t.total, 0)) > ' + @tol;
    DECLARE @name NVARCHAR(200) =
        N'Totals match: ' + @s + N'.' + QUOTENAME(@src_column) +
        N' vs ' + @t + N'.' + QUOTENAME(@tgt_column);
    EXEC qa.run_check @run_id, @name, @layer, N'reconciliation', @sql;
END;
GO

/* ---------- Statistical outliers (warning only) ----------
   Flags values more than @z standard deviations from the average. */
CREATE OR ALTER PROCEDURE qa.check_outliers
    @run_id INT, @layer NVARCHAR(20),
    @schema SYSNAME, @table SYSNAME, @column SYSNAME,
    @z DECIMAL(5,2) = 4
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @t NVARCHAR(300) = QUOTENAME(@schema) + N'.' + QUOTENAME(@table);
    DECLARE @c NVARCHAR(300) = QUOTENAME(@column);
    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT x.* FROM ' + @t + N' AS x CROSS JOIN ' +
        N'(SELECT AVG(CAST(' + @c + N' AS FLOAT)) AS a, STDEV(CAST(' + @c + N' AS FLOAT)) AS sd FROM ' + @t + N') AS s ' +
        N'WHERE s.sd > 0 AND ABS(CAST(x.' + @c + N' AS FLOAT) - s.a) > ' +
        CONVERT(NVARCHAR(20), @z) + N' * s.sd';
    DECLARE @name NVARCHAR(200) = N'Outliers: ' + @t + N'.' + @c;
    DECLARE @det  NVARCHAR(400) = N'Values beyond ' + CONVERT(NVARCHAR(20), @z) + N' std devs. Check with client.';
    EXEC qa.run_check @run_id, @name, @layer, N'plausibility', @sql, N'warning', @det;
END;
GO

/* ---------- Report: summary + everything that needs attention ---------- */
CREATE OR ALTER PROCEDURE qa.report
    @run_id INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE qa.test_run SET finished_at = SYSDATETIME() WHERE run_id = @run_id;

    -- 1) Summary
    SELECT status, COUNT(*) AS tests
    FROM qa.test_result
    WHERE run_id = @run_id
    GROUP BY status
    ORDER BY CASE status WHEN 'ERROR' THEN 1 WHEN 'FAIL' THEN 2
                         WHEN 'WARN'  THEN 3 ELSE 4 END;

    -- 2) What needs attention (copy bad_rows_sql to see the rows)
    SELECT status, layer, category, test_name, bad_rows, details, bad_rows_sql
    FROM qa.test_result
    WHERE run_id = @run_id AND status <> 'PASS'
    ORDER BY CASE status WHEN 'ERROR' THEN 1 WHEN 'FAIL' THEN 2 ELSE 3 END,
             layer, test_name;

    -- 3) Full list (useful to attach to client delivery)
    SELECT layer, category, test_name, status, bad_rows
    FROM qa.test_result
    WHERE run_id = @run_id
    ORDER BY layer, category, test_name;
END;
GO



GO

/* ######## LOAD ######## */
USE RetailDWH;
GO
EXEC etl.run_pipeline @source_path = N'D:\Freelancing\Datasets\';
GO

/* ######## sql/07_qa_suite.sql ######## */
/* =====================================================================
   07_qa_suite.sql
   Data quality checks for RetailDWH. Run after etl.run_pipeline.
   Needs 06_qa_framework.sql installed once.

   Every check returns the BAD rows: 0 = PASS. Warnings are things to
   know about (not errors). Run as ONE batch; the report is at the end.
   ===================================================================== */

USE RetailDWH;
GO

SET NOCOUNT ON;
DECLARE @run INT;
EXEC qa.start_run @project_name = N'RetailDWH', @run_id = @run OUTPUT;

/* ============================ BRONZE ============================= */
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'brands';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'customers';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'deliveries';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'delivery_providers';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'departments';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'employees';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'inventory';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'online_orders';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'online_order_items';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'payments';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'pos_transactions';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'products';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'product_suppliers';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'promotions';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'registers';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'stores';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'suppliers';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'transaction_items';
EXEC qa.check_not_empty @run, N'bronze', N'bronze', N'warehouses';

/* ============================ SILVER ============================= */

/* No rows lost between bronze and silver (the source has no bad keys). */
EXEC qa.check_row_count @run, N'silver', N'bronze', N'brands',             N'silver', N'brands';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'customers',          N'silver', N'customers';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'deliveries',         N'silver', N'deliveries';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'delivery_providers', N'silver', N'delivery_providers';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'departments',        N'silver', N'departments';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'employees',          N'silver', N'employees';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'inventory',          N'silver', N'inventory';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'online_orders',      N'silver', N'online_orders';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'online_order_items', N'silver', N'online_order_items';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'payments',           N'silver', N'payments';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'pos_transactions',   N'silver', N'pos_transactions';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'products',           N'silver', N'products';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'product_suppliers',  N'silver', N'product_suppliers';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'promotions',         N'silver', N'promotions';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'registers',          N'silver', N'registers';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'stores',             N'silver', N'stores';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'suppliers',          N'silver', N'suppliers';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'transaction_items',  N'silver', N'pos_transaction_items';
EXEC qa.check_row_count @run, N'silver', N'bronze', N'warehouses',         N'silver', N'warehouses';

/* Relationships inside silver. */
EXEC qa.check_orphans @run, N'silver', N'silver', N'online_order_items',    N'order_id',       N'silver', N'online_orders',     N'order_id';
EXEC qa.check_orphans @run, N'silver', N'silver', N'online_order_items',    N'product_id',     N'silver', N'products',          N'product_id';
EXEC qa.check_orphans @run, N'silver', N'silver', N'online_order_items',    N'promotion_id',   N'silver', N'promotions',        N'promotion_id';
EXEC qa.check_orphans @run, N'silver', N'silver', N'online_orders',         N'customer_id',    N'silver', N'customers',         N'customer_id';
EXEC qa.check_orphans @run, N'silver', N'silver', N'online_orders',         N'warehouse_id',   N'silver', N'warehouses',        N'warehouse_id';
EXEC qa.check_orphans @run, N'silver', N'silver', N'deliveries',            N'order_id',       N'silver', N'online_orders',     N'order_id';
EXEC qa.check_orphans @run, N'silver', N'silver', N'payments',              N'order_id',       N'silver', N'online_orders',     N'order_id';
EXEC qa.check_orphans @run, N'silver', N'silver', N'pos_transaction_items', N'transaction_id', N'silver', N'pos_transactions',  N'transaction_id';
EXEC qa.check_orphans @run, N'silver', N'silver', N'pos_transaction_items', N'product_id',     N'silver', N'products',          N'product_id';
EXEC qa.check_orphans @run, N'silver', N'silver', N'pos_transactions',      N'store_id',       N'silver', N'stores',            N'store_id';
EXEC qa.check_orphans @run, N'silver', N'silver', N'pos_transactions',      N'employee_id',    N'silver', N'employees',         N'employee_id';
EXEC qa.check_orphans @run, N'silver', N'silver', N'pos_transactions',      N'customer_id',    N'silver', N'customers',         N'customer_id';
EXEC qa.check_orphans @run, N'silver', N'silver', N'pos_transactions',      N'register_id',    N'silver', N'registers',         N'register_id';
EXEC qa.check_orphans @run, N'silver', N'silver', N'products',              N'brand_id',       N'silver', N'brands',            N'brand_id';
EXEC qa.check_orphans @run, N'silver', N'silver', N'products',              N'department_id',  N'silver', N'departments',       N'department_id';

/* Every missing quantity / price was filled. */
EXEC qa.run_check @run, N'Online items: no quantity or price left unfilled', N'silver', N'completeness',
     N'SELECT * FROM silver.online_order_items WHERE quantity IS NULL OR unit_price IS NULL OR quantity_source = ''missing'' OR price_source = ''missing''';
EXEC qa.run_check @run, N'POS items: no quantity or price left unfilled', N'silver', N'completeness',
     N'SELECT * FROM silver.pos_transaction_items WHERE quantity IS NULL OR unit_price IS NULL OR quantity_source = ''missing'' OR price_source = ''missing''';

/* Business rules. */
EXEC qa.run_check @run, N'Promotions: end date not before start date', N'silver', N'validity',
     N'SELECT * FROM silver.promotions WHERE end_date < start_date';
EXEC qa.run_check @run, N'Promotions: discount between 0 and 100', N'silver', N'validity',
     N'SELECT * FROM silver.promotions WHERE discount_percent NOT BETWEEN 0 AND 100';
EXEC qa.run_check @run, N'Customers: known gender and loyalty level', N'silver', N'standardization',
     N'SELECT * FROM silver.customers WHERE gender NOT IN (''Male'',''Female'',''Unknown'') OR loyalty_level NOT IN (''Bronze'',''Silver'',''Gold'',''Platinum'',''Unknown'')';
EXEC qa.run_check @run, N'Order dates in a sensible range', N'silver', N'validity',
     N'SELECT * FROM silver.online_orders WHERE order_datetime < ''2015-01-01'' OR order_datetime > SYSDATETIME()';

/* Warnings: known source issues, handled and documented. */
EXEC qa.run_check @run, N'Order total differs from item lines (values estimated)', N'silver', N'reconciliation',
     N'SELECT o.order_id, o.order_total, SUM(i.quantity * i.unit_price) AS lines_total
       FROM silver.online_orders o JOIN silver.online_order_items i ON i.order_id = o.order_id
       WHERE o.order_total IS NOT NULL
       GROUP BY o.order_id, o.order_total
       HAVING ABS(SUM(i.quantity * i.unit_price) - o.order_total) > 0.01',
     N'warning', N'Orders where a missing value had to be estimated (median price / quantity 1).';
EXEC qa.run_check @run, N'Deliveries dated before shipping', N'silver', N'validity',
     N'SELECT * FROM silver.deliveries WHERE is_delivery_before_ship = 1',
     N'warning', N'Flagged; gold leaves delivery_days empty for these.';
EXEC qa.run_check @run, N'Promotions with dates swapped in source', N'silver', N'validity',
     N'SELECT * FROM silver.promotions WHERE is_dates_swapped = 1',
     N'warning', N'Start and end were reversed in the source and have been corrected.';
EXEC qa.run_check @run, N'Promotions with no discount in source', N'silver', N'completeness',
     N'SELECT * FROM silver.promotions WHERE is_discount_missing = 1',
     N'warning', N'Treated as 0% discount.';
EXEC qa.run_check @run, N'Customers sharing an email address', N'silver', N'uniqueness',
     N'SELECT * FROM silver.customers WHERE is_email_shared = 1',
     N'warning', N'Different customer IDs, same email. Possible duplicates; confirm with the business.';

/* ============================= GOLD ============================== */

/* Keys are unique. */
EXEC qa.check_unique @run, N'gold', N'gold', N'dim_customer',          N'customer_key';
EXEC qa.check_unique @run, N'gold', N'gold', N'dim_product',           N'product_key';
EXEC qa.check_unique @run, N'gold', N'gold', N'dim_promotion',         N'promotion_key';
EXEC qa.check_unique @run, N'gold', N'gold', N'dim_store',             N'store_key';
EXEC qa.check_unique @run, N'gold', N'gold', N'dim_employee',          N'employee_key';
EXEC qa.check_unique @run, N'gold', N'gold', N'dim_warehouse',         N'warehouse_key';
EXEC qa.check_unique @run, N'gold', N'gold', N'dim_delivery_provider', N'delivery_provider_key';
EXEC qa.check_unique @run, N'gold', N'gold', N'dim_date',              N'date_key';
EXEC qa.check_unique @run, N'gold', N'gold', N'dim_customer',          N'customer_label';
EXEC qa.check_unique @run, N'gold', N'gold', N'fact_online_sales',     N'online_sales_key';
EXEC qa.check_unique @run, N'gold', N'gold', N'fact_pos_sales',        N'pos_sales_key';

/* Every fact key finds its dimension row. */
EXEC qa.check_orphans @run, N'gold', N'gold', N'fact_online_sales', N'order_date_key',        N'gold', N'dim_date',              N'date_key';
EXEC qa.check_orphans @run, N'gold', N'gold', N'fact_online_sales', N'delivery_date_key',     N'gold', N'dim_date',              N'date_key';
EXEC qa.check_orphans @run, N'gold', N'gold', N'fact_online_sales', N'customer_key',          N'gold', N'dim_customer',          N'customer_key';
EXEC qa.check_orphans @run, N'gold', N'gold', N'fact_online_sales', N'product_key',           N'gold', N'dim_product',           N'product_key';
EXEC qa.check_orphans @run, N'gold', N'gold', N'fact_online_sales', N'promotion_key',         N'gold', N'dim_promotion',         N'promotion_key';
EXEC qa.check_orphans @run, N'gold', N'gold', N'fact_online_sales', N'warehouse_key',         N'gold', N'dim_warehouse',         N'warehouse_key';
EXEC qa.check_orphans @run, N'gold', N'gold', N'fact_online_sales', N'delivery_provider_key', N'gold', N'dim_delivery_provider', N'delivery_provider_key';
EXEC qa.check_orphans @run, N'gold', N'gold', N'fact_pos_sales',    N'date_key',              N'gold', N'dim_date',              N'date_key';
EXEC qa.check_orphans @run, N'gold', N'gold', N'fact_pos_sales',    N'customer_key',          N'gold', N'dim_customer',          N'customer_key';
EXEC qa.check_orphans @run, N'gold', N'gold', N'fact_pos_sales',    N'product_key',           N'gold', N'dim_product',           N'product_key';
EXEC qa.check_orphans @run, N'gold', N'gold', N'fact_pos_sales',    N'promotion_key',         N'gold', N'dim_promotion',         N'promotion_key';
EXEC qa.check_orphans @run, N'gold', N'gold', N'fact_pos_sales',    N'store_key',             N'gold', N'dim_store',             N'store_key';
EXEC qa.check_orphans @run, N'gold', N'gold', N'fact_pos_sales',    N'employee_key',          N'gold', N'dim_employee',          N'employee_key';

/* Joins did not add or drop rows. */
EXEC qa.check_row_count @run, N'gold', N'silver', N'online_order_items',    N'gold', N'fact_online_sales';
EXEC qa.check_row_count @run, N'gold', N'silver', N'pos_transaction_items', N'gold', N'fact_pos_sales';

/* Amount arithmetic. */
EXEC qa.run_check @run, N'Online: gross = quantity x price, net = gross - discount', N'gold', N'validity',
     N'SELECT * FROM gold.fact_online_sales
       WHERE ABS(gross_amount - quantity * unit_price) > 0.01
          OR net_amount <> gross_amount - discount_amount
          OR net_amount < 0';
EXEC qa.run_check @run, N'POS: gross = quantity x price, net = gross - discount', N'gold', N'validity',
     N'SELECT * FROM gold.fact_pos_sales
       WHERE ABS(gross_amount - quantity * unit_price) > 0.01
          OR net_amount <> gross_amount - discount_amount
          OR net_amount < 0';

/* Status and delivery rules. */
EXEC qa.run_check @run, N'Online: order status values are known', N'gold', N'standardization',
     N'SELECT * FROM gold.fact_online_sales
       WHERE order_status NOT IN (''Pending'',''Processing'',''Shipped'',''Delivered'',''Returned'',''Cancelled'')';
EXEC qa.run_check @run, N'Online: delivery days not negative', N'gold', N'validity',
     N'SELECT * FROM gold.fact_online_sales WHERE delivery_days < 0';
EXEC qa.run_check @run, N'Online: never-shipped orders have no delivery data', N'gold', N'validity',
     N'SELECT * FROM gold.fact_online_sales
       WHERE delivery_status = ''Not Shipped''
         AND (delivery_date_key <> 19000101 OR delivery_provider_key <> -1 OR delivery_days IS NOT NULL)';

/* Calendar has no gaps between first and last real date. */
EXEC qa.run_check @run, N'dim_date: continuous calendar', N'gold', N'completeness',
     N'SELECT MIN(full_date) AS first_day, MAX(full_date) AS last_day, COUNT(*) AS days
       FROM gold.dim_date WHERE date_key <> 19000101
       HAVING COUNT(*) <> DATEDIFF(DAY, MIN(full_date), MAX(full_date)) + 1';

/* Warnings. */
EXEC qa.check_outliers @run, N'gold', N'gold', N'fact_online_sales', N'net_amount', @z = 4;
EXEC qa.check_outliers @run, N'gold', N'gold', N'fact_pos_sales',    N'net_amount', @z = 4;
EXEC qa.run_check @run, N'Online lines with estimated values', N'gold', N'completeness',
     N'SELECT * FROM gold.fact_online_sales WHERE price_source = ''product_median'' OR quantity_source = ''default_1''',
     N'warning', N'Estimated values; check price_source / quantity_source.';
EXEC qa.run_check @run, N'POS lines with estimated values', N'gold', N'completeness',
     N'SELECT * FROM gold.fact_pos_sales WHERE price_source = ''product_median'' OR quantity_source = ''default_1''',
     N'warning', N'Estimated values; check price_source / quantity_source.';

/* ============================ REPORT ============================= */
EXEC qa.report @run;
