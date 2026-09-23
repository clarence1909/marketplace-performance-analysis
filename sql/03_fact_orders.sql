-- ============================================================================
-- 03_fact_orders.sql
-- Marketplace Performance & Seller Health Analysis (Olist)
-- ============================================================================
-- Purpose
--   A single view, one row per order_id, that every query in 04_analysis.sql
--   and the Power BI model can GROUP BY / filter freely without worrying
--   about fan-out from order_items, order_payments or order_reviews. All the
--   granularity decisions below are informed by 02_data_quality_checks.sql --
--   run that first if you haven't.
--
-- GMV definition (stated explicitly, per the project rules)
--   GMV = item price + freight value, summed across every item line in the
--   order. This comes from order_items, NOT order_payments -- payments can
--   be split across multiple rows per order (installments, voucher +
--   card, etc.) and summing them would double-count. price + freight from
--   order_items is the actual value of what was sold and shipped.
--
-- review_score
--   A small number of orders have more than one review row (see check D3 in
--   02_data_quality_checks.sql). We AVG() the score per order so no order is
--   dropped or double-counted. For the large majority of orders, which have
--   exactly one review, this is simply that review's score.
--
-- is_late / days_vs_estimate
--   Only an order that has actually been delivered can be judged late or
--   on-time. If order_delivered_customer_date is NULL (not yet delivered,
--   canceled, lost, etc.), is_late is NULL -- not FALSE -- so it's never
--   accidentally counted as "on time" in an average. Downstream queries
--   filter WHERE is_late IS NOT NULL when they need delivered orders only.
--   days_vs_estimate is estimated date minus delivered date: positive means
--   delivered before the estimate (good), negative means delivered after it
--   (late).
-- ============================================================================

CREATE OR REPLACE VIEW fact_orders AS
WITH item_agg AS (
    -- Collapse order_items from item-level to order-level FIRST, before it
    -- touches anything else, so nothing downstream can fan it out again.
    SELECT
        order_id,
        COUNT(*)             AS num_items,
        SUM(price)            AS item_value,
        SUM(freight_value)     AS freight_value
    FROM order_items
    GROUP BY order_id
),
review_agg AS (
    SELECT
        order_id,
        AVG(review_score)::NUMERIC(3,2) AS review_score
    FROM order_reviews
    WHERE review_score IS NOT NULL
    GROUP BY order_id
)
SELECT
    o.order_id,
    c.customer_id,
    c.customer_unique_id,
    c.customer_state,
    c.customer_city,
    o.order_status,
    o.order_purchase_timestamp::DATE                                          AS order_date,
    ia.num_items,
    ia.item_value,
    ia.freight_value,
    COALESCE(ia.item_value, 0) + COALESCE(ia.freight_value, 0)                 AS gmv,
    ra.review_score,
    o.order_delivered_customer_date::DATE                                     AS delivered_date,
    o.order_estimated_delivery_date::DATE                                      AS estimated_delivery_date,
    (o.order_estimated_delivery_date::DATE - o.order_delivered_customer_date::DATE) AS days_vs_estimate,
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN NULL
        WHEN o.order_delivered_customer_date::DATE > o.order_estimated_delivery_date::DATE THEN TRUE
        ELSE FALSE
    END                                                                        AS is_late
FROM orders o
LEFT JOIN customers c  ON c.customer_id = o.customer_id
LEFT JOIN item_agg ia   ON ia.order_id = o.order_id
LEFT JOIN review_agg ra ON ra.order_id = o.order_id;

-- Note on order_status: this view keeps ALL orders, including canceled and
-- unavailable ones -- it's meant to be a general-purpose fact table, not a
-- pre-filtered one. Queries that compute revenue-style metrics (GMV, AOV)
-- should exclude order_status IN ('canceled', 'unavailable') explicitly, as
-- done in 04_analysis.sql; queries about the funnel or cancellation rate
-- would want those rows. Keeping the filter at the query level rather than
-- baking it into the view keeps that choice visible instead of hidden.

-- Quick sanity check after creating the view: row count here should exactly
-- match COUNT(*) FROM orders (one row per order, no fan-out).
-- SELECT COUNT(*) FROM fact_orders;
