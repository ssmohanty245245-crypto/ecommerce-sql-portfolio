/* =====================================================================
   03_customer_analytics.sql   |   README questions 16-22
   Dialect: SQL Server.  Requires 00b_staging_views.sql.
   A customer "purchase" = a REVENUE order (Delivered/Shipped/Processing).
   Analysis date = MAX(order_date) in the data (never GETDATE()).
   ===================================================================== */
USE EcommerceAnalytics;
GO

-- [Q16] New vs repeat customers by month (new = month of the customer's first purchase)
WITH purchases AS (
    SELECT customer_id, order_month, recognised_revenue,
           MIN(order_month) OVER (PARTITION BY customer_id) AS first_purchase_month
    FROM dbo.vw_order_summary
    WHERE is_revenue_order = 1),
monthly AS (
    SELECT order_month,
           COUNT(DISTINCT customer_id) AS active_customers,
           COUNT(DISTINCT CASE WHEN order_month = first_purchase_month THEN customer_id END) AS new_customers,
           COUNT(*)                                                                          AS orders,
           SUM(CASE WHEN order_month = first_purchase_month THEN recognised_revenue ELSE 0 END) AS new_customer_revenue,
           SUM(recognised_revenue)                                                           AS total_revenue
    FROM purchases
    GROUP BY order_month)
SELECT order_month, active_customers, new_customers,
       active_customers - new_customers                               AS repeat_customers,
       ROUND(100.0 * (active_customers - new_customers) / active_customers, 1) AS repeat_customer_pct,
       ROUND(100.0 * new_customer_revenue / total_revenue, 1)          AS pct_revenue_from_new_customers
FROM monthly
ORDER BY order_month;

-- [Q17] Top 20 customers by lifetime net revenue, with cash actually collected
WITH cust AS (
    SELECT o.customer_id,
           COUNT(*)                          AS lifetime_orders,
           SUM(o.net_revenue)                AS lifetime_net_revenue,
           SUM(o.successful_amount)          AS successful_payment_value,
           MAX(o.order_date)                 AS last_order_date
    FROM dbo.vw_order_summary o
    WHERE o.is_revenue_order = 1
    GROUP BY o.customer_id),
ranked AS (
    SELECT *, RANK() OVER (ORDER BY lifetime_net_revenue DESC)     AS revenue_rank,
              RANK() OVER (ORDER BY successful_payment_value DESC) AS payment_rank
    FROM cust)
SELECT r.revenue_rank, r.payment_rank, r.customer_id, c.customer_segment, c.acquisition_channel, c.state,
       r.lifetime_orders, ROUND(r.lifetime_net_revenue, 2) AS lifetime_net_revenue,
       ROUND(r.successful_payment_value, 2) AS successful_payment_value, r.last_order_date
FROM ranked r
JOIN dbo.stg_customers c ON c.customer_id = r.customer_id
WHERE r.revenue_rank <= 20
ORDER BY r.revenue_rank;

-- [Q17b] Customer-value concentration: what share of revenue comes from the top 10% / 20% of customers?
WITH cust AS (
    SELECT customer_id, SUM(net_revenue) AS lifetime_net_revenue
    FROM dbo.vw_order_summary WHERE is_revenue_order = 1 GROUP BY customer_id),
tiles AS (
    SELECT lifetime_net_revenue, NTILE(10) OVER (ORDER BY lifetime_net_revenue DESC) AS decile
    FROM cust)
SELECT decile, COUNT(*) AS customers, ROUND(SUM(lifetime_net_revenue), 2) AS revenue,
       ROUND(100.0 * SUM(lifetime_net_revenue) / SUM(SUM(lifetime_net_revenue)) OVER (), 1) AS pct_of_revenue,
       ROUND(100.0 * SUM(SUM(lifetime_net_revenue)) OVER (ORDER BY decile) / SUM(SUM(lifetime_net_revenue)) OVER (), 1) AS cumulative_pct
FROM tiles
GROUP BY decile
ORDER BY decile;

-- [Q18a] Repeat purchase rate (customers with 2+ purchases / customers with 1+)
WITH per_customer AS (
    SELECT customer_id, COUNT(*) AS orders
    FROM dbo.vw_order_summary WHERE is_revenue_order = 1 GROUP BY customer_id)
SELECT COUNT(*)                                                     AS purchasing_customers,
       SUM(CASE WHEN orders >= 2 THEN 1 ELSE 0 END)                AS repeat_customers,
       ROUND(100.0 * SUM(CASE WHEN orders >= 2 THEN 1 ELSE 0 END) / COUNT(*), 1) AS repeat_purchase_rate_pct,
       ROUND(AVG(1.0 * orders), 2)                                  AS avg_orders_per_customer,
       (SELECT COUNT(*) FROM dbo.customers) - COUNT(*)              AS customers_with_no_purchase
FROM per_customer;

-- [Q18b] Orders-per-customer distribution
WITH per_customer AS (
    SELECT customer_id, COUNT(*) AS orders
    FROM dbo.vw_order_summary WHERE is_revenue_order = 1 GROUP BY customer_id)
SELECT CASE WHEN orders >= 10 THEN '10+' ELSE CAST(orders AS VARCHAR(3)) END AS orders_bucket,
       MIN(orders) AS sort_key,
       COUNT(*)    AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_customers
FROM per_customer
GROUP BY CASE WHEN orders >= 10 THEN '10+' ELSE CAST(orders AS VARCHAR(3)) END
ORDER BY sort_key;

-- [Q18c] Time between consecutive purchases (days) - overall and distribution
WITH seq AS (
    SELECT customer_id, order_date,
           LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS prev_order_date
    FROM dbo.vw_order_summary
    WHERE is_revenue_order = 1),
gaps AS (
    SELECT customer_id, DATEDIFF(day, prev_order_date, order_date) AS gap_days
    FROM seq
    WHERE prev_order_date IS NOT NULL)
SELECT CASE WHEN gap_days <= 30  THEN '1) 0-30 days'
            WHEN gap_days <= 60  THEN '2) 31-60 days'
            WHEN gap_days <= 90  THEN '3) 61-90 days'
            WHEN gap_days <= 180 THEN '4) 91-180 days'
            WHEN gap_days <= 365 THEN '5) 181-365 days'
            ELSE '6) 365+ days' END                       AS gap_bucket,
       COUNT(*)                                            AS repeat_orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_of_gaps,
       ROUND(AVG(1.0 * gap_days), 1)                       AS avg_gap_days_in_bucket
FROM gaps
GROUP BY CASE WHEN gap_days <= 30  THEN '1) 0-30 days'
              WHEN gap_days <= 60  THEN '2) 31-60 days'
              WHEN gap_days <= 90  THEN '3) 61-90 days'
              WHEN gap_days <= 180 THEN '4) 91-180 days'
              WHEN gap_days <= 365 THEN '5) 181-365 days'
              ELSE '6) 365+ days' END
ORDER BY gap_bucket;

-- [Q18d] Average days between purchases by customer segment
WITH seq AS (
    SELECT customer_id, order_date,
           LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS prev_order_date
    FROM dbo.vw_order_summary
    WHERE is_revenue_order = 1)
SELECT c.customer_segment,
       COUNT(*)                                               AS repeat_orders,
       ROUND(AVG(1.0 * DATEDIFF(day, s.prev_order_date, s.order_date)), 1) AS avg_days_between_purchases
FROM seq s
JOIN dbo.stg_customers c ON c.customer_id = s.customer_id
WHERE s.prev_order_date IS NOT NULL
GROUP BY c.customer_segment
ORDER BY avg_days_between_purchases;

-- [Q19a] RFM segmentation. R/F/M scored 1-5 with NTILE(5) (5 = best). Analysis date = last order date.
WITH base AS (
    SELECT customer_id,
           MAX(order_date)    AS last_order_date,
           COUNT(*)           AS frequency,
           SUM(net_revenue)   AS monetary
    FROM dbo.vw_order_summary
    WHERE is_revenue_order = 1
    GROUP BY customer_id),
ref AS (SELECT MAX(order_date) AS analysis_date FROM dbo.orders),
scored AS (
    SELECT b.customer_id, b.frequency, b.monetary,
           DATEDIFF(day, b.last_order_date, r.analysis_date)                AS recency_days,
           NTILE(5) OVER (ORDER BY b.last_order_date ASC)                   AS r_score,   -- older last order = lower score
           NTILE(5) OVER (ORDER BY b.frequency ASC, b.monetary ASC)         AS f_score,
           NTILE(5) OVER (ORDER BY b.monetary ASC)                          AS m_score
    FROM base b CROSS JOIN ref r),
segmented AS (
    SELECT *,
           CASE WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
                WHEN r_score >= 3 AND f_score >= 4                  THEN 'Loyal Customers'
                WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Promising'
                WHEN r_score >= 3 AND f_score >= 2                  THEN 'Potential Loyalists'
                WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 3 THEN 'Cannot Lose Them'
                WHEN r_score <= 2 AND f_score >= 3                  THEN 'At Risk'
                ELSE 'Hibernating / Lost' END AS rfm_segment
    FROM scored)
SELECT rfm_segment,
       COUNT(*)                                            AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_of_customers,
       ROUND(AVG(1.0 * recency_days), 0)                   AS avg_recency_days,
       ROUND(AVG(1.0 * frequency), 1)                      AS avg_orders,
       ROUND(AVG(monetary), 0)                             AS avg_net_revenue,
       ROUND(SUM(monetary), 0)                             AS total_net_revenue,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_of_revenue
FROM segmented
GROUP BY rfm_segment
ORDER BY total_net_revenue DESC;

-- [Q20a] Customers inactive for 90 / 180 days as of the analysis date (last revenue order)
WITH last_buy AS (
    SELECT customer_id, MAX(order_date) AS last_order_date
    FROM dbo.vw_order_summary WHERE is_revenue_order = 1 GROUP BY customer_id),
ref AS (SELECT MAX(order_date) AS analysis_date FROM dbo.orders),
x AS (
    SELECT c.customer_id, c.customer_segment, l.last_order_date,
           DATEDIFF(day, l.last_order_date, r.analysis_date) AS days_since_last_order
    FROM dbo.stg_customers c
    LEFT JOIN last_buy l ON l.customer_id = c.customer_id
    CROSS JOIN ref r)
SELECT COUNT(*)                                                                         AS total_customers,
       SUM(CASE WHEN last_order_date IS NULL THEN 1 ELSE 0 END)                         AS never_purchased,
       SUM(CASE WHEN days_since_last_order > 90  THEN 1 ELSE 0 END)                     AS inactive_over_90d,
       SUM(CASE WHEN days_since_last_order > 180 THEN 1 ELSE 0 END)                     AS inactive_over_180d,
       ROUND(100.0 * SUM(CASE WHEN days_since_last_order > 90  THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_inactive_90d,
       ROUND(100.0 * SUM(CASE WHEN days_since_last_order > 180 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_inactive_180d
FROM x;

-- [Q20b] Inactive customers by CRM customer_segment and marketing opt-in (who can we actually win back?)
WITH last_buy AS (
    SELECT customer_id, MAX(order_date) AS last_order_date
    FROM dbo.vw_order_summary WHERE is_revenue_order = 1 GROUP BY customer_id),
ref AS (SELECT MAX(order_date) AS analysis_date FROM dbo.orders),
x AS (
    SELECT c.customer_id, c.customer_segment, c.marketing_opt_in,
           DATEDIFF(day, l.last_order_date, r.analysis_date) AS days_since_last_order
    FROM dbo.stg_customers c
    LEFT JOIN last_buy l ON l.customer_id = c.customer_id
    CROSS JOIN ref r)
SELECT customer_segment,
       COUNT(*)                                                                         AS customers,
       SUM(CASE WHEN days_since_last_order > 90  THEN 1 ELSE 0 END)                     AS inactive_over_90d,
       SUM(CASE WHEN days_since_last_order > 180 THEN 1 ELSE 0 END)                     AS inactive_over_180d,
       ROUND(100.0 * SUM(CASE WHEN days_since_last_order > 180 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_inactive_180d,
       SUM(CASE WHEN days_since_last_order > 180 AND marketing_opt_in = 'Yes' THEN 1 ELSE 0 END) AS winback_reachable_180d
FROM x
GROUP BY customer_segment
ORDER BY pct_inactive_180d DESC;

-- [Q21] Acquisition channel vs customer lifetime value (observed through the analysis date)
WITH cust AS (
    SELECT customer_id, COUNT(*) AS orders, SUM(net_revenue) AS net_revenue, SUM(recognised_revenue - recognised_cost) AS gross_profit
    FROM dbo.vw_order_summary WHERE is_revenue_order = 1 GROUP BY customer_id)
SELECT c.acquisition_channel,
       COUNT(*)                                              AS customers,
       SUM(CASE WHEN x.customer_id IS NOT NULL THEN 1 ELSE 0 END) AS purchasing_customers,
       ROUND(AVG(COALESCE(x.net_revenue, 0)), 0)              AS avg_ltv_net_revenue,
       ROUND(AVG(COALESCE(x.gross_profit, 0)), 0)             AS avg_ltv_gross_profit,
       ROUND(AVG(1.0 * COALESCE(x.orders, 0)), 2)             AS avg_orders_per_customer,
       ROUND(SUM(COALESCE(x.net_revenue, 0)) / NULLIF(SUM(COALESCE(x.orders, 0)), 0), 0) AS revenue_per_order,
       ROUND(100.0 * SUM(CASE WHEN x.orders >= 2 THEN 1 ELSE 0 END) / COUNT(*), 1)  AS repeat_rate_pct,
       ROUND(100.0 * SUM(COALESCE(x.net_revenue, 0)) / SUM(SUM(COALESCE(x.net_revenue, 0))) OVER (), 1) AS pct_of_total_revenue
FROM dbo.stg_customers c
LEFT JOIN cust x ON x.customer_id = c.customer_id
GROUP BY c.acquisition_channel
ORDER BY avg_ltv_net_revenue DESC;

-- [Q21b] Does the CRM customer_segment label (VIP / Regular / New / At Risk) actually predict value? (validation check)
WITH cust AS (
    SELECT customer_id, COUNT(*) AS orders, SUM(net_revenue) AS net_revenue
    FROM dbo.vw_order_summary WHERE is_revenue_order = 1 GROUP BY customer_id)
SELECT c.customer_segment,
       COUNT(*)                                          AS customers,
       ROUND(AVG(COALESCE(x.net_revenue, 0)), 0)          AS avg_ltv_net_revenue,
       ROUND(AVG(1.0 * COALESCE(x.orders, 0)), 2)         AS avg_orders_per_customer,
       ROUND(100.0 * SUM(CASE WHEN x.orders >= 2 THEN 1 ELSE 0 END) / COUNT(*), 1) AS repeat_rate_pct
FROM dbo.stg_customers c
LEFT JOIN cust x ON x.customer_id = c.customer_id
GROUP BY c.customer_segment
ORDER BY avg_ltv_net_revenue DESC;

-- [Q22a] Customers who bought across multiple product categories
-- (revenue is pre-aggregated per customer BEFORE joining so order totals are never multiplied by line count)
WITH cust_cat AS (
    SELECT o.customer_id, COUNT(DISTINCT i.category) AS categories_bought
    FROM dbo.vw_order_summary o
    JOIN dbo.vw_item_outcomes i ON i.order_id = o.order_id AND i.is_valid_line = 1
    WHERE o.is_revenue_order = 1
    GROUP BY o.customer_id),
cust_val AS (
    SELECT customer_id, COUNT(*) AS orders, SUM(net_revenue) AS net_revenue
    FROM dbo.vw_order_summary
    WHERE is_revenue_order = 1
    GROUP BY customer_id)
SELECT cc.categories_bought,
       COUNT(*)                                            AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_of_customers,
       ROUND(AVG(1.0 * cv.orders), 1)                      AS avg_orders,
       ROUND(AVG(cv.net_revenue), 0)                       AS avg_ltv
FROM cust_cat cc
JOIN cust_val cv ON cv.customer_id = cc.customer_id
GROUP BY cc.categories_bought
ORDER BY cc.categories_bought;

-- [Q22b] Category-pair affinity: customers who bought BOTH categories (top 10 pairs)
WITH cc AS (
    SELECT DISTINCT o.customer_id, i.category
    FROM dbo.vw_order_summary o
    JOIN dbo.vw_item_outcomes i ON i.order_id = o.order_id AND i.is_valid_line = 1
    WHERE o.is_revenue_order = 1),
pairs AS (
    SELECT a.category AS category_a, b.category AS category_b, COUNT(*) AS customers_both
    FROM cc a
    JOIN cc b ON b.customer_id = a.customer_id AND a.category < b.category
    GROUP BY a.category, b.category),
ranked AS (SELECT *, ROW_NUMBER() OVER (ORDER BY customers_both DESC) AS rn FROM pairs)
SELECT rn, category_a, category_b, customers_both
FROM ranked
WHERE rn <= 10
ORDER BY rn;
