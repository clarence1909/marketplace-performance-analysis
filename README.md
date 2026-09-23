# Marketplace Performance & Seller Health Analysis (Olist)

A portfolio project analyzing the [Brazilian E-Commerce Public Dataset by
Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
(~100k orders, 2016–2018) to answer marketplace-health questions in the
style of a Business Intelligence Executive role — SQL for data
preparation and analysis, Power BI for the dashboard.

Built to demonstrate: intermediate SQL (CTEs, window functions),
explicit handling of data granularity, data-integrity checking, DAX and
dashboard design, and turning analysis into business recommendations
rather than just charts.

## Why this dataset, why these questions

Olist is a Brazilian multi-seller marketplace — structurally close to a
marketplace like Shopee (many sellers, one platform, shared logistics and
review system), which made it a better fit for practicing marketplace
analytics than a single-retailer dataset. I have no e-commerce work
experience yet (background is clinical data analysis and biotech); this
project exists to close that specific gap with a real, messy, public
dataset rather than a cleaned-up tutorial one.

## Business questions

1. **Do late deliveries lower review scores?** (headline question)
2. How is GMV trending month over month?
3. How many customers make a repeat purchase?
4. Which sellers drive GMV, and how do top sellers compare with the rest
   on late rate and review score?
5. Which customer states have the longest delivery times?

## Data granularity — the part that's easy to get wrong

This is the section a hiring manager checking SQL fundamentals will
actually read closely, so it's stated explicitly rather than left
implicit in the queries:

- **`order_items` is item-level, not order-level.** An order with 3
  products has 3 rows here. Summing `price` directly without grouping by
  `order_id` first overstates order counts and, joined elsewhere,
  silently fans out everything downstream.
- **`order_payments` can have multiple rows per order.** A single order
  paid partly by voucher and partly by credit card produces two payment
  rows. GMV in this project is therefore defined from `order_items`
  (`price + freight_value`), **not** from summing `payment_value` — see
  the comment at the top of `sql/03_fact_orders.sql`.
- **Some orders have more than one review row**, and some have none.
  `sql/02_data_quality_checks.sql` (section D3) quantifies this; the
  fact view averages `review_score` per order so no order is dropped or
  double-counted.
- **`customer_id` is generated per order, not per person.**
  `customer_unique_id` is the column that actually identifies a
  returning shopper — this distinction is *the* mechanism behind the
  repeat-purchase question (Q3), not a side note.
- **A single order can include items from more than one seller.**
  `fact_orders` (one row per order) is the right grain for questions
  1, 2, 3 and 5, but wrong for seller-level analysis (Q4) — that query
  goes back to `order_items` joined with seller info instead, to avoid
  crediting or blaming the wrong seller for another seller's items in a
  shared order.

Every one of these was checked against the actual data in
`sql/02_data_quality_checks.sql` before being assumed — see that file for
the checks, not just this summary.

## Method

1. **`sql/01_create_tables.sql`** — staging tables matching the Kaggle
   CSVs column-for-column, plus pgAdmin import steps. No PK/FK
   constraints at this stage, deliberately — see the comment at the top
   of the file for why.
2. **`sql/02_data_quality_checks.sql`** — row counts, null checks,
   duplicate checks, the granularity checks described above, orphan-key
   checks, and a check of month-by-month order volume that justifies the
   Jan 2017–Aug 2018 analysis window used everywhere downstream.
3. **`sql/03_fact_orders.sql`** — a single view, one row per order,
   built by aggregating items/payments/reviews to order level *before*
   joining anything, with GMV, review score, and an explicit `is_late`
   flag (`NULL`, not `FALSE`, for orders that were never delivered).
4. **`sql/04_analysis.sql`** — one query per business question above,
   using CTEs and window functions (`LAG` for month-over-month, `RANK`
   and `NTILE` for seller/state ranking, `ROW_NUMBER` for repeat-order
   sequencing) where they're a natural fit for the question.
5. **Power BI** — `fact_orders` plus two seller-comparison queries
   imported as native SQL, a date table, and six DAX measures, laid out
   across four dashboard pages. Full steps in `powerbi_guide.md`.

All four SQL scripts have been run end-to-end against a live PostgreSQL
instance with synthetic edge-case rows (a repeat customer, a late order,
a multi-seller order, orphaned keys, a multi-review order, etc.) to
confirm they execute without errors and handle each edge case as
documented — not just written and assumed to work.

## Key insights

*(placeholders — fill in after running `sql/04_analysis.sql` against the
real, loaded dataset; see `insight_summary_template.md` for the fuller
write-up)*

- Late orders averaged **[X]** stars vs **[Y]** stars for on-time orders.
- GMV moved from **[X]** to **[Y]** over the window, peaking at **[Z]**.
- **[X]%** of customers made a repeat purchase.
- The top 10% of sellers by GMV generated **[X]%** of total GMV, with a
  **[Y]%** late rate vs **[Z]%** for the rest.
- **[State]** had the longest average delivery time at **[X]** days.

## Dashboard

*(add screenshots here once built — see `powerbi_guide.md` section 8)*

- `![Marketplace Overview](dashboard/screenshots/01_overview.png)`
- `![Delivery & Customer Experience](dashboard/screenshots/02_delivery.png)`
- `![Seller Health](dashboard/screenshots/03_sellers.png)`
- `![Customers](dashboard/screenshots/04_customers.png)`

## How to reproduce this

1. Download the "Brazilian E-Commerce Public Dataset by Olist" from
   [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
   and unzip it. Ignore the geolocation file — not used in this project.
2. In pgAdmin, create a PostgreSQL database (e.g. `olist_marketplace`).
3. Run `sql/01_create_tables.sql`, then import each CSV using the steps
   at the bottom of that file.
4. Run `sql/02_data_quality_checks.sql` and read the output — the
   numbers you see justify the design choices in the next two files.
5. Run `sql/03_fact_orders.sql` to create the `fact_orders` view.
6. Run `sql/04_analysis.sql` for the five business-question results.
7. Follow `powerbi_guide.md` to build the dashboard.
8. Fill in `insight_summary_template.md` with your real numbers.

## Repo structure

```
sql/
  01_create_tables.sql
  02_data_quality_checks.sql
  03_fact_orders.sql
  04_analysis.sql
powerbi_guide.md
insight_summary_template.md
cv_bullets.md
interview_prep.md
README.md
```

## Tools

PostgreSQL + pgAdmin (data prep, analysis) · Power BI Desktop (dashboard,
DAX) · GitHub (this repo)
