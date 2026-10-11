/* =====================================================================
   05_advanced_sql.sql   |   README questions 28-30
   Dialect: SQL Server.  Requires 00b_staging_views.sql.
   Techniques: DENSE_RANK, recursive calendar CTE, LAG, rolling window
   frames, cohort retention.
   ===================================================================== */
USE EcommerceAnalytics;
GO

-- [Q28] Top 3 products per category by net item revenue (DENSE_RANK within category)
WITH product_rev AS (
    SELECT category, product_id, product_name,
           SUM(quantity)                   AS units_sold,
           ROUND(SUM(net_line_revenue), 2) AS net_item_revenue
    FROM dbo.vw_item_outcomes
    WHERE is_revenue_order = 1 AND is_valid_line = 1
    GROUP BY category, product_id, product_name),
ranked AS (
    SELECT *, DENSE_RANK() OVER (PARTITION BY category ORDER BY net_item_revenue DESC) AS rank_in_category,
              SUM(net_item_revenue) OVER (PARTITION BY category)                        AS category_revenue
    FROM product_rev)
SELECT category, rank_in_category, product_id, product_name, units_sold, net_item_revenue,
       ROUND(100.0 * net_item_revenue / category_revenue, 2) AS pct_of_category_revenue
FROM ranked
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;

-- [Q29a] Calendar CTE: every month from the first order month to Dec-2026, so months with ZERO orders still appear
WITH /*REC*/ calendar AS (
    SELECT CAST('2024-01-01' AS DATE) AS month_start
    UNION ALL
    SELECT DATEADD(month, 1, month_start) FROM calendar WHERE month_start < '2026-12-01'),
monthly AS (
    SELECT order_month, COUNT(*) AS orders, SUM(recognised_revenue) AS revenue
    FROM dbo.vw_order_summary GROUP BY order_month),
bounds AS (SELECT MAX(order_month) AS last_data_month FROM dbo.vw_order_summary)
SELECT c.month_start,
       COALESCE(m.orders, 0)              AS orders,
       ROUND(COALESCE(m.revenue, 0), 2)   AS net_item_revenue,
       CASE WHEN m.orders IS NOT NULL      THEN 'Has orders'
            WHEN c.month_start > b.last_data_month THEN 'Beyond data coverage (not a real zero)'
            ELSE 'ZERO ORDERS - investigate' END AS status
FROM calendar c
CROSS JOIN bounds b
LEFT JOIN monthly m ON m.order_month = c.month_start
ORDER BY c.month_start
OPTION (MAXRECURSION 100);

-- [Q29b] Densified gap scan: month x sales channel x state cells with ZERO orders (smallest channel only)
WITH /*REC*/ calendar AS (
    SELECT CAST('2024-01-01' AS DATE) AS month_start
    UNION ALL
    SELECT DATEADD(month, 1, month_start) FROM calendar WHERE month_start < '2026-09-01'),
states AS (SELECT DISTINCT shipping_state FROM dbo.stg_orders WHERE shipping_state <> 'Unknown'),
grid AS (SELECT c.month_start, s.shipping_state FROM calendar c CROSS JOIN states s),
actual AS (
    SELECT order_month, shipping_state, COUNT(*) AS orders
    FROM dbo.vw_order_summary
    WHERE sales_channel = 'Retail Partner'
    GROUP BY order_month, shipping_state)
SELECT COUNT(*)                                                           AS month_state_cells,
       SUM(CASE WHEN a.orders IS NULL THEN 1 ELSE 0 END)                  AS cells_with_zero_retail_partner_orders,
       ROUND(100.0 * SUM(CASE WHEN a.orders IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_zero_cells,
       ROUND(AVG(1.0 * COALESCE(a.orders, 0)), 1)                         AS avg_orders_per_cell
FROM grid g
LEFT JOIN actual a ON a.order_month = g.month_start AND a.shipping_state = g.shipping_state
OPTION (MAXRECURSION 100);

-- [Q30a] Month-over-month revenue growth and rolling 3-month revenue
WITH monthly AS (
    SELECT order_month, SUM(net_revenue) AS net_revenue
    FROM dbo.vw_order_summary
    GROUP BY order_month),
calc AS (
    SELECT order_month, net_revenue,
           LAG(net_revenue) OVER (ORDER BY order_month)                                     AS prev_month_revenue,
           SUM(net_revenue) OVER (ORDER BY order_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_3m_revenue,
           COUNT(*)         OVER (ORDER BY order_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS months_in_window,
           LAG(net_revenue, 12) OVER (ORDER BY order_month)                                 AS same_month_last_year
    FROM monthly)
SELECT order_month,
       ROUND(net_revenue, 2)                                                      AS net_revenue,
       ROUND(100.0 * (net_revenue - prev_month_revenue) / prev_month_revenue, 1)  AS mom_growth_pct,
       CASE WHEN months_in_window = 3 THEN ROUND(rolling_3m_revenue, 2) END       AS rolling_3m_revenue,
       ROUND(100.0 * (net_revenue - same_month_last_year) / same_month_last_year, 1) AS yoy_growth_pct
FROM calc
ORDER BY order_month;

-- [Q30b] Customer cohort retention: % of each first-purchase cohort that bought again exactly N months later.
-- A cell is NULL when month N falls after the last month of data (not yet observable) - never a false 0%.
WITH purchases AS (
    SELECT DISTINCT customer_id, order_month
    FROM dbo.vw_order_summary
    WHERE is_revenue_order = 1),
cohorts AS (
    SELECT customer_id, MIN(order_month) AS cohort_month
    FROM purchases GROUP BY customer_id),
activity AS (
    SELECT c.cohort_month, p.customer_id,
           DATEDIFF(month, c.cohort_month, p.order_month) AS months_since_first
    FROM purchases p
    JOIN cohorts c ON c.customer_id = p.customer_id),
sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size, (SELECT MAX(order_month) FROM purchases) AS last_month
    FROM cohorts GROUP BY cohort_month)
SELECT a.cohort_month,
       s.cohort_size,
       CASE WHEN DATEADD(month, 1,  a.cohort_month) <= s.last_month THEN ROUND(100.0 * SUM(CASE WHEN a.months_since_first = 1  THEN 1 ELSE 0 END) / s.cohort_size, 1) END AS m1_pct,
       CASE WHEN DATEADD(month, 2,  a.cohort_month) <= s.last_month THEN ROUND(100.0 * SUM(CASE WHEN a.months_since_first = 2  THEN 1 ELSE 0 END) / s.cohort_size, 1) END AS m2_pct,
       CASE WHEN DATEADD(month, 3,  a.cohort_month) <= s.last_month THEN ROUND(100.0 * SUM(CASE WHEN a.months_since_first = 3  THEN 1 ELSE 0 END) / s.cohort_size, 1) END AS m3_pct,
       CASE WHEN DATEADD(month, 6,  a.cohort_month) <= s.last_month THEN ROUND(100.0 * SUM(CASE WHEN a.months_since_first = 6  THEN 1 ELSE 0 END) / s.cohort_size, 1) END AS m6_pct,
       CASE WHEN DATEADD(month, 12, a.cohort_month) <= s.last_month THEN ROUND(100.0 * SUM(CASE WHEN a.months_since_first = 12 THEN 1 ELSE 0 END) / s.cohort_size, 1) END AS m12_pct
FROM activity a
JOIN sizes s ON s.cohort_month = a.cohort_month
GROUP BY a.cohort_month, s.cohort_size, s.last_month
ORDER BY a.cohort_month;

-- [Q30c] Cohort retention, long format (feeds the heatmap chart): months 0-12 for every cohort
WITH purchases AS (
    SELECT DISTINCT customer_id, order_month FROM dbo.vw_order_summary WHERE is_revenue_order = 1),
cohorts AS (SELECT customer_id, MIN(order_month) AS cohort_month FROM purchases GROUP BY customer_id),
activity AS (
    SELECT c.cohort_month, c.customer_id, DATEDIFF(month, c.cohort_month, p.order_month) AS months_since_first
    FROM purchases p JOIN cohorts c ON c.customer_id = p.customer_id),
sizes AS (SELECT cohort_month, COUNT(*) AS cohort_size FROM cohorts GROUP BY cohort_month)
SELECT a.cohort_month, a.months_since_first, s.cohort_size,
       COUNT(DISTINCT a.customer_id) AS active_customers,
       ROUND(100.0 * COUNT(DISTINCT a.customer_id) / s.cohort_size, 1) AS retention_pct
FROM activity a
JOIN sizes s ON s.cohort_month = a.cohort_month
WHERE a.months_since_first BETWEEN 0 AND 12
GROUP BY a.cohort_month, a.months_since_first, s.cohort_size
ORDER BY a.cohort_month, a.months_since_first;
