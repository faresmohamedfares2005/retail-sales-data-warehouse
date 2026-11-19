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
