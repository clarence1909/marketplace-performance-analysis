
-- 05_export_for_powerbi.sql
-- Marketplace Performance & Seller Health Analysis (Olist)

-- Purpose
--   Produce the four data files the Power BI dashboard is built from, so the
--   dashboard can be built without a live database connection. Every number
--   in the dashboard still comes from PostgreSQL -- this script is the
--   hand-off point, and keeping it in the repo means the files can always
--   be regenerated exactly.
--
-- The four files (saved in powerbi_data/ and kept in the repo, so the
-- dashboard can be built without a database; this script regenerates them):
--   1. fact_orders.csv              -- the query below
--   2. seller_tier_comparison.csv   -- query 4a in 04_analysis.sql
--   3. top_sellers.csv              -- query 4b in 04_analysis.sql
--   4. customer_repeat_summary.csv  -- query Q3 in 04_analysis.sql
-- Files 2-4 reuse the queries in 04_analysis.sql rather than copying them
-- here, so there is only one version of each piece of logic.
--
-- How to export from pgAdmin
--   1. Run 01-03 first, so fact_orders exists.
--   2. Open the Query Tool, run one query at a time (select it, press F5).
--   3. In the Data Output panel, click "Save results to file" (the download
--      icon). Save as CSV and rename it to the file name above.
--   Or, from psql, wrap the query as:
--      \copy (<query>) TO 'fact_orders.csv' WITH (FORMAT csv, HEADER true)
--      (note: \copy needs the whole command on one line)




-- 1. fact_orders.csv
-- One row per order, already limited to the Jan 2017 - Aug 2018 analysis
-- window (see section H of 02_data_quality_checks.sql), so Power BI doesn't
-- need its own date filter. All order statuses are kept: the DAX measures
-- exclude canceled/unavailable orders from GMV and order counts themselves,
-- matching Q2-Q4 in 04_analysis.sql.
--
-- is_late is cast to text so it exports as true/false (which Power BI reads
-- as a True/False column) rather than PostgreSQL's t/f. Blank means the
-- order was never delivered.
--
-- Expected on the Kaggle data: 99,092 rows.

SELECT
    order_id,
    customer_unique_id,
    customer_state,
    order_status,
    order_date,
    num_items,
    item_value,
    freight_value,
    gmv,
    review_score,
    delivered_date,
    estimated_delivery_date,
    days_vs_estimate,
    is_late::TEXT AS is_late
FROM fact_orders
WHERE order_date BETWEEN '2017-01-01' AND '2018-08-31'
ORDER BY order_date, order_id;
