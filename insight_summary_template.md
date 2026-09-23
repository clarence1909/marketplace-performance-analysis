# Marketplace Performance & Seller Health — Insight Summary

*Fill in every `[X]` by actually running `sql/04_analysis.sql` and reading
the dashboard — none of these numbers are filled in yet, on purpose. This
page is meant to be the one thing you hand someone (a recruiter, an
interviewer, your own future reference) who wants the 60-second version
without opening Power BI.*

## Context

This project analyzes [X] orders placed on Olist, a Brazilian
multi-seller marketplace, between January 2017 and August 2018 (the
window with reliable order volume — see `sql/02_data_quality_checks.sql`,
section H, for why the surrounding months were excluded). The goal was to
answer five marketplace-health questions a Business Intelligence Executive
would realistically be asked to look into: delivery performance and its
link to customer satisfaction, GMV trend, customer repeat rate, seller
concentration and health, and regional delivery gaps.

## Key Findings

**1. [Finding — e.g., "Late deliveries are associated with meaningfully
lower review scores"]**
Late orders averaged **[X] stars** vs **[Y] stars** for on-time/early
orders — a gap of **[Z] stars** (from Q1, `sql/04_analysis.sql`). [Why it
matters: e.g., delivery reliability isn't just an operations metric, it's
directly tied to the review scores that drive buyer trust and seller
ranking on the platform.]

**2. [Finding — e.g., "GMV grew steadily but not evenly across the
window"]**
GMV moved from **[X]** in [earliest month] to **[Y]** in [latest month],
peaking at **[Z]** in [peak month] (**+[N]% MoM** at its fastest — from
Q2). [Why it matters: e.g., identifies whether growth is broad-based or
concentrated in a few strong months worth investigating further.]

**3. [Finding — e.g., "A small share of sellers account for a
disproportionate share of GMV, with a real service-quality gap"]**
The top 10% of sellers by GMV generated **[X]%** of total GMV, with a late
rate of **[Y]%** vs **[Z]%** for the remaining 90%, and an average review
of **[A]** vs **[B]** (from Q4). [Why it matters: e.g., the marketplace's
overall customer experience is disproportionately exposed to how well this
small group of sellers performs.]

## Recommendations

1. **[Recommendation tied to Finding 1]** — e.g., flag sellers whose
   orders are late more than [X]% of the time for a delivery-time review,
   since late delivery is the clearest lever tied to review score in this
   data.
2. **[Recommendation tied to Finding 3]** — e.g., extend proactive seller
   support (courier options, packaging SLAs) specifically to the top-decile
   sellers, since their service quality has outsized weight on total
   marketplace GMV.
3. **[Optional third recommendation, e.g. tied to Q5's state-level gap]**
   — e.g., investigate fulfillment/logistics options for the [state]
   region specifically, where average delivery time was [X] days versus
   [Y] days nationally.

## Limitations

- This is public historical data (2017–2018) from a single marketplace in
  one country; findings describe patterns in *this* dataset and shouldn't
  be read as universal claims about e-commerce delivery or reviews.
- `review_score` reflects the customer's overall order experience, not
  seller performance specifically. For multi-seller orders, this project
  attributes the order's review score (and its late/on-time status) to
  every seller who shipped an item in that order — a simplification made
  necessary by the fact that Olist's data ties delivery status and
  reviews to the *order*, not to an individual seller within it (see the
  note above Q4 in `sql/04_analysis.sql`).
- "Late" is a binary flag based on the estimated delivery date; it doesn't
  capture *how* late, beyond the separate `days_vs_estimate` figure, and
  doesn't account for delivery estimates that may themselves have been set
  generously or tightly by category.
- Repeat-purchase rate (Q3) is measured only within the Jan 2017–Aug 2018
  window — a customer whose first and second orders straddle the window's
  edges would be undercounted.
