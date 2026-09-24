# Power BI Guide: Marketplace Performance & Seller Health Dashboard

This guide walks from an empty Power BI Desktop file to a 4-page dashboard
built on top of the PostgreSQL database from `sql/01_create_tables.sql` –
`sql/04_analysis.sql`. Follow it in order — later steps assume the model
built in earlier ones.

Run the SQL scripts first (in pgAdmin, in numeric order) before starting
here. This guide assumes `fact_orders` already exists in your database.

## 1. Prerequisites

- Power BI Desktop (Windows), any recent version. Since December 2019,
  Power BI Desktop ships with the Npgsql PostgreSQL driver built in, so
  no separate driver install is needed for a normal, up-to-date install.
  If you're on a very old version and the PostgreSQL connector errors out
  asking for a provider, install Npgsql 4.0.17 from the
  [Npgsql releases page](https://github.com/npgsql/npgsql/releases/tag/v4.0.17),
  matching Power BI's bitness (almost always 64-bit), and select "Npgsql
  GAC Installation" during setup.
- PostgreSQL running locally (or reachable) with the Olist data already
  loaded and `fact_orders` created.
- Your PostgreSQL username/password handy.

## 2. Connect Power BI to PostgreSQL

1. Open Power BI Desktop → **Get Data** → search **PostgreSQL database** →
   **Connect**.
2. **Server**: `localhost` (or your server address). **Database**: the
   name you created in pgAdmin (e.g. `olist_marketplace`).
3. **Data Connectivity mode**: choose **Import**. At ~100k orders this
   dataset is small enough that Import gives you a faster, fully
   interactive dashboard; DirectQuery would just add query latency for
   no benefit here.
4. Click **OK**. If prompted about encryption, and your local Postgres
   isn't set up for SSL, choose the unencrypted-connection option to
   proceed (fine for a local portfolio project; wouldn't be for a
   production database with real customer data).
5. Enter your **Database** credentials (username/password) → **Connect**.
6. In **Navigator**, tick:
   - `fact_orders` (the view)
   - `sellers`
   That's the core model. Don't select the raw `orders`, `order_items`,
   `order_payments`, `order_reviews` tables here — `fact_orders` already
   rolled them up correctly, and pulling in the raw item/payment/review
   tables alongside it risks re-introducing the exact fan-out problem
   `03_fact_orders.sql` was built to avoid.
7. Click **Transform Data** (not Load yet) — we need one filter step
   first.

## 3. Filter to the analysis window in Power Query

The project restricts every business-question query to **Jan 2017 – Aug
2018** because the surrounding months have too few orders to trend
reliably (see section H of `sql/02_data_quality_checks.sql`). Apply the
same restriction here, once, so every visual in the dashboard inherits it
automatically instead of you having to remember it per chart:

1. In the **Power Query Editor**, select the `fact_orders` query on the
   left.
2. Click the filter dropdown on the `order_date` column header → **Date
   Filters** → **Between…** → `1/1/2017` and `8/31/2018` → **OK**.
3. Confirm the step appears in the **Applied Steps** pane on the right
   (e.g. "Filtered Rows") — this is what makes the restriction durable
   rather than a one-off click.
4. Click **Close & Apply**.

## 4. Add the seller comparison table

`fact_orders` is one row per **order**, but a single order can contain
items from more than one seller (see `sql/03_fact_orders.sql` and query
4a/4b in `sql/04_analysis.sql`). Seller-level GMV, late rate, and review
score therefore can't be built correctly from `fact_orders` alone in
DAX — the SQL already solves this correctly with `order_items` and
window functions (`NTILE`, `RANK`), so the simplest, least error-prone
option is to reuse that query result directly rather than rebuild the
same logic a second time in DAX:

1. **Get Data** → **PostgreSQL database** again → same server/database.
2. Expand **Advanced options** → paste the entire **4a** query from
   `sql/04_analysis.sql` (the one that returns `seller_group`,
   `num_sellers`, `total_gmv`, `pct_of_gmv`, `late_rate_pct`,
   `avg_review_score` and two `avg_seller_*` columns) into the **SQL
   statement** box → **OK**.
3. Name this query `seller_tier_comparison` in the Queries pane.
4. Repeat once more for the **4b** query (top 20 sellers) and name it
   `top_sellers`.
5. **Close & Apply**. You now have two extra, independent tables — they
   don't need a relationship to `fact_orders`; they're pre-aggregated and
   used on their own visuals on the Seller Health page.

(If you later want interactive drill-down from a seller to their
individual orders, the next step up is importing `order_items` as a
second fact table and relating it to both `fact_orders` (on `order_id`)
and `sellers` (on `seller_id`). Not required for the four dashboard pages
below — worth knowing as an extension if you want to push the project
further.)

## 5. Build the Date table

Time intelligence (like GMV month-over-month) needs a proper date
dimension — relating a measure directly to a text/date column on the fact
table without one will make `DATEADD` and similar functions behave
unpredictably.

1. **Home** → **New Table** (not New Column) and enter:
   ```
   Date = CALENDAR(DATE(2017,1,1), DATE(2018,8,31))
   ```
2. With the new `Date` table selected, add four columns — click **New
   Column** once for each line:
   ```
   Year = YEAR('Date'[Date])
   MonthNumber = MONTH('Date'[Date])
   YearMonth = YEAR('Date'[Date]) * 100 + MONTH('Date'[Date])
   MonthName = FORMAT('Date'[Date], "MMM YYYY")
   ```
3. Click the `MonthName` column → **Column tools** → **Sort by column** →
   `YearMonth`. Without this, Power BI sorts month names alphabetically
   (Apr 2017, Apr 2018, Aug 2017, ...), which scrambles every chart and
   slicer that uses them.
4. Go to **Model view**. Right-click the `Date` table → **Mark as date
   table** → choose the `Date` column → **OK**.
5. Still in Model view, drag from `Date[Date]` to `fact_orders[order_date]`
   to create the relationship. Confirm it's **one-to-many** (one row in
   Date per day, many orders per day) with a single-direction filter from
   `Date` → `fact_orders`. Power BI usually infers this correctly, but
   check it in the relationship's properties if a visual later behaves
   oddly.

## 6. DAX measures

Create these on the `fact_orders` table (**Home** → **New Measure**), not
as calculated columns — measures recalculate per filter context (per
page, per slicer selection), which is what a dashboard needs.

Two of them (`Total GMV`, `Total Orders`) exclude `canceled` and
`unavailable` orders, matching the same exclusion applied in Q2–Q5 of
`sql/04_analysis.sql` — canceled orders were never actually fulfilled, so
counting their value would overstate real marketplace volume. Keeping the
same filter in both places means the SQL and the dashboard numbers should
match if you ever cross-check them, which is worth doing once as a sanity
check.

```
Total GMV =
CALCULATE(
    SUM(fact_orders[gmv]),
    fact_orders[order_status] <> "canceled",
    fact_orders[order_status] <> "unavailable"
)

Total Orders =
CALCULATE(
    DISTINCTCOUNT(fact_orders[order_id]),
    fact_orders[order_status] <> "canceled",
    fact_orders[order_status] <> "unavailable"
)

AOV =
DIVIDE([Total GMV], [Total Orders])

Late Rate =
DIVIDE(
    CALCULATE(COUNTROWS(fact_orders), fact_orders[is_late] = TRUE()),
    CALCULATE(COUNTROWS(fact_orders), NOT ISBLANK(fact_orders[is_late]))
)

Avg Review Score =
AVERAGE(fact_orders[review_score])

GMV MoM % =
VAR CurrentGMV = [Total GMV]
VAR PreviousGMV = CALCULATE([Total GMV], DATEADD('Date'[Date], -1, MONTH))
RETURN DIVIDE(CurrentGMV - PreviousGMV, PreviousGMV)
```

Notes:
- `Late Rate`'s denominator deliberately excludes blank `is_late` (orders
  never delivered) rather than counting them as "not late" — same logic
  as `WHERE is_late IS NOT NULL` in the SQL.
- `AVERAGE` in DAX ignores blanks automatically, so `Avg Review Score`
  correctly skips orders with no review without extra handling.
- Format `Late Rate`, `GMV MoM %` as percentages and `Total GMV`/`AOV` as
  currency (Real, R$) in the measure's formatting pane.

## 7. Dashboard pages

Use **View → Themes** to pick one consistent theme before building pages,
and keep KPI cards, fonts and colors consistent across all four — small
thing, but it's what makes a dashboard look built by one person on
purpose rather than four unrelated pages.

### Page 1 — Marketplace Overview

- **KPI cards** (top row): `Total GMV`, `Total Orders`, `AOV`, `GMV MoM %`.
  `GMV MoM %` compares the selected month with the month before, so it
  only means something when one month is picked in the slicer below. With
  nothing picked it compares the whole period with itself shifted by a
  month, which isn't meaningful — so either keep the slicer on one month,
  or show `GMV MoM %` in the line chart's tooltip instead of a card.
- **Line chart**: `MonthName` from the `Date` table (sorted by
  `YearMonth`) on the x-axis, `Total GMV` on the y-axis — the headline
  trend line.
- **Bar chart**: `Total GMV` by `customer_state` — where the volume is
  coming from geographically.
- **Slicer**: `MonthName` (from `Date`) so a viewer can zoom into a
  specific period.

### Page 2 — Delivery & Customer Experience

- **KPI cards**: `Late Rate`, `Avg Review Score`, and one more measure
  (create it the same way as the others in Section 6):
  ```
  Avg Delivery Days =
  AVERAGEX(
      FILTER(fact_orders, NOT ISBLANK(fact_orders[delivered_date])),
      DATEDIFF(fact_orders[order_date], fact_orders[delivered_date], DAY)
  )
  ```
  `AVERAGEX` rather than `AVERAGE`, because DAX's `AVERAGE` only accepts a
  plain column, not a calculation. The `FILTER` skips orders that were
  never delivered — without it, a blank delivery date is treated as a date
  in 1899 and wrecks the average.
- **Bar chart**: `Avg Review Score` by `is_late` (Late vs on-time/early)
  — this is the project's headline finding (Q1), so give it the most
  prominent spot on this page. In the visual's filter pane, untick the
  `(Blank)` value of `is_late`: those are orders that were never
  delivered.
- **Bar chart, sorted descending**: `Avg Delivery Days` by
  `customer_state` (Q5) — add `Late Rate` as a secondary measure in the
  tooltip so a viewer can see both together.
- **Slicer**: `customer_state`.

### Page 3 — Seller Health

- **Table or clustered bar chart** from `top_sellers`: `seller_id`,
  `seller_gmv`, `late_rate_pct`, `avg_review_score`, sorted by
  `gmv_rank` — the top 20 sellers by GMV.
- **Two small column charts** from `seller_tier_comparison`, side by
  side: `seller_group` on the axis, with `late_rate_pct` in one and
  `avg_review_score` in the other — the top-10%-vs-rest comparison (Q4),
  this page's headline visual. Two charts rather than one, because a
  percentage and a 1–5 star score on the same axis make the smaller one
  unreadable.
- **Card**: `pct_of_gmv` from `seller_tier_comparison`, filtered to the
  top-decile row, to state what share of GMV the top sellers represent.

### Page 4 — Customers (optional)

- Import one more native-SQL table the same way as Section 4, using the
  Q3 query from `sql/04_analysis.sql` (repeat-purchase summary); call it
  `customer_repeat_summary`.
- **KPI card**: `repeat_customer_pct` from that table.
- **Donut or stacked bar**: `one_time_customers` vs `repeat_customers`.
- If you want a distribution rather than just the yes/no split, add a
  `GROUP BY total_orders` variant of the Q3 query (how many customers
  placed exactly 1, 2, 3+ orders) as a further native-SQL table and chart
  it as a simple column chart.

## 8. Before you call it done

- Check your cards against the numbers the SQL produced on the Kaggle
  data. With no slicer selected (except where noted), the dashboard
  should show exactly:

  | Page | Visual | Should show |
  |---|---|---|
  | 1 | Total GMV | R$15,683,706.74 |
  | 1 | Total Orders | 97,910 |
  | 1 | AOV | R$160.18 |
  | 1 | GMV MoM % (slicer on Aug 2018) | −4.1% |
  | 2 | Late Rate | 6.8% |
  | 2 | Avg Review Score | 4.09 |
  | 2 | Avg Delivery Days | 12.5 |
  | 3 | pct_of_gmv, top 10% of sellers | 66.5 |
  | 4 | repeat_customer_pct | 3.0 |

  If a card is off, the cause is almost always a filter applied in one
  place and not the other: the Jan 2017–Aug 2018 window (Section 3) or the
  `canceled`/`unavailable` exclusion (Section 6).
- Click through every page with a slicer applied and confirm the numbers
  move sensibly. A slicer only affects its own page unless you sync it
  across pages (**View → Sync slicers**).
- Cross-check one number by hand: pick a single month's `Total GMV` card
  on Page 1 and compare it to the same month's `gmv` value from the Q2
  query in `sql/04_analysis.sql` run directly in pgAdmin. They should
  match exactly — if they don't, the mismatch is almost always the
  `canceled`/`unavailable` filter being applied in one place and not the
  other.
- Take screenshots of all four pages for the `README.md` placeholders.
- Save the `.pbix` file into this repo (e.g. `dashboard/marketplace_dashboard.pbix`)
  so the finished file, not just this guide, is part of what a reviewer
  can open.

Sources:
- [Power Query PostgreSQL connector – Microsoft Learn](https://learn.microsoft.com/en-us/power-query/connectors/postgresql)
