-- ============================================================================
-- 04_analysis.sql
-- Marketplace Performance & Seller Health Analysis (Olist)
-- ============================================================================
-- One query per business question, built on top of fact_orders
-- (03_fact_orders.sql). All queries restrict to the Jan 2017-Aug 2018
-- window -- see section H of 02_data_quality_checks.sql for why.
--
-- Every figure below is a placeholder: [X], [Y], [Z] etc. Replace them by
-- actually running each query against your loaded database. Do not fill
-- these in by guessing.
-- ============================================================================


-- ============================================================================
-- Q1. Do late deliveries lower review scores?  (headline insight)
-- ============================================================================
-- Only delivered orders can be judged late or on-time (is_late IS NULL for
-- anything else -- see 03_fact_orders.sql), so we filter those out rather
-- than letting them dilute the average.
SELECT
    CASE WHEN is_late THEN 'Late' ELSE 'On-time or early' END AS delivery_group,
    COUNT(*)                                    AS num_orders,
    ROUND(AVG(review_score), 2)                 AS avg_review_score,
    ROUND(AVG(days_vs_estimate), 1)             AS avg_days_vs_estimate
FROM fact_orders
WHERE is_late IS NOT NULL
  AND review_score IS NOT NULL
  AND order_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY is_late
ORDER BY is_late;
-- Read as: "[X]% of orders were late; late orders averaged [Y] stars vs
-- [Z] stars for on-time orders."


-- ============================================================================
-- Q2. How is GMV trending month over month?
-- ============================================================================
-- order_status filter: canceled/unavailable orders were never fulfilled, so
-- they're excluded from a revenue-style trend (they're still visible in
-- fact_orders for anyone who wants a funnel view).
WITH monthly_gmv AS (
    SELECT
        DATE_TRUNC('month', order_date)::DATE AS order_month,
        SUM(gmv)                               AS gmv,
        COUNT(*)                               AS num_orders
    FROM fact_orders
    WHERE order_status NOT IN ('canceled', 'unavailable')
      AND order_date BETWEEN '2017-01-01' AND '2018-08-31'
    GROUP BY 1
)
SELECT
    order_month,
    gmv,
    num_orders,
    ROUND(gmv / NULLIF(num_orders, 0), 2)                                   AS aov,
    LAG(gmv) OVER (ORDER BY order_month)                                     AS prior_month_gmv,
    ROUND(
        100.0 * (gmv - LAG(gmv) OVER (ORDER BY order_month))
        / NULLIF(LAG(gmv) OVER (ORDER BY order_month), 0)
    , 1)                                                                     AS gmv_mom_pct
FROM monthly_gmv
ORDER BY order_month;
-- Read as: "GMV grew from [X] in [month] to [Y] in [month], peaking at [Z]
-- in [month] (+[N]% MoM)."


-- ============================================================================
-- Q3. How many customers make a repeat purchase?  (by customer_unique_id)
-- ============================================================================
-- customer_id is per-order; customer_unique_id is the real person (see
-- check D4 in 02_data_quality_checks.sql). ROW_NUMBER numbers each person's
-- orders in date order, so MAX(order_sequence) per person tells us how many
-- orders they ever placed.
WITH customer_orders AS (
    SELECT
        customer_unique_id,
        order_id,
        order_date,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id ORDER BY order_date
        ) AS order_sequence
    FROM fact_orders
    WHERE order_status NOT IN ('canceled', 'unavailable')
      AND order_date BETWEEN '2017-01-01' AND '2018-08-31'
),
customer_summary AS (
    SELECT
        customer_unique_id,
        MAX(order_sequence) AS total_orders
    FROM customer_orders
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*) FILTER (WHERE total_orders = 1)  AS one_time_customers,
    COUNT(*) FILTER (WHERE total_orders > 1)  AS repeat_customers,
    COUNT(*)                                   AS total_customers,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE total_orders > 1) / NULLIF(COUNT(*), 0)
    , 1)                                        AS repeat_customer_pct
FROM customer_summary;
-- Read as: "Of [X] unique customers in the window, only [Y] ([Z]%) placed
-- more than one order."


-- ============================================================================
-- Q4. Which sellers drive GMV, and how do top sellers compare with the rest
--     on late rate and review score?
-- ============================================================================
-- fact_orders is one row per ORDER, but a single order can include items
-- from more than one seller, so seller-level analysis goes back to
-- order_items (joined to fact_orders for status/date/is_late/review_score)
-- rather than fact_orders alone.
--
-- NOTE: the seller_items/seller_summary/ranked_sellers CTEs below are
-- repeated in both 4a and 4b. A WITH clause only stays in scope for the one
-- statement it's attached to, so a CTE can't be shared across two separate
-- semicolon-terminated queries -- repeating it keeps 4a and 4b each
-- independently runnable (as pgAdmin's "Execute" on just one block).

-- 4a. Top decile vs the rest, side by side
WITH seller_items AS (
    SELECT
        oi.seller_id,
        oi.order_id,
        oi.price + oi.freight_value AS item_gmv,
        fo.is_late,
        fo.review_score
    FROM order_items oi
    JOIN fact_orders fo ON fo.order_id = oi.order_id
    WHERE fo.order_status NOT IN ('canceled', 'unavailable')
      AND fo.order_date BETWEEN '2017-01-01' AND '2018-08-31'
),
seller_summary AS (
    SELECT
        seller_id,
        SUM(item_gmv)                                              AS seller_gmv,
        COUNT(DISTINCT order_id)                                   AS num_orders,
        ROUND(AVG(review_score), 2)                                AS avg_review_score,
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE is_late)
            / NULLIF(COUNT(*) FILTER (WHERE is_late IS NOT NULL), 0)
        , 1)                                                        AS late_rate_pct
    FROM seller_items
    GROUP BY seller_id
),
ranked_sellers AS (
    SELECT
        *,
        RANK()  OVER (ORDER BY seller_gmv DESC)  AS gmv_rank,
        NTILE(10) OVER (ORDER BY seller_gmv DESC) AS gmv_decile   -- decile 1 = top 10% by GMV
    FROM seller_summary
)
SELECT
    CASE WHEN gmv_decile = 1 THEN 'Top 10% of sellers by GMV' ELSE 'Remaining 90%' END AS seller_group,
    COUNT(*)                       AS num_sellers,
    SUM(seller_gmv)                 AS total_gmv,
    ROUND(AVG(late_rate_pct), 1)    AS avg_late_rate_pct,
    ROUND(AVG(avg_review_score), 2) AS avg_review_score
FROM ranked_sellers
GROUP BY seller_group
ORDER BY seller_group;
-- Read as: "The top 10% of sellers ([X] sellers) generated [Y]% of GMV
-- ([Z] total), with a late rate of [A]% vs [B]% for the rest, and an
-- average review of [C] vs [D]."

-- 4b. The actual top 20 sellers, for a table/drilldown in the dashboard
WITH seller_items AS (
    SELECT
        oi.seller_id,
        oi.order_id,
        oi.price + oi.freight_value AS item_gmv,
        fo.is_late,
        fo.review_score
    FROM order_items oi
    JOIN fact_orders fo ON fo.order_id = oi.order_id
    WHERE fo.order_status NOT IN ('canceled', 'unavailable')
      AND fo.order_date BETWEEN '2017-01-01' AND '2018-08-31'
),
seller_summary AS (
    SELECT
        seller_id,
        SUM(item_gmv)                                              AS seller_gmv,
        COUNT(DISTINCT order_id)                                   AS num_orders,
        ROUND(AVG(review_score), 2)                                AS avg_review_score,
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE is_late)
            / NULLIF(COUNT(*) FILTER (WHERE is_late IS NOT NULL), 0)
        , 1)                                                        AS late_rate_pct
    FROM seller_items
    GROUP BY seller_id
),
ranked_sellers AS (
    SELECT
        *,
        RANK()  OVER (ORDER BY seller_gmv DESC)  AS gmv_rank,
        NTILE(10) OVER (ORDER BY seller_gmv DESC) AS gmv_decile
    FROM seller_summary
)
SELECT
    seller_id,
    seller_gmv,
    num_orders,
    late_rate_pct,
    avg_review_score,
    gmv_rank
FROM ranked_sellers
ORDER BY gmv_rank
LIMIT 20;


-- ============================================================================
-- Q5. Which customer states have the longest delivery times?
-- ============================================================================
SELECT
    customer_state,
    COUNT(*)                                                       AS num_delivered_orders,
    ROUND(AVG(delivered_date - order_date), 1)                     AS avg_delivery_days,
    ROUND(AVG(days_vs_estimate), 1)                                 AS avg_days_vs_estimate,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE is_late) / NULLIF(COUNT(*), 0)
    , 1)                                                             AS late_rate_pct,
    RANK() OVER (ORDER BY AVG(delivered_date - order_date) DESC)     AS slowest_rank
FROM fact_orders
WHERE is_late IS NOT NULL  -- only orders we actually know were delivered
  AND order_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY customer_state
ORDER BY avg_delivery_days DESC;
-- Read as: "[State X] has the longest average delivery time at [Y] days
-- ([Z]% late), compared with [A] days nationally."
