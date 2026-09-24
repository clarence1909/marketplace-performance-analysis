# Marketplace Performance & Seller Health Analysis (Olist)

A portfolio project analyzing the [Brazilian E-Commerce Public Dataset by
Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
(99,441 orders, 2016–2018) to answer marketplace-health questions in the
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

## Key insights

Every figure comes from `sql/04_analysis.sql` run on the Kaggle data for
Jan 2017 – Aug 2018. The full write-up, with recommendations, is in
[`insight_summary.md`](insight_summary.md).

- **Late deliveries cost about 2 stars.** Late orders averaged 2.27
  stars vs 4.29 for on-time orders (95% confidence interval for the gap:
  1.98 to 2.06 stars), and 62.3% of late orders scored 1–2 stars vs 9.2%
  of on-time ones. The gap holds within all 21 states with enough data to
  compare.
- **GMV grew fast, then levelled off.** From R$136,943.46 in Jan 2017 to
  a Black Friday peak of R$1,172,191.68 in Nov 2017, then between
  R$979,486.16 and R$1,156,248.89 a month through 2018 — still +140.4% on
  the same months of 2017.
- **Almost nobody comes back.** Only 3.0% of 94,707 customers placed a
  second order.
- **Two-thirds of GMV comes from 10% of sellers** (66.5%, from 303
  sellers) — and they are no better at delivery: 6.9% of their orders
  arrived late vs 6.4% for the other 2,726 sellers.
- **Slow isn't the same as late.** The remote north has the longest
  deliveries (Roraima 29.9 days vs 12.5 nationally) but few late ones.
  Late rates peak in Alagoas (21.5% vs 6.8% nationally), and Rio de
  Janeiro alone accounts for 22.9% of all late orders.

## Data granularity — the part that's easy to get wrong

This is the section a hiring manager checking SQL fundamentals will
actually read closely, so it's stated explicitly rather than left
implicit in the queries. Every number here comes from
`sql/02_data_quality_checks.sql` run on the real data:

- **`order_items` is item-level, not order-level.** 88,863 orders have
  one item, but 9,803 have two or more (up to 21). Summing `price` without
  grouping by `order_id` first, or joining item rows onto order-level
  data, silently fans out everything downstream.
- **`order_payments` can have multiple rows per order.** 2,961 orders
  have more than one payment row (up to 29), e.g. part voucher, part
  credit card. GMV in this project is therefore defined from
  `order_items` (`price + freight_value`), **not** from summing
  `payment_value` — see the comment at the top of `sql/03_fact_orders.sql`.
- **Reviews don't map one-to-one to orders.** 547 orders have 2–3 review
  rows and 768 have none, so the fact view averages `review_score` per
  order. Separately, 789 `review_id`s are reused across 1,603 rows, so
  `review_id` can't be used as a key either.
- **`customer_id` is generated per order, not per person.** 99,441
  `customer_id`s belong to only 96,096 real customers
  (`customer_unique_id`) — this distinction is *the* mechanism behind the
  repeat-purchase question (Q3), not a side note.
- **A single order can include items from more than one seller** (1,278
  orders, up to 5 sellers). `fact_orders` (one row per order) is the
  right grain for questions 1, 2, 3 and 5, but wrong for seller-level
  analysis (Q4) — that query collapses `order_items` to one row per
  seller per order before measuring anything.
- **Some orders have no items at all** (775, almost all "unavailable" or
  "canceled"). They show up with GMV = 0, and only 5 of them fall inside
  the analysis filters — too few to move average order value.

## Method

1. **`sql/01_create_tables.sql`** — staging tables matching the Kaggle
   CSVs column-for-column, plus pgAdmin import steps. No PK/FK
   constraints at this stage, deliberately — see the comment at the top
   of the file for why.
2. **`sql/02_data_quality_checks.sql`** — row counts, null checks,
   duplicate checks, the granularity checks described above, orphan-key
   checks (none found), date-logic checks, and a check of month-by-month
   order volume that justifies the Jan 2017–Aug 2018 analysis window
   (the months either side have between 0 and 324 orders each, vs
   6,167–7,269 a month in 2018).
3. **`sql/03_fact_orders.sql`** — a single view, one row per order,
   built by aggregating items/payments/reviews to order level *before*
   joining anything, with GMV, review score, and an explicit `is_late`
   flag (`NULL`, not `FALSE`, for orders that were never delivered).
4. **`sql/04_analysis.sql`** — one query per business question, using
   CTEs and window functions (`LAG` for month-over-month, `RANK` and
   `NTILE` for seller/state ranking, `ROW_NUMBER` for repeat-order
   sequencing), plus a 95% confidence interval and a within-state check
   for the headline finding.
5. **Power BI** — `fact_orders` plus seller-comparison queries imported
   as native SQL, a date table, and DAX measures, laid out across four
   dashboard pages. Full steps in `powerbi_guide.md`.

### Verification

All four scripts run end-to-end on the full Kaggle dataset without
edits. `fact_orders` has exactly one row per order (99,441), and its
total GMV (R$15,843,553.24) matches the raw item table to the cent. The
scripts were also tested on hand-built edge cases (a repeat customer, a
late order, a multi-seller order, orphaned keys, a double-reviewed
order) where the right answers were known in advance.

Running on the real data caught two errors that the synthetic test
didn't:

- **Zip codes stored as numbers.** The first version typed zip code
  prefixes as `INT`, but 24% of customer zips start with 0 (`01151`), and
  `INT` silently turns that into `1151`. They're now `CHAR(5)`.
- **Seller metrics counted per item instead of per order.** The first
  Q4 measured late rate and review score over item rows, so a seller
  with three items in one late order was counted late three times. That
  changed the late rate of 821 of 3,029 sellers, by up to 38 percentage
  points. Q4 now collapses items to one row per seller per order first.

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
4. Run `sql/02_data_quality_checks.sql` and compare your output with the
   findings block at the top of the file.
5. Run `sql/03_fact_orders.sql` to create the `fact_orders` view.
6. Run `sql/04_analysis.sql` and compare with the "Result" comment under
   each query — your numbers should match exactly.
7. Follow `powerbi_guide.md` to build the dashboard; section 8 lists the
   numbers each page should show.

## Repo structure

```
sql/
  01_create_tables.sql
  02_data_quality_checks.sql
  03_fact_orders.sql
  04_analysis.sql
powerbi_guide.md
insight_summary.md
cv_bullets.md
interview_prep.md
README.md
```

## Tools

PostgreSQL + pgAdmin (data prep, analysis) · Power BI Desktop (dashboard,
DAX) · GitHub (this repo)
