# Marketplace Performance & Seller Health — Insight Summary

*Every figure below comes from the SQL in this repo, run on the Kaggle Olist
dataset for January 2017 – August 2018. Each one appears in the "Result"
comment under its query in `sql/04_analysis.sql`, or in the findings block at
the top of `sql/02_data_quality_checks.sql`.*

## Context

Olist is a Brazilian multi-seller marketplace. This analysis covers 99,092
orders placed between January 2017 and August 2018, the window with reliable
volume. The months on either side have between 0 and 324 orders each, too
few to trend (see `sql/02_data_quality_checks.sql`, section H). Over the
window, fulfilled orders generated R$15,683,706.74 in GMV (item price plus
freight). Monthly GMV grew from R$136,943.46 in January 2017 to a peak of
R$1,172,191.68 in November 2017, driven by Black Friday (24 November alone had
1,176 orders). It then levelled off at between R$979,486.16 and R$1,156,248.89 a
month through 2018, which is still 140.4% above the same eight months of 2017.

## Key Findings

**1. Late deliveries go with review scores about 2 stars lower.**
Of 95,561 delivered, reviewed orders, 6.7% arrived late. Late orders averaged
**2.27 stars vs 4.29** for on-time ones, a gap of 2.02 stars (95% confidence
interval: 1.98 to 2.06). **62.3%** of late orders scored 1–2 stars, against
9.2% of on-time orders. The gap also holds within each of the 21 states with
enough late orders to compare, at 1.63 to 2.62 stars, so it isn't explained by
where customers live.
*Why it matters:* delivery reliability is the clearest lever on review scores
in this data, and reviews are what the next buyer sees.

**2. Lateness is concentrated, and not where deliveries are slowest.**
The remote north has the longest deliveries: Roraima 29.9 days, Amapá 27.2 and
Amazonas 26.4, against 12.5 nationally. Yet Amapá and Amazonas are late only
3.0% and 2.8% of the time, because their delivery estimates are generous. The
late-rate hotspots are Alagoas (21.5%), Maranhão (17.5%) and Sergipe (15.4%),
against 6.8% nationally. By volume, Rio de Janeiro stands out: 12.1% late on
12,310 delivered orders, or 1,495 late orders, which is 22.9% of all late
orders.
*Why it matters:* customers judge a delivery against the date they were
promised. The problem to fix is missed estimates in specific states, not long
delivery times as such.

**3. Two-thirds of GMV comes from 10% of sellers, and they're no better at delivering.**
The top 10% of sellers by GMV (303 of 3,029) generated **66.5%** of GMV
(R$10,436,449.08). **6.9%** of their orders arrived late, against **6.4%** for
the other 2,726 sellers, and their average review was 4.08 against 4.13.
*Why it matters:* most customers buy from this small group, so a delivery
problem there reaches the most buyers. Working only on the long tail of small
sellers would miss most of the volume.

## Recommendations

1. **Fix the promise in the hotspot states first.** Review estimated delivery
   dates and carrier performance in Alagoas, Maranhão, Sergipe and Rio de
   Janeiro, where estimates are missed far more often than the 6.8% national
   rate. Where delivery can't be made faster, a more realistic estimate is a
   fix in itself: the north shows that a long delivery promised accurately
   rarely counts as late.
2. **Build delivery performance into top-seller account management.** Track
   the late rate of the top 303 sellers every month and flag any above the
   national rate. The largest seller by GMV, for example, runs at 10.5% late.
   Because this group carries 66.5% of GMV, small improvements here move the
   whole marketplace.
3. **Protect the first order, because there usually isn't a second.** Only
   3.0% of customers (2,875 of 94,707) ever ordered twice. Warn customers
   before an order misses its estimate instead of waiting for the 1–2 star
   review. Run it as an A/B test: send the warning on half of the at-risk
   orders and compare review scores against the other half. That is also how
   you'd confirm that lateness *causes* the lower scores (see Limitations).

## Limitations

- This is public data from one marketplace in one country, from 2017–2018.
  It describes patterns in this data, not e-commerce in general.
- The review gap is an association, not proof of cause. It survives
  comparing late and on-time orders within the same state, but other factors,
  such as product type or seller, could still play a part. The A/B test in
  Recommendation 3 is how to settle it.
- Olist records delivery status and reviews per order, not per seller. A late
  order with items from several sellers (1,278 such orders) counts as late for
  each of them.
- "Late" means delivered after the estimated date. It says nothing about how
  that estimate was set.
- Repeat purchase is measured only inside the window, so a customer whose two
  orders fall either side of its edges counts as one-time.
- Some states have small samples: Roraima has only 40 delivered orders and
  Amapá 67, so treat their rankings with caution.
