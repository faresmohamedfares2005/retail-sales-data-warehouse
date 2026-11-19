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
