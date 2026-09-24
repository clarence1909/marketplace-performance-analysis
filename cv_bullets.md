# CV Bullet Options

Three options for the same project — pick whichever fits the rest of your
CV's tone, or mix phrases from more than one. Every number comes from the
SQL in this repo run on the Kaggle data (see the "Result" comments in
`sql/04_analysis.sql`). If you rerun it and get anything different, use
your numbers, not these.

**1. SQL / data modeling emphasis**

> Built a PostgreSQL model of a 99,441-order, 8-table e-commerce dataset,
> using CTEs and window functions (LAG, RANK, NTILE) to resolve item-,
> payment- and review-level granularity into an order-level fact view that
> reconciles to raw GMV to the cent; validating on real data caught two
> silent errors, including a seller-metric grain bug that skewed 821
> sellers' late-delivery rates.

**2. Insight / dashboard emphasis** *(only once the dashboard is built)*

> Showed that late deliveries on a Brazilian marketplace averaged 2.27
> review stars vs 4.29 on time across 95,561 orders (95% CI for the gap:
> 1.98–2.06), with 62.3% of late orders scoring 1–2 stars vs 9.2%; built a
> 4-page Power BI dashboard with DAX measures to track delivery, GMV and
> seller health.

**3. Data-quality / benchmarking emphasis**

> Audited a 99,441-order marketplace dataset (duplicates, orphan keys,
> granularity, date logic) before analysis, then benchmarked the top 10% of
> sellers — 66.5% of GMV — against the rest, showing they were no better at
> on-time delivery (6.9% vs 6.4% late) and pinpointing state-level
> late-delivery hotspots (up to 21.5% vs 6.8% nationally).

**Notes on using these**

- Keep whichever bullet you use to one or two lines if your CV format is
  dense — these are written slightly long so you have material to trim
  rather than pad.
- Only use bullet 2 once the Power BI dashboard actually exists. Every
  claim on a CV should be something you can open and show.
- For the Shopee Malaysia BI Executive role specifically, bullets 2 and 3
  map most directly to the job description's language ("turning analysis
  into business actions", "benchmarking").
- Don't combine all three into one bullet — pick the angle that's least
  duplicated elsewhere on your CV (e.g. if another bullet already covers
  your SQL/Python data-pipeline work from Parexel, lead with 2 or 3 here
  instead of 1).
