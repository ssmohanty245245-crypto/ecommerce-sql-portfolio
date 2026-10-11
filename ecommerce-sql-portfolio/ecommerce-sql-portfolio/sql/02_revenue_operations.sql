/* =====================================================================
   02_revenue_operations.sql   |   README questions 6-15
   Dialect: SQL Server.  Requires 00b_staging_views.sql.
   All revenue uses the definitions documented in 00b (revenue order =
   Delivered/Shipped/Processing; net revenue = item revenue - refunds).
   ===================================================================== */
USE EcommerceAnalytics;
GO

-- [Q06] Monthly orders, gross item sales, discounts, shipping fees, AOV
SELECT order_month,
       COUNT(*)                                                    AS orders_booked,
       SUM(is_revenue_order)                                       AS revenue_orders,
       ROUND(SUM(CASE WHEN is_revenue_order = 1 THEN gross_item_sales ELSE 0 END), 2)                    AS gross_item_sales,
       ROUND(SUM(CASE WHEN is_revenue_order = 1 THEN gross_item_sales - net_item_revenue ELSE 0 END), 2) AS discounts,
       ROUND(SUM(recognised_revenue), 2)                           AS net_item_revenue,
       ROUND(SUM(CASE WHEN is_revenue_order = 1 THEN shipping_fee ELSE 0 END), 2)                        AS shipping_fees,
       ROUND(SUM(refund_amount), 2)                                AS refunds,
       ROUND(SUM(net_revenue), 2)                                  AS net_revenue_after_refunds,
       ROUND(SUM(CASE WHEN is_revenue_order = 1 THEN order_total ELSE 0 END)
             / NULLIF(SUM(is_revenue_order), 0), 2)                AS aov
FROM dbo.vw_order_summary
GROUP BY order_month
ORDER BY order_month;

-- [Q06b] Same KPIs by calendar year (sanity check: 2026 covers Jan-Sep only)
SELECT YEAR(order_date)                                AS order_year,
       COUNT(DISTINCT order_month)                     AS months_in_data,
       COUNT(*)                                        AS orders_booked,
       ROUND(SUM(recognised_revenue), 2)               AS net_item_revenue,
       ROUND(SUM(net_revenue), 2)                      AS net_revenue_after_refunds,
       ROUND(SUM(CASE WHEN is_revenue_order = 1 THEN order_total ELSE 0 END) / NULLIF(SUM(is_revenue_order), 0), 2) AS aov
FROM dbo.vw_order_summary
GROUP BY YEAR(order_date)
ORDER BY order_year;

-- [Q07a] Order status mix by month (% of booked orders)
SELECT order_month,
       COUNT(*) AS orders,
       ROUND(100.0 * SUM(CASE WHEN order_status = 'Delivered'  THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_delivered,
       ROUND(100.0 * SUM(CASE WHEN order_status = 'Shipped'    THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_shipped,
       ROUND(100.0 * SUM(CASE WHEN order_status = 'Processing' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_processing,
       ROUND(100.0 * SUM(CASE WHEN order_status = 'Cancelled'  THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_cancelled,
       ROUND(100.0 * SUM(CASE WHEN order_status = 'Returned'   THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_returned
FROM dbo.vw_order_summary
GROUP BY order_month
ORDER BY order_month;

-- [Q07b] Order status mix by sales channel
SELECT sales_channel,
       COUNT(*) AS orders,
       ROUND(100.0 * SUM(CASE WHEN order_status = 'Delivered'  THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_delivered,
       ROUND(100.0 * SUM(CASE WHEN order_status = 'Shipped'    THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_shipped,
       ROUND(100.0 * SUM(CASE WHEN order_status = 'Processing' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_processing,
       ROUND(100.0 * SUM(CASE WHEN order_status = 'Cancelled'  THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_cancelled,
       ROUND(100.0 * SUM(CASE WHEN order_status = 'Returned'   THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_returned
FROM dbo.vw_order_summary
GROUP BY sales_channel
ORDER BY orders DESC;

-- [Q08] Payment success rate and successful value by payment method
SELECT payment_method,
       COUNT(*)                                                                          AS attempts,
       SUM(CASE WHEN payment_status = 'Successful' THEN 1 ELSE 0 END)                    AS successful,
       SUM(CASE WHEN payment_status = 'Failed'     THEN 1 ELSE 0 END)                    AS failed,
       SUM(CASE WHEN payment_status = 'Pending'    THEN 1 ELSE 0 END)                    AS pending,
       SUM(CASE WHEN payment_status = 'Refunded'   THEN 1 ELSE 0 END)                    AS refunded,
       ROUND(100.0 * SUM(CASE WHEN payment_status = 'Successful' THEN 1 ELSE 0 END) / COUNT(*), 1) AS success_rate_pct,
       ROUND(100.0 * SUM(CASE WHEN payment_status = 'Failed'     THEN 1 ELSE 0 END) / COUNT(*), 1) AS failure_rate_pct,
       ROUND(SUM(CASE WHEN payment_status = 'Successful' THEN payment_amount ELSE 0 END), 2)       AS successful_value
FROM dbo.payments
GROUP BY payment_method
ORDER BY successful_value DESC;

-- [Q09a] Top 10 products by units sold (revenue orders only)
WITH product_sales AS (
    SELECT product_id, product_name, category,
           SUM(quantity)                AS units_sold,
           ROUND(SUM(net_line_revenue), 2) AS net_item_revenue
    FROM dbo.vw_item_outcomes
    WHERE is_revenue_order = 1 AND is_valid_line = 1
    GROUP BY product_id, product_name, category),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY units_sold DESC, net_item_revenue DESC) AS rn
    FROM product_sales)
SELECT rn AS rank_by_units, product_id, product_name, category, units_sold, net_item_revenue
FROM ranked
WHERE rn <= 10
ORDER BY rn;

-- [Q09b] Top 10 products by net item revenue
WITH product_sales AS (
    SELECT product_id, product_name, category,
           SUM(quantity)                AS units_sold,
           ROUND(SUM(net_line_revenue), 2) AS net_item_revenue
    FROM dbo.vw_item_outcomes
    WHERE is_revenue_order = 1 AND is_valid_line = 1
    GROUP BY product_id, product_name, category),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY net_item_revenue DESC) AS rn,
              SUM(net_item_revenue) OVER ()                        AS total_revenue
    FROM product_sales)
SELECT rn AS rank_by_revenue, product_id, product_name, category, units_sold, net_item_revenue,
       ROUND(100.0 * net_item_revenue / total_revenue, 2) AS pct_of_total_revenue
FROM ranked
WHERE rn <= 10
ORDER BY rn;

-- [Q10] Category revenue, refunds, estimated gross profit and gross margin %
SELECT category,
       SUM(quantity)                                                       AS units_sold,
       ROUND(SUM(net_line_revenue), 2)                                     AS net_item_revenue,
       ROUND(SUM(line_cost_clean), 2)                                      AS item_cost,
       ROUND(SUM(net_line_revenue - line_cost_clean), 2)                   AS gross_profit,
       ROUND(100.0 * SUM(net_line_revenue - line_cost_clean) / SUM(net_line_revenue), 1) AS gross_margin_pct,
       ROUND(SUM(refund_amount), 2)                                        AS refunds,
       ROUND(100.0 * SUM(refund_amount) / SUM(net_line_revenue), 1)        AS refund_pct_of_revenue,
       ROUND(100.0 * SUM(net_line_revenue) / SUM(SUM(net_line_revenue)) OVER (), 1) AS revenue_share_pct
FROM dbo.vw_item_outcomes
WHERE is_revenue_order = 1
GROUP BY category
ORDER BY net_item_revenue DESC;

-- [Q11a] Revenue and margin by SALES CHANNEL
SELECT sales_channel,
       SUM(is_revenue_order)                                     AS revenue_orders,
       ROUND(SUM(recognised_revenue), 2)                         AS net_item_revenue,
       ROUND(SUM(net_revenue), 2)                                AS net_revenue_after_refunds,
       ROUND(SUM(recognised_revenue - recognised_cost), 2)       AS gross_profit,
       ROUND(100.0 * SUM(recognised_revenue - recognised_cost) / SUM(recognised_revenue), 1) AS gross_margin_pct,
       ROUND(SUM(CASE WHEN is_revenue_order = 1 THEN order_total ELSE 0 END) / SUM(is_revenue_order), 2) AS aov
FROM dbo.vw_order_summary
GROUP BY sales_channel
ORDER BY net_item_revenue DESC;

-- [Q11b] Revenue and margin by SHIPPING STATE
SELECT shipping_state,
       SUM(is_revenue_order)                                     AS revenue_orders,
       ROUND(SUM(recognised_revenue), 2)                         AS net_item_revenue,
       ROUND(SUM(net_revenue), 2)                                AS net_revenue_after_refunds,
       ROUND(SUM(recognised_revenue - recognised_cost), 2)       AS gross_profit,
       ROUND(100.0 * SUM(recognised_revenue - recognised_cost) / SUM(recognised_revenue), 1) AS gross_margin_pct,
       ROUND(100.0 * SUM(recognised_revenue) / SUM(SUM(recognised_revenue)) OVER (), 1) AS revenue_share_pct
FROM dbo.vw_order_summary
GROUP BY shipping_state
ORDER BY net_item_revenue DESC;

-- [Q12a] High-value orders = top decile of revenue orders by order_total (NTILE(10) = 10)
WITH scored AS (
    SELECT o.order_id, o.customer_id, o.sales_channel, o.order_total, o.recognised_revenue,
           c.customer_segment,
           NTILE(10) OVER (ORDER BY o.order_total) AS value_decile
    FROM dbo.vw_order_summary o
    JOIN dbo.stg_customers c ON c.customer_id = o.customer_id
    WHERE o.is_revenue_order = 1)
SELECT customer_segment,
       COUNT(*)                                                                  AS revenue_orders,
       SUM(CASE WHEN value_decile = 10 THEN 1 ELSE 0 END)                        AS high_value_orders,
       ROUND(100.0 * SUM(CASE WHEN value_decile = 10 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_of_segment_orders_high_value,
       ROUND(100.0 * SUM(CASE WHEN value_decile = 10 THEN 1 ELSE 0 END)
             / SUM(SUM(CASE WHEN value_decile = 10 THEN 1 ELSE 0 END)) OVER (), 1)     AS share_of_all_high_value_orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                              AS share_of_all_orders
FROM scored
GROUP BY customer_segment
ORDER BY high_value_orders DESC;

-- [Q12b] High-value orders by sales channel + how much revenue the top decile carries
WITH scored AS (
    SELECT order_id, sales_channel, order_total, recognised_revenue,
           NTILE(10) OVER (ORDER BY order_total) AS value_decile
    FROM dbo.vw_order_summary
    WHERE is_revenue_order = 1)
SELECT sales_channel,
       COUNT(*)                                                                  AS revenue_orders,
       SUM(CASE WHEN value_decile = 10 THEN 1 ELSE 0 END)                        AS high_value_orders,
       ROUND(100.0 * SUM(CASE WHEN value_decile = 10 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_of_channel_orders_high_value,
       ROUND(100.0 * SUM(CASE WHEN value_decile = 10 THEN recognised_revenue ELSE 0 END)
             / SUM(recognised_revenue), 1)                                              AS pct_of_channel_revenue_from_top_decile
FROM scored
GROUP BY sales_channel
ORDER BY high_value_orders DESC;

-- [Q12c] Revenue concentration: share of total revenue by order-value decile
WITH scored AS (
    SELECT recognised_revenue, order_total, NTILE(10) OVER (ORDER BY order_total) AS value_decile
    FROM dbo.vw_order_summary
    WHERE is_revenue_order = 1)
SELECT value_decile,
       COUNT(*)                                          AS orders,
       ROUND(MIN(order_total), 2)                        AS min_order_total,
       ROUND(MAX(order_total), 2)                        AS max_order_total,
       ROUND(SUM(recognised_revenue), 2)                 AS revenue,
       ROUND(100.0 * SUM(recognised_revenue) / SUM(SUM(recognised_revenue)) OVER (), 1) AS pct_of_revenue
FROM scored
GROUP BY value_decile
ORDER BY value_decile DESC;

-- [Q13a] Cancellation and return rates BY MONTH
SELECT order_month,
       COUNT(*)                                                                           AS orders,
       ROUND(100.0 * SUM(CASE WHEN order_status = 'Cancelled' THEN 1 ELSE 0 END) / COUNT(*), 2) AS cancellation_rate_pct,
       ROUND(100.0 * SUM(has_return) / NULLIF(SUM(CASE WHEN order_status IN ('Delivered','Returned') THEN 1 ELSE 0 END), 0), 2) AS return_rate_pct
FROM dbo.vw_order_summary
GROUP BY order_month
ORDER BY order_month;

-- [Q13b] ... BY SALES CHANNEL
SELECT sales_channel,
       COUNT(*)                                                                           AS orders,
       ROUND(100.0 * SUM(CASE WHEN order_status = 'Cancelled' THEN 1 ELSE 0 END) / COUNT(*), 2) AS cancellation_rate_pct,
       ROUND(100.0 * SUM(has_return) / NULLIF(SUM(CASE WHEN order_status IN ('Delivered','Returned') THEN 1 ELSE 0 END), 0), 2) AS return_rate_pct
FROM dbo.vw_order_summary
GROUP BY sales_channel
ORDER BY orders DESC;

-- [Q13c] ... BY CATEGORY (order-line level)
SELECT category,
       COUNT(*)                                                                          AS order_lines,
       ROUND(100.0 * SUM(is_cancelled_line) / COUNT(*), 2)                               AS cancellation_rate_pct,
       ROUND(100.0 * SUM(is_returned_line)
             / NULLIF(SUM(CASE WHEN order_status IN ('Delivered','Returned') THEN 1 ELSE 0 END), 0), 2) AS return_rate_pct
FROM dbo.vw_item_outcomes
WHERE is_valid_line = 1
GROUP BY category
ORDER BY return_rate_pct DESC;

-- [Q13d] ... BY SHIPPING STATE
SELECT shipping_state,
       COUNT(*)                                                                           AS orders,
       ROUND(100.0 * SUM(CASE WHEN order_status = 'Cancelled' THEN 1 ELSE 0 END) / COUNT(*), 2) AS cancellation_rate_pct,
       ROUND(100.0 * SUM(has_return) / NULLIF(SUM(CASE WHEN order_status IN ('Delivered','Returned') THEN 1 ELSE 0 END), 0), 2) AS return_rate_pct
FROM dbo.vw_order_summary
GROUP BY shipping_state
ORDER BY return_rate_pct DESC;

-- [Q14a] Most common return reasons (returns table = item-level returns on delivered orders)
SELECT return_reason,
       COUNT(*)                                          AS return_rows,
       SUM(return_quantity_clean)                        AS units_returned,
       ROUND(SUM(refund_amount_clean), 2)                AS refund_value,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_returns
FROM dbo.stg_returns
GROUP BY return_reason
ORDER BY return_rows DESC;

-- [Q14b] Categories with the highest return rates (units returned / units sold on Delivered+Returned orders) + top reason
WITH cat AS (
    SELECT category,
           SUM(CASE WHEN order_status IN ('Delivered','Returned') THEN quantity ELSE 0 END) AS units_eligible,
           SUM(returned_units)                                                               AS units_returned,
           SUM(refund_amount)                                                                AS refund_value
    FROM dbo.vw_item_outcomes
    WHERE is_valid_line = 1
    GROUP BY category),
reasons AS (
    SELECT category, return_reason, COUNT(*) AS n,
           ROW_NUMBER() OVER (PARTITION BY category ORDER BY COUNT(*) DESC) AS rn
    FROM dbo.stg_returns
    GROUP BY category, return_reason)
SELECT c.category, c.units_eligible, c.units_returned,
       ROUND(100.0 * c.units_returned / c.units_eligible, 2) AS unit_return_rate_pct,
       ROUND(c.refund_value, 2)                              AS refund_value,
       r.return_reason                                       AS top_return_reason
FROM cat c
JOIN reasons r ON r.category = c.category AND r.rn = 1
ORDER BY unit_return_rate_pct DESC;

-- [Q15a] Order patterns by WEEKDAY (order placement day; NO delivery timestamps exist in this data)
WITH d AS (
    SELECT order_id, order_status, recognised_revenue, order_total, is_revenue_order,
           DATEDIFF(day, '1900-01-01', order_date) % 7 AS weekday_num      -- 0 = Monday (1900-01-01 was a Monday): independent of DATEFIRST
    FROM dbo.vw_order_summary)
SELECT weekday_num + 1 AS weekday_no,
       CASE weekday_num WHEN 0 THEN 'Monday' WHEN 1 THEN 'Tuesday' WHEN 2 THEN 'Wednesday' WHEN 3 THEN 'Thursday'
                        WHEN 4 THEN 'Friday' WHEN 5 THEN 'Saturday' ELSE 'Sunday' END AS weekday_name,
       COUNT(*)                                                                      AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                            AS pct_of_orders,
       ROUND(SUM(recognised_revenue), 2)                                             AS net_item_revenue,
       ROUND(SUM(CASE WHEN is_revenue_order = 1 THEN order_total ELSE 0 END) / SUM(is_revenue_order), 2) AS aov,
       ROUND(100.0 * SUM(CASE WHEN order_status = 'Cancelled' THEN 1 ELSE 0 END) / COUNT(*), 2) AS cancellation_rate_pct
FROM d
GROUP BY weekday_num
ORDER BY weekday_no;

-- [Q15b] Seasonality: calendar month-of-year across all years (orders per month, to remove year-length bias)
WITH m AS (
    SELECT MONTH(order_date) AS month_no, order_month, COUNT(*) AS orders, SUM(recognised_revenue) AS revenue
    FROM dbo.vw_order_summary
    GROUP BY MONTH(order_date), order_month)
SELECT month_no,
       COUNT(*)                           AS years_of_data,
       ROUND(AVG(1.0 * orders), 0)        AS avg_orders_per_month,
       ROUND(AVG(revenue), 0)             AS avg_net_item_revenue_per_month
FROM m
GROUP BY month_no
ORDER BY month_no;
