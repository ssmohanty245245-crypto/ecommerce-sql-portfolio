"""Independent validation: recompute headline KPIs with pandas straight from the raw CSVs
(NOT from the SQL views) and compare with the SQL query outputs saved in /results.
Run from the repo root:  python scripts/validate_with_pandas.py"""
import pandas as pd, numpy as np
D, R = "data/", "results/"
o  = pd.read_csv(D+"orders.csv");  oi = pd.read_csv(D+"order_items.csv")
pay = pd.read_csv(D+"payments.csv"); ret = pd.read_csv(D+"returns.csv"); s = pd.read_csv(D+"website_sessions.csv")

rev_orders = o[o.order_status.isin(["Delivered", "Shipped", "Processing"])]
rev  = oi[oi.order_id.isin(rev_orders.order_id)].line_revenue.sum()            # uses the RAW stored line_revenue
refunds = ret[ret.order_id.isin(rev_orders.order_id)].refund_amount.sum()
cash = pay[pay.payment_status == "Successful"].payment_amount.sum()
per_cust = rev_orders.groupby("customer_id").size()

checks = []
def add(name, pandas_val, sql_val, tol=0.01):
    checks.append((name, round(float(pandas_val), 2), round(float(sql_val), 2), abs(float(pandas_val) - float(sql_val)) <= tol))

q06 = pd.read_csv(R+"Q06.csv"); q10 = pd.read_csv(R+"Q10.csv"); q11 = pd.read_csv(R+"Q11a.csv"); q11b = pd.read_csv(R+"Q11b.csv")
add("Net item revenue: Q06 monthly total", rev, q06.net_item_revenue.sum())
add("Net item revenue: Q10 category total", rev, q10.net_item_revenue.sum())
add("Net item revenue: Q11a channel total", rev, q11.net_item_revenue.sum())
add("Net item revenue: Q11b state total",   rev, q11b.net_item_revenue.sum())
add("Refunds on revenue orders: Q06 total", refunds, q06.refunds.sum(), 0.05)
q04 = pd.read_csv(R+"Q04b.csv")
add("Successful cash collected: Q04b", cash, q04.successful_payment_value.sum())
add("Orders booked: Q06 total", len(o), q06.orders_booked.sum(), 0)
q18 = pd.read_csv(R+"Q18a.csv")
add("Purchasing customers: Q18a", per_cust.size, q18.purchasing_customers[0], 0)
add("Repeat purchase rate %: Q18a", 100*(per_cust >= 2).mean(), q18.repeat_purchase_rate_pct[0], 0.06)
q19 = pd.read_csv(R+"Q19a.csv")
add("RFM segments sum to purchasing customers: Q19a", per_cust.size, q19.customers.sum(), 0)
add("Session conversion rate %: Q23a", 100*(s.converted == "Yes").mean(), 100*(pd.read_csv(R+"Q23a.csv").conversions.sum())/len(s), 0.01)
q01 = pd.read_csv(R+"Q01a.csv").set_index("table_name").row_count
add("Row count orders", len(o), q01["orders"], 0); add("Row count order_items", len(oi), q01["order_items"], 0)
q30 = pd.read_csv(R+"Q30b.csv")
first = rev_orders.assign(m=rev_orders.order_date.str[:7]).groupby("customer_id").m.min()
add("Jan-2024 cohort size: Q30b", (first == "2024-01").sum(), q30.cohort_size.iloc[0], 0)
q22 = pd.read_csv(R+"Q22a.csv")
add("Customers in category-breadth table: Q22a", per_cust.size, q22.customers.sum(), 0)

out = pd.DataFrame(checks, columns=["check", "pandas_value", "sql_value", "match"])
out.to_csv(R+"validation_checks.csv", index=False)
print(out.to_string(index=False)); print("\nALL CHECKS PASSED" if out.match.all() else "\nSOME CHECKS FAILED")
