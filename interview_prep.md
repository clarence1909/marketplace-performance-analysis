# Interview Prep — Likely Questions About This Project

Five questions you should be ready for if this project comes up in a
Shopee BI interview, with the points worth hitting in each answer — not
scripted answers, since those come across as rehearsed. Fill in the
bracketed figures once you have real results.

## 1. "Walk me through this project."

- Lead with the *business* framing before the technical one: you wanted
  a portfolio piece that demonstrated marketplace-analyst skills
  specifically (not just "a SQL project") because you're coming from
  clinical data analysis with no e-commerce background — name that gap
  directly, don't dance around it.
- Structure: picked a real multi-seller marketplace dataset (Olist) →
  defined 5 business questions upfront → PostgreSQL for prep/analysis →
  Power BI for the dashboard.
- Close with the headline finding in one sentence: late deliveries were
  associated with a [X]-star lower average review ([Y] vs [Z]).

## 2. "How did you handle data granularity / avoid double-counting?"

This is very likely given how explicitly the job description mentions
granularity — treat it as a chance to show, not just claim, the skill.

- Name the three grain mismatches concretely: `order_items` is
  item-level, `order_payments` can have multiple rows per order (split
  payments), `order_reviews` occasionally has 0 or 2+ rows per order.
- Explain the fix: aggregate each child table to one row per order
  *first*, in a CTE, before joining anything — that's what
  `sql/03_fact_orders.sql` does, and why GMV is built from `order_items`
  (price + freight) instead of summing `payment_value`.
- Mention you *checked* this rather than assumed it —
  `sql/02_data_quality_checks.sql` section D quantifies exactly how many
  orders have >1 item/payment/review row before you decided how to
  aggregate.
- If pushed further: the same issue reappears for seller-level analysis
  (Q4) because one order can span multiple sellers — you deliberately
  went back to `order_items` for that question rather than reusing the
  order-level fact view, and can explain why in one sentence if asked.

## 3. "Your background is Tableau — why build this in Power BI?"

Your CV shows strong, specific Tableau experience (including XML-level
debugging), so expect this to come up as a mismatch worth explaining.

- Be direct: you already have Tableau depth; building in Power BI here
  was a deliberate choice to broaden tool range for a market/role where
  Power BI is common, not a sign you don't know Tableau.
- Have one honest, specific observation ready about where the tools
  differ (e.g., something about DAX vs. Tableau's calculation model, or
  the PostgreSQL connector experience) — a generic "they're both fine"
  answer undersells that you actually built something end-to-end in a
  second tool.
- If asked which you'd choose for a real Shopee project: answer based on
  what the team actually uses, not a personal preference — this is a
  question about adaptability, not brand loyalty.

## 4. "What's the business takeaway, and what would you actually recommend?"

This is the "turning analysis into business action" skill from the job
description — the question most likely to separate a strong answer from
a purely technical one.

- State the finding in plain numbers first: [X]% of orders were late;
  late orders averaged [Y] stars vs [Z] for on-time ones.
- Then the recommendation, stated as an action, not a restatement of the
  finding: e.g. flag sellers whose late rate crosses a threshold for
  review, rather than "we should reduce late deliveries" (true, but not
  actionable on its own).
- If you found the seller-concentration result (Q4): connect it — a
  small group of sellers driving most GMV means delivery-reliability
  investment targeted at that group has outsized impact on overall
  marketplace experience, which is a more efficient recommendation than
  a blanket policy.

## 5. "What are the limitations, and what would you do differently with more time or real production data?"

Answering this well signals the same rigor your clinical-data background
should give you — don't skip it or undersell the project by being vague.

- Name the real limitations you already documented rather than inventing
  new ones on the spot: review score and lateness are tracked at the
  order level, not per seller, so a multi-seller order's late flag gets
  attributed to every seller who shipped an item in it — a simplification,
  not a hidden flaw.
- On statistical rigor: the late-vs-review comparison (Q1) is a group
  average difference: with more time you'd want to check it's not driven
  by a handful of outlier categories or sellers, and could add a formal
  significance test rather than relying on the raw gap alone.
- On production readiness: this was a one-off CSV import; a live version
  would need incremental/scheduled refresh, monitoring for schema drift
  in source data, and proper access controls — worth naming even briefly
  to show you're thinking beyond "the numbers came out right once."
