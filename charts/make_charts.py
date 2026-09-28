"""
Static charts for the README, made from the data files in powerbi_data/.

Run from the repo root:
    python charts/make_charts.py

Needs pandas and matplotlib. Writes a light and a dark version of each chart
into charts/, so the README can show the right one for GitHub's theme.
Every number drawn here matches the "Result" comments in sql/04_analysis.sql.
"""
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.patches import PathPatch
from matplotlib.path import Path as MPath

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "powerbi_data"
OUT = ROOT / "charts"

DPI = 200
# The images are about 2000px wide and GitHub shows them at roughly 880px, so
# a mark meant to look N px wide on screen is drawn N / 0.44 px in the file.
SCALE = 0.44
def pt(display_px):
    """Display pixels -> matplotlib points at this DPI and scale."""
    return display_px / SCALE * 72 / DPI

THEMES = {
    "light": dict(surface="#fcfcfb", ink="#0b0b0b", ink2="#52514e", muted="#898781",
                  grid="#e1e0d9", axis="#c3c2b7", accent="#2a78d6", accent2="#eb6834",
                  context="#898781"),
    "dark":  dict(surface="#1a1a19", ink="#ffffff", ink2="#c3c2b7", muted="#898781",
                  grid="#2c2c2a", axis="#383835", accent="#3987e5", accent2="#d95926",
                  context="#898781"),
}

def half_up(x, places=1):
    """Round the way PostgreSQL's ROUND() does (2.85 -> 2.9), not banker's rounding."""
    q = Decimal(1).scaleb(-places)
    return float(Decimal(str(x)).quantize(q, rounding=ROUND_HALF_UP))


# ---------------------------------------------------------------- data
f = pd.read_csv(DATA / "fact_orders.csv", dtype={"is_late": "string"},
                parse_dates=["order_date", "delivered_date"])
fulfilled = f[~f["order_status"].isin(["canceled", "unavailable"])]
monthly_gmv = fulfilled.groupby(fulfilled["order_date"].dt.to_period("M"))["gmv"].sum()

reviewed = f[f["is_late"].notna() & f["review_score"].notna()]
late_mask = reviewed["is_late"] == "true"
review_groups = {
    "On-time or early": reviewed[~late_mask],
    "Late": reviewed[late_mask],
}

delivered = f[f["is_late"].notna()].copy()
delivered["days"] = (delivered["delivered_date"] - delivered["order_date"]).dt.days
delivered["late"] = delivered["is_late"] == "true"
states = delivered.groupby("customer_state").agg(days=("days", "mean"), late=("late", "mean"),
                                                 orders=("days", "size"))
states["late"] *= 100
national_days = delivered["days"].mean()
national_late = delivered["late"].mean() * 100

tiers = pd.read_csv(DATA / "seller_tier_comparison.csv").set_index("seller_group")
top = tiers.loc["Top 10% of sellers by GMV"]
rest = tiers.loc["Remaining 90%"]


# ---------------------------------------------------------------- helpers
def new_figure(t, height):
    fig = plt.figure(figsize=(10, height), dpi=DPI, facecolor=t["surface"])
    return fig

def title_block(fig, t, title, subtitle):
    fig.text(0.04, 0.95, title, color=t["ink"], fontsize=16, fontweight="semibold",
             ha="left", va="top")
    fig.text(0.04, 0.95 - 0.36 / fig.get_figheight(), subtitle, color=t["ink2"],
             fontsize=11, ha="left", va="top")

def style_axes(ax, t, grid_axis="y"):
    ax.set_facecolor(t["surface"])
    for side in ("top", "right", "left", "bottom"):
        ax.spines[side].set_visible(False)
    ax.tick_params(colors=t["muted"], labelsize=10.5, length=0)
    if grid_axis:
        ax.grid(axis=grid_axis, color=t["grid"], linewidth=pt(1), linestyle="-")
    ax.set_axisbelow(True)

def hbar(ax, y, width, height, color, x0=0.0, round_end=True):
    """Horizontal bar: square at the baseline, 4px rounded data end.
    Drawn as one path (no overlapping patches), so there's no seam."""
    bbox = ax.get_window_extent()
    x_lo, x_hi = ax.get_xlim()
    y_lo, y_hi = ax.get_ylim()
    px_x = bbox.width / (x_hi - x_lo)
    px_y = bbox.height / abs(y_hi - y_lo)
    r_px = 4 / SCALE
    rx, ry = r_px / px_x, r_px / px_y
    x1, yb, yt = x0 + width, y - height / 2, y + height / 2
    M, L, C, Z = MPath.MOVETO, MPath.LINETO, MPath.CURVE4, MPath.CLOSEPOLY
    if round_end and width > rx and height > 2 * ry:
        k = 0.5523  # cubic Bezier approximation of a quarter ellipse
        verts = [(x0, yb), (x1 - rx, yb),
                 (x1 - rx + k * rx, yb), (x1, yb + ry - k * ry), (x1, yb + ry),
                 (x1, yt - ry),
                 (x1, yt - ry + k * ry), (x1 - rx + k * rx, yt), (x1 - rx, yt),
                 (x0, yt), (x0, yb)]
        codes = [M, L, C, C, C, L, C, C, C, L, Z]
    else:
        verts = [(x0, yb), (x1, yb), (x1, yt), (x0, yt), (x0, yb)]
        codes = [M, L, L, L, Z]
    ax.add_patch(PathPatch(MPath(verts, codes), fc=color, ec="none", zorder=3))

def save(fig, name, mode):
    path = OUT / f"{name}_{mode}.png"
    fig.savefig(path, dpi=DPI, facecolor=fig.get_facecolor())
    plt.close(fig)
    print("wrote", path.relative_to(ROOT))

def money(x):
    return f"R${x / 1e6:.2f}M" if x >= 1e6 else f"R${x / 1e3:.0f}k"


# ---------------------------------------------------------------- 1. GMV by month
def chart_gmv(t, mode):
    fig = new_figure(t, 5.2)
    title_block(fig, t, "Monthly GMV grew fast, then levelled off",
                "Fulfilled orders, Jan 2017 – Aug 2018. GMV = item price + freight, in Brazilian reais (R$).")
    ax = fig.add_axes([0.09, 0.13, 0.86, 0.69])
    style_axes(ax, t)
    x = list(range(len(monthly_gmv)))
    y = monthly_gmv.values
    ax.fill_between(x, y, color=t["accent"], alpha=0.10, linewidth=0, zorder=2)
    ax.plot(x, y, color=t["accent"], linewidth=pt(2), solid_joinstyle="round",
            solid_capstyle="round", zorder=3)
    ax.plot(x[-1], y[-1], "o", color=t["accent"], markersize=pt(9),
            markeredgecolor=t["surface"], markeredgewidth=pt(2), zorder=4)
    ax.set_xlim(-0.9, len(x) - 0.4)
    ax.set_ylim(0, 1_300_000)
    ax.tick_params(axis="x", pad=8)
    ax.tick_params(axis="y", pad=6)
    ax.set_yticks([0, 250_000, 500_000, 750_000, 1_000_000, 1_250_000])
    ax.set_yticklabels(["R$0", "R$250k", "R$500k", "R$750k", "R$1.0M", "R$1.25M"])
    ticks = [i for i, p in enumerate(monthly_gmv.index) if p.month in (1, 4, 7, 10)]
    ax.set_xticks(ticks)
    ax.set_xticklabels([monthly_gmv.index[i].strftime("%b %Y") for i in ticks])
    ax.axhline(0, color=t["axis"], linewidth=pt(1), zorder=2)
    peak = int(monthly_gmv.values.argmax())
    ax.annotate(f"Black Friday peak\n{money(y[peak])} (Nov 2017)", (peak, y[peak]),
                xytext=(-10, 0), textcoords="offset points", ha="right", va="center",
                fontsize=10.5, color=t["ink2"])
    ax.annotate(money(y[0]), (0, y[0]), xytext=(9, -4), textcoords="offset points",
                ha="left", va="top", fontsize=10.5, color=t["ink2"])
    ax.annotate(money(y[-1]), (x[-1], y[-1]), xytext=(0, 12), textcoords="offset points",
                ha="center", va="bottom", fontsize=10.5, color=t["ink2"])
    save(fig, "01_gmv_by_month", mode)


# ---------------------------------------------------------------- 2. reviews, late vs on-time
def chart_reviews(t, mode):
    fig = new_figure(t, 4.2)
    title_block(fig, t, "Late deliveries go with much worse reviews",
                f"{len(reviewed):,} delivered, reviewed orders, Jan 2017 – Aug 2018. "
                "Late = delivered after the estimated date.")
    labels = list(review_groups)
    colors = [t["context"], t["accent"]]
    panels = [
        ("Average review score (out of 5)", [g["review_score"].mean() for g in review_groups.values()],
         5.0, lambda v: f"{half_up(v, 2):.2f}", [0, 1, 2, 3, 4, 5], lambda v: f"{v:g}"),
        ("Share of orders scoring 1–2 stars",
         [100 * (g["review_score"] <= 2).mean() for g in review_groups.values()],
         70.0, lambda v: f"{half_up(v, 1):.1f}%", [0, 20, 40, 60], lambda v: f"{v:g}%"),
    ]
    for i, (name, values, xmax, fmt, xticks, tickfmt) in enumerate(panels):
        ax = fig.add_axes([0.20 + i * 0.41, 0.15, 0.33, 0.54])
        style_axes(ax, t, grid_axis="x")
        ax.set_xlim(0, xmax)
        ax.set_ylim(-0.6, 1.6)
        ax.set_xticks(xticks)
        ax.set_xticklabels([tickfmt(v) for v in xticks])
        ax.set_yticks([0, 1])
        ax.set_yticklabels(labels if i == 0 else ["", ""], fontsize=11, color=t["ink2"])
        ax.set_title(name, loc="left", fontsize=11.5, color=t["ink"], pad=10)
        ax.axvline(0, color=t["axis"], linewidth=pt(1), zorder=2)
        for row, (v, c) in enumerate(zip(values, colors)):
            hbar(ax, row, v, 0.28, c)
            ax.text(v + xmax * 0.02, row, fmt(v), va="center", ha="left",
                    fontsize=11, color=t["ink"], fontweight="semibold")
    save(fig, "02_reviews_late_vs_on_time", mode)


# ---------------------------------------------------------------- 3. states: slow vs late
def chart_states(t, mode):
    fig = new_figure(t, 6.0)
    title_block(fig, t, "Slow isn't the same as late",
                "One dot per customer state (Brazilian state codes, e.g. RJ = Rio de Janeiro). "
                "Delivered orders, Jan 2017 – Aug 2018.")
    ax = fig.add_axes([0.09, 0.12, 0.86, 0.62])
    style_axes(ax, t, grid_axis="both")
    slow = states.sort_values("days", ascending=False).head(3).index.tolist()
    hot = states.sort_values("late", ascending=False)
    hot = [s for s in hot.index if s not in slow][:3]
    ax.axvline(national_days, color=t["axis"], linewidth=pt(1.5), zorder=2)
    ax.axhline(national_late, color=t["axis"], linewidth=pt(1.5), zorder=2)
    ax.text(national_days + 0.3, 23.2, f"national average\n{half_up(national_days)} days",
            fontsize=9.5, color=t["muted"], va="top")
    ax.text(31.8, national_late + 0.4, f"national late rate {half_up(national_late)}%",
            fontsize=9.5, color=t["muted"], ha="right", va="bottom")
    groups = [
        (slow, t["accent"], "3 slowest states"),
        (hot, t["accent2"], "3 highest late rates"),
        ([s for s in states.index if s not in slow + hot], t["context"], "Other states"),
    ]
    for members, color, label in groups:
        d = states.loc[members]
        ax.scatter(d["days"], d["late"], s=pt(10) ** 2, color=color, edgecolors=t["surface"],
                   linewidths=pt(2), zorder=4, label=label)
    # Label to the right of the dot, except where a neighbour sits there.
    left_of_dot = {"AM"}
    for s in slow + hot + ["RJ", "SP"]:
        dx, ha = (-7, "right") if s in left_of_dot else (7, "left")
        ax.annotate(s, (states.loc[s, "days"], states.loc[s, "late"]), xytext=(dx, 0),
                    textcoords="offset points", va="center", ha=ha, fontsize=10.5,
                    color=t["ink"], fontweight="semibold")
    rj = states.loc["RJ"]
    rj_share = 100 * delivered.loc[delivered["customer_state"] == "RJ", "late"].sum() / delivered["late"].sum()
    ax.annotate(f"RJ: {half_up(rj['late'])}% late on {int(rj['orders']):,} orders —\n"
                f"{half_up(rj_share)}% of all late orders",
                (rj["days"], rj["late"]), xytext=(-12, 34), textcoords="offset points",
                ha="right", va="bottom", fontsize=9.5, color=t["ink2"],
                arrowprops=dict(arrowstyle="-", color=t["muted"], linewidth=pt(1)))
    ax.set_xlim(6, 32)
    ax.set_ylim(0, 24)
    ax.set_xlabel("Average delivery time (days from order to delivery)", color=t["ink2"], fontsize=10.5)
    ax.set_ylabel("Delivered late (% of orders)", color=t["ink2"], fontsize=10.5)
    ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{v:g}%"))
    ax.legend(loc="lower left", bbox_to_anchor=(0, 1.01), ncol=3, frameon=False, fontsize=10.5,
              labelcolor=t["ink2"], handletextpad=0.3, columnspacing=1.6, borderaxespad=0)
    save(fig, "03_state_delivery_vs_late", mode)


# ---------------------------------------------------------------- 4. top sellers vs rest
def chart_sellers(t, mode):
    fig = new_figure(t, 4.2)
    title_block(fig, t, "Top 10% of sellers: two-thirds of GMV, no better at delivering",
                f"Sellers ranked by GMV: top 10% ({int(top['num_sellers'])} sellers) vs the other "
                f"{int(rest['num_sellers']):,}. Fulfilled orders, Jan 2017 – Aug 2018.")
    # Left: share of GMV as one part-to-whole bar
    ax = fig.add_axes([0.04, 0.15, 0.42, 0.50])
    style_axes(ax, t, grid_axis=None)
    ax.set_xlim(0, 100)
    ax.set_ylim(-0.6, 0.6)
    ax.set_yticks([])
    ax.set_xticks([])
    ax.set_title("Share of GMV", loc="left", fontsize=11.5, color=t["ink"], pad=10)
    gap = 100 * (2 / SCALE) / ax.get_window_extent().width
    top_share, rest_share = float(top["pct_of_gmv"]), float(rest["pct_of_gmv"])
    hbar(ax, 0, top_share - gap / 2, 0.32, t["accent"], round_end=False)
    hbar(ax, 0, rest_share - gap / 2, 0.32, t["context"], x0=top_share + gap / 2)
    # Labels sit above each segment (in text ink), rather than squeezed inside it.
    for x_start, name, share in [(0, "Top 10%", top_share),
                                 (top_share + gap / 2, "Other 90%", rest_share)]:
        ax.text(x_start, 0.24, f"{share:.1f}%", ha="left", va="bottom", fontsize=11,
                color=t["ink"], fontweight="semibold")
        ax.text(x_start, 0.24 + 0.2, name, ha="left", va="bottom", fontsize=10.5,
                color=t["ink2"])
    # Right: late rate, one bar per group
    ax2 = fig.add_axes([0.62, 0.15, 0.34, 0.50])
    style_axes(ax2, t, grid_axis="x")
    ax2.set_xlim(0, 10)
    ax2.set_ylim(-0.6, 1.6)
    ax2.set_xticks([0, 2, 4, 6, 8, 10])
    ax2.set_xticklabels([f"{v}%" for v in [0, 2, 4, 6, 8, 10]])
    ax2.set_yticks([0, 1])
    ax2.set_yticklabels(["Other 90%", "Top 10%"], fontsize=11, color=t["ink2"])
    ax2.set_title("Orders delivered late", loc="left", fontsize=11.5, color=t["ink"], pad=10)
    ax2.axvline(0, color=t["axis"], linewidth=pt(1), zorder=2)
    for row, (v, c) in enumerate([(float(rest["late_rate_pct"]), t["context"]),
                                  (float(top["late_rate_pct"]), t["accent"])]):
        hbar(ax2, row, v, 0.28, c)
        ax2.text(v + 0.2, row, f"{v:.1f}%", va="center", ha="left", fontsize=11,
                 color=t["ink"], fontweight="semibold")
    save(fig, "04_top_sellers_vs_rest", mode)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    for mode, theme in THEMES.items():
        chart_gmv(theme, mode)
        chart_reviews(theme, mode)
        chart_states(theme, mode)
        chart_sellers(theme, mode)
