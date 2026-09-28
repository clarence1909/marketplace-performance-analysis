# Power BI Guide: Marketplace Performance & Seller Health Dashboard

This guide walks from an empty Power BI Desktop file to a 4-page dashboard.
The dashboard is built from four data files exported from PostgreSQL by
`sql/05_export_for_powerbi.sql`, so you don't need a database on your PC —
every number still comes from the SQL in this repo. Follow the sections in
order; later steps assume the model built in earlier ones.

## 1. What you need

- **Power BI Desktop** (Windows, free) — from the Microsoft Store or
  microsoft.com/power-bi/desktop.
- **The four data files**, in the `powerbi_data` folder of this project:
  - `fact_orders.csv` — one row per order, Jan 2017 – Aug 2018 (99,092 rows)
  - `seller_tier_comparison.csv` — top 10% of sellers vs the rest (query 4a)
  - `top_sellers.csv` — the top 20 sellers by GMV (query 4b)
  - `customer_repeat_summary.csv` — repeat-purchase summary (query Q3)

  They're included in the repo. To regenerate them from PostgreSQL, run
  `sql/01`–`03` in pgAdmin, then follow the export steps at the top of
  `sql/05_export_for_powerbi.sql`.

## 2. Load the four data files

1. Open Power BI Desktop → **Blank report**.
2. **Home** → **Get data** → **Text/CSV** → pick
   `powerbi_data\fact_orders.csv` → **Open**.
3. In the preview window, check **File Origin** is *65001: Unicode
   (UTF-8)* and **Delimiter** is *Comma*. Set **Data Type Detection** to
   *Based on entire dataset* — Power BI otherwise guesses each column's type
   from the first 200 rows only.
4. Click **Transform Data** (not Load) so you can check the column types
   before anything is built on them. The icon at the left of each column
   header shows its type. They should be:

   | Columns | Type (icon) |
   |---|---|
   | `order_date`, `delivered_date`, `estimated_delivery_date` | Date (calendar) |
   | `is_late` | True/False (✓✗) |
   | `num_items`, `days_vs_estimate` | Whole Number (123) |
   | `item_value`, `freight_value`, `gmv`, `review_score` | Decimal Number (1.2) |
   | everything else | Text (ABC) |

   If one is wrong, click its icon and choose the right type (**Replace
   current** if asked). This matters: if `is_late` loads as text, the Late
   Rate measure quietly returns the wrong answer instead of an error.
5. **Close & Apply**.
6. Repeat **Get data** → **Text/CSV** for the other three files. They're
   small, so **Load** straight away is fine — just check the number columns
   came in as numbers. Keep the default table names (the file names).
7. Check the row count: open **Table view** (the grid icon on the left),
   click `fact_orders`, and read the count at the bottom — it should say
   **99,092 rows**.

Two things are already done for you in the SQL, so there's no need to redo
them in Power BI:

- **The date window.** `fact_orders.csv` only contains Jan 2017 – Aug 2018
  orders — the months either side have too few orders to trend (see section
  H of `sql/02_data_quality_checks.sql`).
- **The seller-level logic.** A single order can contain items from more
  than one seller, so seller late rates and reviews can't be built
  correctly from `fact_orders` alone. The SQL handles this (query 4a/4b in
  `sql/04_analysis.sql`), and the two seller files are its output. They
  don't need relationships to `fact_orders`; they feed their own visuals on
  the Seller Health page.

## 3. Build the Date table

Time intelligence (like GMV month-over-month) needs a proper date table —
without one, `DATEADD` and similar functions behave unpredictably.

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

## 4. DAX measures

Create these on the `fact_orders` table (**Home** → **New Measure**, one
measure at a time), not as calculated columns — measures recalculate for
whatever is selected on the page, which is what a dashboard needs.

`Total GMV` and `Total Orders` exclude `canceled` and `unavailable` orders,
matching Q2–Q4 in `sql/04_analysis.sql`: those orders were never fulfilled,
so counting their value would overstate real marketplace volume.

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

Avg Delivery Days =
AVERAGEX(
    FILTER(fact_orders, NOT ISBLANK(fact_orders[delivered_date])),
    DATEDIFF(fact_orders[order_date], fact_orders[delivered_date], DAY)
)

GMV MoM % =
VAR CurrentGMV = [Total GMV]
VAR PreviousGMV = CALCULATE([Total GMV], DATEADD('Date'[Date], -1, MONTH))
RETURN DIVIDE(CurrentGMV - PreviousGMV, PreviousGMV)
```

Notes:
- `Late Rate`'s denominator deliberately excludes blank `is_late` (orders
  never delivered) rather than counting them as "not late" — same logic as
  `WHERE is_late IS NOT NULL` in the SQL.
- `AVERAGE` ignores blanks automatically, so `Avg Review Score` correctly
  skips orders with no review.
- `Avg Delivery Days` uses `AVERAGEX`, because `AVERAGE` only accepts a
  plain column, not a calculation. The `FILTER` skips orders that were
  never delivered — without it, a blank delivery date is treated as a date
  in 1899 and wrecks the average.
- Format `Late Rate` and `GMV MoM %` as percentages and `Total GMV`/`AOV`
  as currency (Real, R$) in each measure's formatting options.

## 5. Dashboard pages

Use **View → Themes** to pick one consistent theme before building pages,
and keep KPI cards, fonts and colors consistent across all four — small
thing, but it's what makes a dashboard look built by one person on purpose
rather than four unrelated pages.

### Page 1 — Marketplace Overview

- **KPI cards** (top row): `Total GMV`, `Total Orders`, `AOV`, `GMV MoM %`.
  `GMV MoM %` compares the selected month with the month before, so it only
  means something when one month is picked in the slicer below. With
  nothing picked it compares the whole period with itself shifted by a
  month, which isn't meaningful — so either keep the slicer on one month,
  or show `GMV MoM %` in the line chart's tooltip instead of a card.
- **Line chart**: `MonthName` from the `Date` table (sorted by `YearMonth`)
  on the x-axis, `Total GMV` on the y-axis — the headline trend line.
- **Bar chart**: `Total GMV` by `customer_state` — where the volume comes
  from geographically.
- **Slicer**: `MonthName` (from `Date`) so a viewer can zoom into a
  specific period.

### Page 2 — Delivery & Customer Experience

- **KPI cards**: `Late Rate`, `Avg Review Score`, `Avg Delivery Days`.
- **Bar chart**: `Avg Review Score` by `is_late` (Late vs on-time/early) —
  this is the project's headline finding (Q1), so give it the most
  prominent spot on this page. In the visual's filter pane, untick the
  `(Blank)` value of `is_late`: those are orders that were never delivered.
- **Bar chart, sorted descending**: `Avg Delivery Days` by `customer_state`
  (Q5) — add `Late Rate` to the tooltip so a viewer can see both together,
  which is exactly where the "slow isn't the same as late" finding shows.
- **Slicer**: `customer_state`.

### Page 3 — Seller Health

- **Table** from `top_sellers`: `seller_id`, `seller_gmv`, `late_rate_pct`,
  `avg_review_score`, sorted by `gmv_rank` — the top 20 sellers by GMV.
- **Two small column charts** from `seller_tier_comparison`, side by side:
  `seller_group` on the axis, with `late_rate_pct` in one and
  `avg_review_score` in the other — the top-10%-vs-rest comparison (Q4),
  this page's headline visual. Two charts rather than one, because a
  percentage and a 1–5 star score on the same axis make the smaller one
  unreadable.
- **Card**: `pct_of_gmv` from `seller_tier_comparison`, filtered to the
  top-10% row, to state what share of GMV the top sellers represent.

### Page 4 — Customers (optional)

- **KPI card**: `repeat_customer_pct` from `customer_repeat_summary`.
- **Donut or stacked bar**: `one_time_customers` vs `repeat_customers`.

## 6. Before you call it done

- Check your cards against the numbers the SQL produced. With no slicer
  selected (except where noted), the dashboard should show exactly:

  | Page | Visual | Should show |
  |---|---|---|
  | 1 | Total GMV | R$15,683,706.74 |
  | 1 | Total Orders | 97,910 |
  | 1 | AOV | R$160.18 |
  | 1 | GMV MoM % (slicer on Aug 2018) | −4.1% |
  | 1 | Total GMV (slicer on Nov 2017) | R$1,172,191.68 |
  | 2 | Late Rate | 6.8% |
  | 2 | Avg Review Score | 4.09 |
  | 2 | Avg Delivery Days | 12.5 |
  | 2 | Avg Review Score, Late / on-time bars | 2.27 / 4.29 |
  | 3 | pct_of_gmv, top 10% of sellers | 66.5 |
  | 4 | repeat_customer_pct | 3.0 |

  If a card is off, the cause is almost always one of two things: a column
  loaded with the wrong type (Section 2, step 4 — check `is_late` and the
  dates first), or the `canceled`/`unavailable` exclusion typed differently
  in a measure (Section 4).
- Click through every page with a slicer applied and confirm the numbers
  move sensibly. A slicer only affects its own page unless you sync it
  across pages (**View → Sync slicers**).
- Take screenshots of all four pages. They go in the README's Charts
  section, in place of (or above) the static charts there.
- Save the `.pbix` file into this project (e.g.
  `dashboard/marketplace_dashboard.pbix`) so the finished file, not just
  this guide, is part of what a reviewer can open. The `.pbix` stores its
  own copy of the data, so it opens without the CSV files.

## 7. Optional: connect straight to PostgreSQL instead

If you later install PostgreSQL and load the data with `sql/01`–`03`, you
can swap the files for a live connection — worth knowing, since that's how
BI teams usually work:

1. **Get data** → **PostgreSQL database** → **Server** `localhost`,
   **Database** `olist_marketplace` → **Import** mode → sign in with your
   PostgreSQL username and password.
2. In **Navigator**, tick `fact_orders` → **Transform Data**. The view holds
   every order, so filter `order_date` to between 1/1/2017 and 8/31/2018
   (**Date Filters** → **Between…**) before **Close & Apply**.
3. For the three small tables, use **Get data** → **PostgreSQL database**
   → **Advanced options**, and paste query 4a, 4b or Q3 from
   `sql/04_analysis.sql` into the **SQL statement** box.

Current Power BI Desktop includes the PostgreSQL driver (Npgsql), so no
separate install is needed.

Sources:
- [Power Query PostgreSQL connector – Microsoft Learn](https://learn.microsoft.com/en-us/power-query/connectors/postgresql)
