"""Builds the README charts from the saved query results (/results). Run from repo root."""
import pandas as pd, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt, numpy as np
R, I = "results/", "images/"
plt.rcParams.update({"font.size": 10, "axes.spines.top": False, "axes.spines.right": False, "figure.dpi": 130})
BLUE, ORANGE, GREY, RED = "#2F5D8A", "#E07B39", "#9AA5B1", "#C0392B"

# 1 -- monthly revenue + rolling 3m ------------------------------------------------------------
d = pd.read_csv(R+"Q30a.csv", parse_dates=["order_month"])
fig, ax = plt.subplots(figsize=(10, 4.2))
colors = [ORANGE if m in (10, 11, 12) else BLUE for m in d.order_month.dt.month]
ax.bar(d.order_month, d.net_revenue/1e3, width=24, color=colors)
ax2 = ax.twinx(); ax2.plot(d.order_month, d.rolling_3m_revenue/1e3, color="black", lw=1.6, label="Rolling 3-month revenue (right axis)")
ax2.spines["top"].set_visible(False)
ax.set_ylabel("Net revenue per month (thousands)"); ax2.set_ylabel("Rolling 3-month (thousands)")
ax.set_title("Net revenue: a festive Oct-Dec peak every year, but no underlying growth", loc="left", fontweight="bold")
ax2.legend(loc="upper center", bbox_to_anchor=(0.5, -0.12), frameon=False, ncol=1)
fig.text(0.01, -0.14, "Orange = Oct-Dec. Net revenue = item revenue of Delivered/Shipped/Processing orders minus refunds (excl. shipping).", fontsize=8, color="#555")
fig.tight_layout(); fig.savefig(I+"01_monthly_revenue.png", bbox_inches="tight"); plt.close()

# 2 -- payment reconciliation -------------------------------------------------------------------
q = pd.read_csv(R+"Q04a.csv").set_index("order_status").loc[["Delivered", "Shipped", "Processing", "Returned", "Cancelled"]]
fig, ax = plt.subplots(figsize=(8.5, 3.8))
left = np.zeros(len(q))
for col, c, lab in [("fully_paid", BLUE, "Fully paid"), ("partially_paid", ORANGE, "Partially paid (split payment, one leg failed)"), ("no_successful_payment", RED, "No successful payment")]:
    pct = 100*q[col]/q.orders; ax.barh(q.index, pct, left=left, color=c, label=lab)
    for i, (v, l) in enumerate(zip(pct, left)):
        if v > 4: ax.text(l+v/2, i, f"{v:.1f}%", ha="center", va="center", color="white", fontsize=8)
    left += pct
ax.invert_yaxis(); ax.set_xlim(0, 100); ax.set_xlabel("% of orders")
ax.set_title("Payment reconciliation: ~1 in 7 orders has no successful payment", loc="left", fontweight="bold")
ax.legend(loc="upper center", bbox_to_anchor=(0.45, -0.18), ncol=3, frameon=False, fontsize=8)
fig.tight_layout(); fig.savefig(I+"02_payment_reconciliation.png", bbox_inches="tight"); plt.close()

# 3 -- RFM segments: customers vs revenue --------------------------------------------------------
r = pd.read_csv(R+"Q19a.csv").sort_values("pct_of_revenue", ascending=True)
fig, ax = plt.subplots(figsize=(8.5, 4))
y = np.arange(len(r)); ax.barh(y+0.2, r.pct_of_customers, 0.4, color=GREY, label="% of customers")
ax.barh(y-0.2, r.pct_of_revenue, 0.4, color=BLUE, label="% of revenue")
ax.set_yticks(y); ax.set_yticklabels(r.rfm_segment); ax.set_xlabel("%")
ax.set_title("RFM: Champions are 17% of customers but 31% of revenue", loc="left", fontweight="bold"); ax.legend(frameon=False)
fig.tight_layout(); fig.savefig(I+"03_rfm_segments.png", bbox_inches="tight"); plt.close()

# 4 -- cohort retention heatmap -----------------------------------------------------------------
c = pd.read_csv(R+"Q30c.csv"); piv = c[c.months_since_first.between(1, 12)].pivot(index="cohort_month", columns="months_since_first", values="retention_pct")
# keep only observable cells
last = pd.Timestamp("2026-09-01")
for cm in piv.index:
    for m in piv.columns:
        if pd.Timestamp(cm) + pd.DateOffset(months=int(m)) > last: piv.loc[cm, m] = np.nan
fig, ax = plt.subplots(figsize=(8.5, 7))
im = ax.imshow(piv.values, cmap="Blues", vmin=0, vmax=20, aspect="auto")
ax.set_xticks(range(piv.shape[1])); ax.set_xticklabels(piv.columns); ax.set_yticks(range(len(piv))); ax.set_yticklabels([x[:7] for x in piv.index], fontsize=7)
ax.set_xlabel("Months since first purchase"); ax.set_ylabel("First-purchase cohort")
ax.set_title("Cohort retention (% buying in month N): flat ~8-12%, no decay curve", loc="left", fontweight="bold", fontsize=10)
plt.colorbar(im, label="% of cohort active"); fig.tight_layout(); fig.savefig(I+"04_cohort_retention.png", bbox_inches="tight"); plt.close()

# 5 -- conversion by traffic source (flat) -------------------------------------------------------
t = pd.read_csv(R+"Q23a.csv").sort_values("conversion_rate_pct")
fig, ax = plt.subplots(figsize=(8.5, 3.6))
ax.barh(t.traffic_source, t.conversion_rate_pct, color=BLUE); ax.axvline(13.02, color="black", ls="--", lw=1); ax.text(13.03, -0.45, "avg 13.02%", fontsize=8)
ax.set_xlim(0, 16); ax.set_xlabel("Session conversion rate (%)")
for i, v in enumerate(t.conversion_rate_pct): ax.text(v+0.1, i, f"{v:.2f}%", va="center", fontsize=8)
ax.set_title("Conversion is statistically flat across traffic sources (12.9%-13.3%)", loc="left", fontweight="bold")
fig.tight_layout(); fig.savefig(I+"05_conversion_by_source.png", bbox_inches="tight"); plt.close()
print("charts done")
