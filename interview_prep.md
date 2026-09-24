# Interview Prep — Likely Questions About This Project

Five questions you should be ready for if this project comes up in a
Shopee BI interview, with the points worth hitting in each answer — not
scripted answers, since those come across as rehearsed. The numbers come
from the SQL in this repo run on the Kaggle data; know where each one
comes from, because a good interviewer will ask.

## 1. "Walk me through this project."

- Lead with the *business* framing before the technical one: you wanted
  a portfolio piece that demonstrated marketplace-analyst skills
  specifically (not just "a SQL project") because you're coming from
  clinical data analysis with no e-commerce background — name that gap
  directly, don't dance around it.
- Structure: picked a real multi-seller marketplace dataset (Olist, 99,441
  orders) → defined 5 business questions upfront → checked data quality
  before trusting anything → PostgreSQL for prep/analysis → Power BI for
  the dashboard.
- Close with the headline finding in one sentence: late deliveries went
  with reviews about 2 stars lower — 2.27 vs 4.29 — and 62.3% of late
  orders scored 1–2 stars.

## 2. "How did you handle data granularity / avoid double-counting?"

This is very likely given how explicitly the job description mentions
granularity — treat it as a chance to show, not just claim, the skill.

- Name the grain mismatches with real numbers: `order_items` is
  item-level (9,803 orders have 2+ items), `order_payments` splits across
  rows (2,961 orders have 2+ payment rows), `order_reviews` has 0 or 2–3
  rows for some orders (768 and 547), and 789 `review_id`s are reused.
- Explain the fix: aggregate each child table to one row per order
  *first*, in a CTE, before joining anything — that's what
  `sql/03_fact_orders.sql` does, and why GMV comes from `order_items`
  (price + freight) rather than summing payments.
- Show you *verified* it rather than assumed it: the fact view has exactly
  99,441 rows, one per order, and its GMV matches the raw item table to
  the cent (R$15,843,553.24).
- Then tell the story of the bug you caught in your own work — this is
  the strongest part of the answer. Your first seller query measured late
  rate per *item* row, so a seller with three items in one late order was
  counted late three times. Running on real data showed it changed the
  late rate of 821 of 3,029 sellers, by up to 38 percentage points. The
  fix: collapse items to one row per seller per order before measuring.
  It shows you check your own output, which matters more than never
  making mistakes.

## 3. "Your background is Tableau — why build this in Power BI?"

Your CV shows strong, specific Tableau experience (including XML-level
debugging), so expect this to come up as a mismatch worth explaining.

- Be direct: you already have Tableau depth; building in Power BI here
  was a deliberate choice to broaden tool range for a market/role where
  Power BI is common, not a sign you don't know Tableau.
- Have one honest, specific observation ready about where the tools
  differ — ideally something you actually hit while building. For
  example: DAX's `AVERAGE` only accepts a column, so an average of a
  calculated value (like delivery days) needs `AVERAGEX`; or month names
  sort alphabetically until you set "Sort by column". A generic "they're
  both fine" undersells that you built something end-to-end in a second
  tool.
- If asked which you'd choose for a real Shopee project: answer based on
  what the team actually uses, not a personal preference — this is a
  question about adaptability, not brand loyalty.

## 4. "What's the business takeaway, and what would you actually recommend?"

This is the "turning analysis into business action" skill from the job
description — the question most likely to separate a strong answer from
a purely technical one.

- State the finding in plain numbers first: 6.8% of delivered orders
  arrived late, and late orders averaged 2.27 stars vs 4.29 for on-time
  ones.
- Then the insight most people miss: slow isn't the same as late. The
  remote north has the longest deliveries (Roraima 29.9 days vs 12.5
  nationally) but hardly any late ones, because its estimates are
  realistic. Lateness concentrates in Alagoas (21.5%), Maranhão (17.5%)
  and Sergipe (15.4%), and by volume in Rio de Janeiro (22.9% of all late
  orders). So the fix is missed promises in specific places.
- Recommendations stated as actions, not restated findings: review
  estimates and carriers in those states first; put late rate into
  top-seller account management, since the top 10% of sellers carry 66.5%
  of GMV and are no better on delivery (6.9% vs 6.4% late); and warn
  customers before a late delivery, tested as an A/B experiment.
- Tie in retention: only 3.0% of customers ever ordered twice, so for
  most customers the first delivery is the whole relationship.

## 5. "What are the limitations, and what would you do differently with more time or real production data?"

Answering this well signals the same rigor your clinical-data background
should give you — don't skip it or undersell the project by being vague.

- The review gap is an association, not proof of cause. You already
  checked the obvious confounder — the gap holds within each of 21 states
  (1.63 to 2.62 stars), so it isn't about where customers live — but
  product type or seller could still play a part. The clean way to prove
  cause is the A/B test in your recommendations.
- Attribution: Olist records delivery and reviews per order, not per
  seller, so a late multi-seller order (1,278 of them) counts as late for
  every seller in it.
- Small samples: Roraima has only 40 delivered orders, so its "slowest
  state" ranking is less reliable than São Paulo's (40,399).
- On production readiness: this was a one-off CSV import; a live version
  would need scheduled refresh, monitoring for schema drift in the source
  data, and proper access controls — worth naming even briefly to show
  you're thinking beyond "the numbers came out right once."
