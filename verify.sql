USE RetailDWH;
SELECT metric, value FROM (
SELECT 1 AS n, 'rows rejected in silver (last run)' AS metric, CAST(SUM(ISNULL(rows_rejected,0)) AS VARCHAR(50)) AS value FROM etl.load_log WHERE layer='silver' AND run_id=(SELECT TOP 1 run_id FROM etl.load_log ORDER BY log_id DESC)
UNION ALL SELECT 2, 'failed steps (last run)', CAST(COUNT(*) AS VARCHAR(50)) FROM etl.load_log WHERE status<>'Success' AND run_id=(SELECT TOP 1 run_id FROM etl.load_log ORDER BY log_id DESC)
UNION ALL SELECT 3, 'fact_online_sales rows', CAST(COUNT(*) AS VARCHAR(50)) FROM gold.fact_online_sales
UNION ALL SELECT 4, 'fact_pos_sales rows', CAST(COUNT(*) AS VARCHAR(50)) FROM gold.fact_pos_sales
UNION ALL SELECT 5, 'online net total', CAST(SUM(net_amount) AS VARCHAR(50)) FROM gold.fact_online_sales
UNION ALL SELECT 6, 'online net excl cancelled', CAST(SUM(net_amount) AS VARCHAR(50)) FROM gold.fact_online_sales WHERE order_status<>'Cancelled'
UNION ALL SELECT 7, 'pos net total', CAST(SUM(net_amount) AS VARCHAR(50)) FROM gold.fact_pos_sales
UNION ALL SELECT 8, 'online net 2024 / 2025', STRING_AGG(CAST(v AS VARCHAR(30)), ' / ') FROM (SELECT LEFT(order_date_key,4) y, SUM(net_amount) v FROM gold.fact_online_sales GROUP BY LEFT(order_date_key,4)) x
UNION ALL SELECT 9, 'pos net 2024 / 2025', STRING_AGG(CAST(v AS VARCHAR(30)), ' / ') FROM (SELECT LEFT(date_key,4) y, SUM(net_amount) v FROM gold.fact_pos_sales GROUP BY LEFT(date_key,4)) x
UNION ALL SELECT 10, 'avg delivery days', CAST(CAST(AVG(CAST(delivery_days AS DECIMAL(10,4))) AS DECIMAL(10,2)) AS VARCHAR(50)) FROM gold.fact_online_sales
UNION ALL SELECT 11, 'online price_source', STRING_AGG(CONCAT(price_source,'=',c), ' ') FROM (SELECT price_source, COUNT(*) c FROM silver.online_order_items GROUP BY price_source) x
UNION ALL SELECT 12, 'online quantity_source', STRING_AGG(CONCAT(quantity_source,'=',c), ' ') FROM (SELECT quantity_source, COUNT(*) c FROM silver.online_order_items GROUP BY quantity_source) x
UNION ALL SELECT 13, 'orders by final status', STRING_AGG(CONCAT(order_status,'=',c), ' ') FROM (SELECT order_status, COUNT(DISTINCT order_id) c FROM gold.fact_online_sales GROUP BY order_status) x
UNION ALL SELECT 14, 'dim_date range', CONCAT(MIN(full_date),' to ',MAX(full_date),' (',COUNT(*),' rows)') FROM gold.dim_date WHERE date_key<>19000101
) t ORDER BY n;
