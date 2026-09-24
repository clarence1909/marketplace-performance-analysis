-- ============================================================================
-- 04_analysis.sql
-- Marketplace Performance & Seller Health Analysis (Olist)
-- ============================================================================
-- One query per business question, built on top of fact_orders
-- (03_fact_orders.sql). All queries restrict to the Jan 2017-Aug 2018
-- window -- see section H of 02_data_quality_checks.sql for why.
--
-- The "Result" comment under each query is its actual output on the Kaggle
-- dataset, copied from the query results. Run the file yourself and check
-- your numbers match -- if they don't, something differs in your load.
-- ============================================================================


-- ============================================================================
-- Q1. Do late deliveries lower review scores?  (headline insight)
-- ============================================================================
-- Only delivered orders can be judged late or on-time (is_late IS NULL for
-- anything else -- see 03_fact_orders.sql), so we filter those out rather
-- than letting them dilute the average. pct_1_or_2_stars counts orders
-- whose (average) review score is 2 or lower.
SELECT
    CASE WHEN is_late THEN 'Late' ELSE 'On-time or early' END              AS delivery_group,
    COUNT(*)                                                               AS num_orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                     AS pct_of_orders,
    ROUND(AVG(review_score), 2)                                            AS avg_review_score,
    ROUND(100.0 * COUNT(*) FILTER (WHERE review_score <= 2) / COUNT(*), 1) AS pct_1_or_2_stars,
    ROUND(AVG(days_vs_estimate), 1)                                        AS avg_days_vs_estimate
FROM fact_orders
WHERE is_late IS NOT NULL
  AND review_score IS NOT NULL
  AND order_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY is_late
ORDER BY is_late;
-- Result: 6,379 of 95,561 delivered, reviewed orders (6.7%) were late.
-- Late orders averaged 2.27 stars vs 4.29 for on-time/early orders, and
-- 62.3% of late orders scored 1-2 stars vs 9.2% of on-time ones. On
-- average, late orders arrived 10.5 days after the estimate; on-time orders
-- arrived 13.4 days before it.

-- Q1b. Is that gap real, or could it be noise? A 95% confidence interval
-- for the difference in average score (normal approximation, which is
-- safe at these sample sizes). If the interval is nowhere near 0, the gap
-- isn't chance.
WITH grp AS (
    SELECT
        is_late,
        COUNT(*)               AS n,
        AVG(review_score)      AS mean_score,
        VAR_SAMP(review_score) AS var_score
    FROM fact_orders
    WHERE is_late IS NOT NULL
      AND review_score IS NOT NULL
      AND order_date BETWEEN '2017-01-01' AND '2018-08-31'
    GROUP BY is_late
)
SELECT
    ROUND(l.mean_score - o.mean_score, 2)                                     AS diff_late_minus_ontime,
    ROUND((l.mean_score - o.mean_score)
          - 1.96 * SQRT(l.var_score / l.n + o.var_score / o.n), 2)            AS ci95_low,
    ROUND((l.mean_score - o.mean_score)
          + 1.96 * SQRT(l.var_score / l.n + o.var_score / o.n), 2)            AS ci95_high,
    ROUND((l.mean_score - o.mean_score)
          / SQRT(l.var_score / l.n + o.var_score / o.n), 1)                   AS z_score
FROM grp l
JOIN grp o ON l.is_late AND NOT o.is_late;
-- Result: -2.02 stars, 95% CI -2.06 to -1.98 (z = -100.8). Not noise.

-- Q1c. Could it just be a regional effect -- e.g. remote states get both
-- more late deliveries AND grumpier reviewers? Compare late vs on-time
-- WITHIN each state (states with at least 30 late orders, so each
-- comparison has enough data).
WITH by_state AS (
    SELECT
        customer_state,
        COUNT(*) FILTER (WHERE is_late)              AS late_orders,
        AVG(review_score) FILTER (WHERE NOT is_late) AS ontime_avg,
        AVG(review_score) FILTER (WHERE is_late)     AS late_avg
    FROM fact_orders
    WHERE is_late IS NOT NULL
      AND review_score IS NOT NULL
      AND order_date BETWEEN '2017-01-01' AND '2018-08-31'
    GROUP BY customer_state
)
SELECT
    customer_state,
    late_orders,
    ROUND(ontime_avg, 2)            AS ontime_avg_score,
    ROUND(late_avg, 2)              AS late_avg_score,
    ROUND(ontime_avg - late_avg, 2) AS gap
FROM by_state
WHERE late_orders >= 30
ORDER BY gap;
-- Result: the gap holds in all 21 qualifying states, from 1.63 to 2.62
-- stars. Still an association rather than proof of cause, but it's not
-- explained by where customers live.


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
-- Result: GMV grew from R$136,943.46 in Jan 2017 to R$996,973.51 in
-- Aug 2018, peaking at R$1,172,191.68 in Nov 2017 (+53.3% MoM). Through
-- 2018 it levelled off between R$979,486.16 (Feb) and R$1,156,248.89 (Apr)
-- a month. Adding up the monthly rows: Jan-Aug 2018 = R$8,593,137.50 vs
-- Jan-Aug 2017 = R$3,574,992.04, i.e. +140.4% for the same eight months.

-- Q2b. What caused the Nov 2017 spike? Drill down to the busiest days.
SELECT order_date, COUNT(*) AS orders_placed
FROM fact_orders
WHERE order_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY order_date
ORDER BY orders_placed DESC
LIMIT 5;
-- Result: 24 Nov 2017 -- Black Friday -- had 1,176 orders, more than
-- double the next-busiest day (25 Nov 2017, 499).


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
-- Result: of 94,707 unique customers in the window, only 2,875 (3.0%)
-- placed more than one order; 91,832 bought once.


-- ============================================================================
-- Q4. Which sellers drive GMV, and how do top sellers compare with the rest
--     on late rate and review score?
-- ============================================================================
-- fact_orders is one row per ORDER, but a single order can include items
-- from more than one seller (1,278 orders on the Kaggle data), so
-- seller-level analysis goes back to order_items.
--
-- The grain matters twice here. order_items is one row per ITEM, but
-- delivery status and review score belong to the ORDER. So seller_orders
-- first collapses items to ONE ROW PER (seller, order): a seller who
-- shipped 3 items in one late order has one late order, not three.
-- (An earlier version measured late rate and review per item row; on the
-- Kaggle data that changed the late rate of 821 of 3,029 sellers, by up to
-- 38 percentage points. GMV is unaffected -- it is summed from items either
-- way.)
--
-- Attribution caveat: a late multi-seller order counts as late for every
-- seller in it, because Olist records delivery per order, not per seller.
--
-- The seller_orders/seller_summary/ranked_sellers CTEs are repeated in 4a
-- and 4b. A WITH clause only stays in scope for the one statement it's
-- attached to, so repeating it keeps 4a and 4b each independently runnable
-- (as pgAdmin's "Execute" on just one block).

-- 4a. Top decile vs the rest, side by side.
--   late_rate_pct / avg_review_score are order-weighted: of all the group's
--   orders, what share arrived late / what did they score. That's what
--   customers actually experienced.
--   avg_seller_* are the plain average across sellers (each seller counts
--   once however small) -- the "typical seller" view, shown for comparison.
WITH seller_orders AS (
    SELECT
        oi.seller_id,
        oi.order_id,
        SUM(oi.price + oi.freight_value) AS seller_order_gmv,
        fo.is_late,
        fo.review_score
    FROM order_items oi
    JOIN fact_orders fo ON fo.order_id = oi.order_id
    WHERE fo.order_status NOT IN ('canceled', 'unavailable')
      AND fo.order_date BETWEEN '2017-01-01' AND '2018-08-31'
    GROUP BY oi.seller_id, oi.order_id, fo.is_late, fo.review_score
),
seller_summary AS (
    SELECT
        seller_id,
        SUM(seller_order_gmv)                        AS seller_gmv,
        COUNT(*)                                     AS num_orders,
        COUNT(*) FILTER (WHERE is_late IS NOT NULL)  AS delivered_orders,
        COUNT(*) FILTER (WHERE is_late)              AS late_orders,
        COUNT(review_score)                          AS reviewed_orders,
        SUM(review_score)                            AS review_score_sum,
        ROUND(AVG(review_score), 2)                  AS avg_review_score,
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE is_late)
            / NULLIF(COUNT(*) FILTER (WHERE is_late IS NOT NULL), 0)
        , 1)                                         AS late_rate_pct
    FROM seller_orders
    GROUP BY seller_id
),
ranked_sellers AS (
    SELECT
        *,
        RANK()    OVER (ORDER BY seller_gmv DESC) AS gmv_rank,
        NTILE(10) OVER (ORDER BY seller_gmv DESC) AS gmv_decile   -- decile 1 = top 10% by GMV
    FROM seller_summary
)
SELECT
    CASE WHEN gmv_decile = 1 THEN 'Top 10% of sellers by GMV' ELSE 'Remaining 90%' END AS seller_group,
    COUNT(*)                                                                AS num_sellers,
    SUM(seller_gmv)                                                         AS total_gmv,
    ROUND(100.0 * SUM(seller_gmv) / SUM(SUM(seller_gmv)) OVER (), 1)        AS pct_of_gmv,
    ROUND(100.0 * SUM(late_orders) / NULLIF(SUM(delivered_orders), 0), 1)  AS late_rate_pct,
    ROUND(SUM(review_score_sum) / NULLIF(SUM(reviewed_orders), 0), 2)       AS avg_review_score,
    ROUND(AVG(late_rate_pct), 1)                                            AS avg_seller_late_rate_pct,
    ROUND(AVG(avg_review_score), 2)                                         AS avg_seller_review_score
FROM ranked_sellers
GROUP BY seller_group
ORDER BY seller_group;
-- Result: the top 10% of sellers (303 sellers) generated 66.5% of GMV
-- (R$10,436,449.08). They are not better at delivery: 6.9% of their orders
-- arrived late vs 6.4% for the remaining 2,726 sellers, with an average
-- review of 4.08 vs 4.13. The typical-seller view is close to even
-- (7.1% vs 7.0% late, 4.07 vs 4.05 stars).

-- 4b. The actual top 20 sellers, for a table/drilldown in the dashboard.
WITH seller_orders AS (
    SELECT
        oi.seller_id,
        oi.order_id,
        SUM(oi.price + oi.freight_value) AS seller_order_gmv,
        fo.is_late,
        fo.review_score
    FROM order_items oi
    JOIN fact_orders fo ON fo.order_id = oi.order_id
    WHERE fo.order_status NOT IN ('canceled', 'unavailable')
      AND fo.order_date BETWEEN '2017-01-01' AND '2018-08-31'
    GROUP BY oi.seller_id, oi.order_id, fo.is_late, fo.review_score
),
seller_summary AS (
    SELECT
        seller_id,
        SUM(seller_order_gmv)        AS seller_gmv,
        COUNT(*)                     AS num_orders,
        ROUND(AVG(review_score), 2)  AS avg_review_score,
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE is_late)
            / NULLIF(COUNT(*) FILTER (WHERE is_late IS NOT NULL), 0)
        , 1)                         AS late_rate_pct
    FROM seller_orders
    GROUP BY seller_id
),
ranked_sellers AS (
    SELECT
        *,
        RANK() OVER (ORDER BY seller_gmv DESC) AS gmv_rank
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
-- The national_* columns use SUM(...) OVER () on top of the GROUP BY
-- aggregates, so every row carries the order-weighted national figure to
-- compare against. late_orders / pct_of_all_late_orders show where late
-- deliveries pile up in absolute terms, not just as a rate.
SELECT
    customer_state,
    COUNT(*)                                                               AS num_delivered_orders,
    ROUND(AVG(delivered_date - order_date), 1)                             AS avg_delivery_days,
    ROUND(AVG(days_vs_estimate), 1)                                        AS avg_days_vs_estimate,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / NULLIF(COUNT(*), 0), 1) AS late_rate_pct,
    COUNT(*) FILTER (WHERE is_late)                                        AS late_orders,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE is_late)
        / SUM(COUNT(*) FILTER (WHERE is_late)) OVER ()
    , 1)                                                                   AS pct_of_all_late_orders,
    ROUND(SUM(SUM(delivered_date - order_date)) OVER ()
          / SUM(COUNT(*)) OVER (), 1)                                      AS national_avg_delivery_days,
    ROUND(100.0 * SUM(COUNT(*) FILTER (WHERE is_late)) OVER ()
          / SUM(COUNT(*)) OVER (), 1)                                      AS national_late_rate_pct,
    RANK() OVER (ORDER BY AVG(delivered_date - order_date) DESC)           AS slowest_rank
FROM fact_orders
WHERE is_late IS NOT NULL  -- only orders we actually know were delivered
  AND order_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY customer_state
ORDER BY avg_delivery_days DESC;
-- Result: the slowest states are in the remote north -- Roraima (RR) at
-- 29.9 days, Amapa (AP) 27.2, Amazonas (AM) 26.4 -- against 12.5 days
-- nationally and 8.7 in Sao Paulo (SP). But slow is not the same as late:
-- AP and AM are late only 3.0% and 2.8% of the time, because their
-- estimates are generous. Lateness concentrates elsewhere: Alagoas (AL)
-- 21.5%, Maranhao (MA) 17.5% and Sergipe (SE) 15.4% late, vs 6.8%
-- nationally. And in absolute terms, Rio de Janeiro (RJ) -- 12.1% late
-- on 12,310 delivered orders -- accounts for 1,495 late orders, 22.9% of
-- all late orders, second only to SP (1,817).
-- Small-sample caution: RR has only 40 delivered orders and AP only 67.
