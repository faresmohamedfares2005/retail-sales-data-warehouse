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
