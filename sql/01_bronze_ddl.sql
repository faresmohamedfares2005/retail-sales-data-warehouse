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
