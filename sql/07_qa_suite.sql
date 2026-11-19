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
