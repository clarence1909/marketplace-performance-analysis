-- ============================================================================
-- 02_data_quality_checks.sql
-- Marketplace Performance & Seller Health Analysis (Olist)
-- ============================================================================
-- Purpose
--   Run these BEFORE trusting anything downstream. Each block below tests one
--   thing and says why it matters. Run the whole file top to bottom in
--   pgAdmin's Query Tool; read the output of each block before moving to the
--   next one -- some of the choices in 03_fact_orders.sql depend on what you
--   find here (e.g. how review_score is aggregated, why GMV isn't summed
--   from order_payments).
-- ============================================================================


-- ============================================================================
-- A. ROW COUNTS
-- What it tests: the basic shape of the data -- did every CSV actually load?
-- A table with 0 rows, or a count wildly different from what Kaggle's
-- dataset card advertises (roughly 99k orders), means the import step failed
-- silently for that table.
-- ============================================================================
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'product_category_name_translation', COUNT(*) FROM product_category_name_translation
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
ORDER BY table_name;


-- ============================================================================
-- B. NULLS IN COLUMNS THE ANALYSIS DEPENDS ON
-- What it tests: whether the columns we're about to build measures on
-- (dates, ids, prices) are ever missing. A NULL order_purchase_timestamp
-- would silently vanish from any month-by-month trend; a NULL price would
-- understate GMV.
-- ============================================================================
SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL)                       AS null_order_id,
    COUNT(*) FILTER (WHERE customer_id IS NULL)                    AS null_customer_id,
    COUNT(*) FILTER (WHERE order_status IS NULL)                   AS null_order_status,
    COUNT(*) FILTER (WHERE order_purchase_timestamp IS NULL)       AS null_purchase_ts,
    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL)  AS null_delivered_date,
    COUNT(*) FILTER (WHERE order_estimated_delivery_date IS NULL)  AS null_estimated_date
FROM orders;

SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL)     AS null_order_id,
    COUNT(*) FILTER (WHERE product_id IS NULL)   AS null_product_id,
    COUNT(*) FILTER (WHERE seller_id IS NULL)    AS null_seller_id,
    COUNT(*) FILTER (WHERE price IS NULL)        AS null_price,
    COUNT(*) FILTER (WHERE freight_value IS NULL) AS null_freight
FROM order_items;

SELECT
    COUNT(*) FILTER (WHERE customer_unique_id IS NULL) AS null_customer_unique_id,
    COUNT(*) FILTER (WHERE customer_state IS NULL)     AS null_customer_state
FROM customers;


-- ============================================================================
-- C. DUPLICATE CHECKS ON EACH TABLE'S INTENDED GRAIN
-- What it tests: whether the natural key we assumed for each table (see the
-- comments in 01_create_tables.sql) is actually unique. If customer_id
-- repeats in `customers`, for instance, a plain join would fan out and
-- silently inflate every downstream count.
-- ============================================================================

-- C1. customers: customer_id should be unique
SELECT customer_id, COUNT(*) AS n
FROM customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- C2. orders: order_id should be unique
SELECT order_id, COUNT(*) AS n
FROM orders
GROUP BY order_id
HAVING COUNT(*) > 1;

-- C3. order_items: (order_id, order_item_id) should be unique
SELECT order_id, order_item_id, COUNT(*) AS n
FROM order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;

-- C4. order_payments: (order_id, payment_sequential) should be unique
SELECT order_id, payment_sequential, COUNT(*) AS n
FROM order_payments
GROUP BY order_id, payment_sequential
HAVING COUNT(*) > 1;

-- C5. fully duplicated rows anywhere in order_reviews (same review applied twice)
SELECT review_id, order_id, review_score, review_creation_date, COUNT(*) AS n
FROM order_reviews
GROUP BY review_id, order_id, review_score, review_creation_date
HAVING COUNT(*) > 1;


-- ============================================================================
-- D. GRANULARITY CHECKS
-- What it tests: how many child rows each order actually has in the
-- item / payment / review tables. This is the single most important check
-- in this file -- it's the difference between reporting real numbers and
-- silently double-counting. The results tell us exactly how to aggregate
-- in 03_fact_orders.sql.
-- ============================================================================

-- D1. items per order (order_items is item-level, not order-level)
SELECT items_per_order, COUNT(*) AS num_orders
FROM (
    SELECT order_id, COUNT(*) AS items_per_order
    FROM order_items
    GROUP BY order_id
) t
GROUP BY items_per_order
ORDER BY items_per_order;

-- D2. payment rows per order (some orders split payment across methods)
SELECT payments_per_order, COUNT(*) AS num_orders
FROM (
    SELECT order_id, COUNT(*) AS payments_per_order
    FROM order_payments
    GROUP BY order_id
) t
GROUP BY payments_per_order
ORDER BY payments_per_order;

-- D3. review rows per order (should mostly be 1, sometimes 0, rarely >1)
SELECT reviews_per_order, COUNT(*) AS num_orders
FROM (
    SELECT order_id, COUNT(*) AS reviews_per_order
    FROM order_reviews
    GROUP BY order_id
) t
GROUP BY reviews_per_order
ORDER BY reviews_per_order;

-- D4. customer_id vs customer_unique_id: proves customer_id is per-order,
-- not per-person. Expect distinct customer_id to be noticeably higher than
-- distinct customer_unique_id -- that gap IS the repeat-purchase signal
-- used in Q3 of 04_analysis.sql.
SELECT
    COUNT(DISTINCT customer_id)         AS distinct_customer_id,
    COUNT(DISTINCT customer_unique_id)  AS distinct_customer_unique_id
FROM customers;


-- ============================================================================
-- E. ORPHAN-KEY CHECKS
-- What it tests: referential integrity that isn't enforced by a constraint
-- (see 01_create_tables.sql for why). An order_item pointing at a seller_id
-- that doesn't exist in `sellers` would silently disappear from any join,
-- understating seller-level GMV without any error being raised.
-- ============================================================================

-- E1. order_items -> orders
SELECT COUNT(*) AS orphan_order_items_missing_order
FROM order_items oi
LEFT JOIN orders o ON o.order_id = oi.order_id
WHERE o.order_id IS NULL;

-- E2. order_items -> products
SELECT COUNT(*) AS orphan_order_items_missing_product
FROM order_items oi
LEFT JOIN products p ON p.product_id = oi.product_id
WHERE p.product_id IS NULL;

-- E3. order_items -> sellers
SELECT COUNT(*) AS orphan_order_items_missing_seller
FROM order_items oi
LEFT JOIN sellers s ON s.seller_id = oi.seller_id
WHERE s.seller_id IS NULL;

-- E4. orders -> customers
SELECT COUNT(*) AS orphan_orders_missing_customer
FROM orders o
LEFT JOIN customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL;

-- E5. order_payments -> orders
SELECT COUNT(*) AS orphan_payments_missing_order
FROM order_payments op
LEFT JOIN orders o ON o.order_id = op.order_id
WHERE o.order_id IS NULL;

-- E6. order_reviews -> orders
SELECT COUNT(*) AS orphan_reviews_missing_order
FROM order_reviews r
LEFT JOIN orders o ON o.order_id = r.order_id
WHERE o.order_id IS NULL;

-- E7. products -> product_category_name_translation
-- (a missing translation isn't fatal -- category isn't used in the 5 core
-- business questions -- but worth knowing if you extend the dashboard)
SELECT COUNT(DISTINCT p.product_category_name) AS categories_without_translation
FROM products p
LEFT JOIN product_category_name_translation t
    ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL;


-- ============================================================================
-- F. DATE LOGIC CHECKS
-- What it tests: whether the delivery dates are internally consistent. These
-- feed directly into the is_late flag in 03_fact_orders.sql, so a bug here
-- becomes a bug in the headline finding (Q1).
-- ============================================================================

-- F1. Orders "delivered" before they were purchased -- should be zero.
SELECT COUNT(*) AS delivered_before_purchase
FROM orders
WHERE order_delivered_customer_date < order_purchase_timestamp;

-- F2. Orders with status = 'delivered' but no delivered_customer_date --
-- these can't get an is_late flag even though the status says they arrived.
SELECT COUNT(*) AS delivered_status_missing_date
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;

-- F3. Orders with a delivered_customer_date but a status that isn't
-- 'delivered' -- a status/date mismatch worth knowing about.
SELECT order_status, COUNT(*) AS n
FROM orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_status <> 'delivered'
GROUP BY order_status;


-- ============================================================================
-- G. ORDER STATUS MIX
-- What it tests: what proportion of orders are canceled / unavailable /
-- still in flight. This decides whether those statuses should be excluded
-- from GMV and delivery metrics in 03/04 (canceled orders were never
-- fulfilled, so counting their GMV would overstate real marketplace volume).
-- ============================================================================
SELECT
    order_status,
    COUNT(*)                                  AS num_orders,
    MIN(order_purchase_timestamp)             AS earliest_order,
    MAX(order_purchase_timestamp)             AS latest_order
FROM orders
GROUP BY order_status
ORDER BY num_orders DESC;


-- ============================================================================
-- H. MONTHLY ORDER VOLUME -- JUSTIFIES THE Jan 2017-Aug 2018 ANALYSIS WINDOW
-- What it tests: order volume by calendar month across the full history.
-- Olist's data technically starts in Sep 2016 and runs to Oct 2018, but the
-- first few months and the last couple of months have only a handful of
-- orders (the marketplace was just starting, and the extract cuts off
-- mid-flow at the end). Run this block and look at the row counts for
-- 2016-09 through 2016-12 and for 2018-09 onwards -- they'll be a small
-- fraction of a normal month's volume. Trending GMV or review scores through
-- those months would show misleading spikes/dips driven by tiny sample
-- sizes, not real marketplace behaviour. That's why every query in
-- 04_analysis.sql and the Power BI model filter to Jan 2017-Aug 2018.
-- ============================================================================
SELECT
    DATE_TRUNC('month', order_purchase_timestamp)::DATE AS order_month,
    COUNT(*)                                              AS num_orders
FROM orders
GROUP BY 1
ORDER BY 1;
