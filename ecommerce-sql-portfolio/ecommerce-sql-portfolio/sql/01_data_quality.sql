/* =====================================================================
   01_data_quality.sql   |   README questions 1-5 (+ extra checks)
   Dialect: SQL Server.  Run AFTER 00_setup and 00b_staging_views (Q04-Q05 reuse the order-level view).
   Principle: profile and VALIDATE grain before any join or KPI.
   ===================================================================== */
USE EcommerceAnalytics;
GO

-- [Q01a] Row counts per table
SELECT 'customers' AS table_name, COUNT_BIG(*) AS row_count FROM dbo.customers
UNION ALL SELECT 'products',         COUNT_BIG(*) FROM dbo.products
UNION ALL SELECT 'campaigns',        COUNT_BIG(*) FROM dbo.campaigns
UNION ALL SELECT 'orders',           COUNT_BIG(*) FROM dbo.orders
UNION ALL SELECT 'order_items',      COUNT_BIG(*) FROM dbo.order_items
UNION ALL SELECT 'payments',         COUNT_BIG(*) FROM dbo.payments
UNION ALL SELECT 'returns',          COUNT_BIG(*) FROM dbo.returns
UNION ALL SELECT 'website_sessions', COUNT_BIG(*) FROM dbo.website_sessions;

-- [Q01b] Date coverage of every date column
SELECT 'customers.signup_date' AS date_column, MIN(signup_date) AS min_date, MAX(signup_date) AS max_date FROM dbo.customers
UNION ALL SELECT 'products.launch_date',   MIN(launch_date),   MAX(launch_date)   FROM dbo.products
UNION ALL SELECT 'campaigns.start_date',   MIN(start_date),    MAX(start_date)    FROM dbo.campaigns
UNION ALL SELECT 'campaigns.end_date',     MIN(end_date),      MAX(end_date)      FROM dbo.campaigns
UNION ALL SELECT 'orders.order_date',      MIN(order_date),    MAX(order_date)    FROM dbo.orders
UNION ALL SELECT 'payments.payment_date',  MIN(payment_date),  MAX(payment_date)  FROM dbo.payments
UNION ALL SELECT 'returns.return_date',    MIN(return_date),   MAX(return_date)   FROM dbo.returns
UNION ALL SELECT 'sessions.session_date',  MIN(session_date),  MAX(session_date)  FROM dbo.website_sessions;

-- [Q01c] Duplicate primary keys (duplicate_keys = 0 means the stated grain holds)
SELECT 'customers' AS table_name, COUNT(*) AS total_rows, COUNT(DISTINCT customer_id) AS distinct_keys,
       COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_keys FROM dbo.customers
UNION ALL SELECT 'products',         COUNT(*), COUNT(DISTINCT product_id),    COUNT(*) - COUNT(DISTINCT product_id)    FROM dbo.products
UNION ALL SELECT 'campaigns',        COUNT(*), COUNT(DISTINCT campaign_id),   COUNT(*) - COUNT(DISTINCT campaign_id)   FROM dbo.campaigns
UNION ALL SELECT 'orders',           COUNT(*), COUNT(DISTINCT order_id),      COUNT(*) - COUNT(DISTINCT order_id)      FROM dbo.orders
UNION ALL SELECT 'order_items',      COUNT(*), COUNT(DISTINCT order_item_id), COUNT(*) - COUNT(DISTINCT order_item_id) FROM dbo.order_items
UNION ALL SELECT 'payments',         COUNT(*), COUNT(DISTINCT payment_id),    COUNT(*) - COUNT(DISTINCT payment_id)    FROM dbo.payments
UNION ALL SELECT 'returns',          COUNT(*), COUNT(DISTINCT return_id),     COUNT(*) - COUNT(DISTINCT return_id)     FROM dbo.returns
UNION ALL SELECT 'website_sessions', COUNT(*), COUNT(DISTINCT session_id),    COUNT(*) - COUNT(DISTINCT session_id)    FROM dbo.website_sessions;

-- [Q01d] NULL / blank / 'unknown' profile for the columns that can hold them
SELECT 'customers' AS table_name, 'city' AS column_name, COUNT(*) AS total_rows,
       SUM(CASE WHEN city IS NULL OR LTRIM(RTRIM(city)) = '' THEN 1 ELSE 0 END) AS null_or_blank,
       0 AS unknown_values FROM dbo.customers
UNION ALL SELECT 'customers', 'state', COUNT(*), SUM(CASE WHEN state IS NULL THEN 1 ELSE 0 END), 0 FROM dbo.customers
UNION ALL SELECT 'customers', 'acquisition_channel', COUNT(*),
       SUM(CASE WHEN acquisition_channel IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN LOWER(acquisition_channel) = 'unknown' THEN 1 ELSE 0 END) FROM dbo.customers
UNION ALL SELECT 'orders', 'customer_id', COUNT(*), SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END), 0 FROM dbo.orders
UNION ALL SELECT 'orders', 'shipping_state', COUNT(*), SUM(CASE WHEN shipping_state IS NULL THEN 1 ELSE 0 END), 0 FROM dbo.orders
UNION ALL SELECT 'orders', 'shipping_city', COUNT(*), SUM(CASE WHEN shipping_city IS NULL THEN 1 ELSE 0 END), 0 FROM dbo.orders
UNION ALL SELECT 'order_items', 'product_id', COUNT(*), SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END), 0 FROM dbo.order_items
UNION ALL SELECT 'payments', 'payment_method', COUNT(*), SUM(CASE WHEN payment_method IS NULL THEN 1 ELSE 0 END), 0 FROM dbo.payments
UNION ALL SELECT 'returns', 'return_reason', COUNT(*), SUM(CASE WHEN return_reason IS NULL THEN 1 ELSE 0 END), 0 FROM dbo.returns
UNION ALL SELECT 'website_sessions', 'customer_id', COUNT(*), SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END), 0 FROM dbo.website_sessions
UNION ALL SELECT 'website_sessions', 'campaign_id', COUNT(*), SUM(CASE WHEN campaign_id IS NULL THEN 1 ELSE 0 END), 0 FROM dbo.website_sessions
UNION ALL SELECT 'website_sessions', 'session_duration_sec', COUNT(*), SUM(CASE WHEN session_duration_sec IS NULL THEN 1 ELSE 0 END), 0 FROM dbo.website_sessions;

-- [Q02a] Orders whose customer_id does not exist in customers (orphans). Expect 0 rows.
SELECT o.order_id, o.customer_id, o.order_date, o.order_total
FROM dbo.orders o
LEFT JOIN dbo.customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL;

-- [Q02b] Referential-integrity scorecard for ALL foreign keys (orphan_rows = 0 is the goal)
SELECT 'orders.customer_id -> customers' AS relationship, COUNT(*) AS orphan_rows
FROM dbo.orders o LEFT JOIN dbo.customers c ON c.customer_id = o.customer_id WHERE o.customer_id IS NOT NULL AND c.customer_id IS NULL
UNION ALL SELECT 'order_items.order_id -> orders', COUNT(*)
FROM dbo.order_items oi LEFT JOIN dbo.orders o ON o.order_id = oi.order_id WHERE o.order_id IS NULL
UNION ALL SELECT 'order_items.product_id -> products', COUNT(*)
FROM dbo.order_items oi LEFT JOIN dbo.products p ON p.product_id = oi.product_id WHERE p.product_id IS NULL
UNION ALL SELECT 'payments.order_id -> orders', COUNT(*)
FROM dbo.payments pay LEFT JOIN dbo.orders o ON o.order_id = pay.order_id WHERE o.order_id IS NULL
UNION ALL SELECT 'returns.order_item_id -> order_items', COUNT(*)
FROM dbo.returns r LEFT JOIN dbo.order_items oi ON oi.order_item_id = r.order_item_id WHERE oi.order_item_id IS NULL
UNION ALL SELECT 'sessions.customer_id -> customers', COUNT(*)
FROM dbo.website_sessions s LEFT JOIN dbo.customers c ON c.customer_id = s.customer_id WHERE s.customer_id IS NOT NULL AND c.customer_id IS NULL
UNION ALL SELECT 'sessions.campaign_id -> campaigns', COUNT(*)
FROM dbo.website_sessions s LEFT JOIN dbo.campaigns c ON c.campaign_id = s.campaign_id WHERE s.campaign_id IS NOT NULL AND c.campaign_id IS NULL
UNION ALL SELECT 'orders with NO order_items (childless parents)', COUNT(*)
FROM dbo.orders o WHERE NOT EXISTS (SELECT 1 FROM dbo.order_items oi WHERE oi.order_id = o.order_id);

-- [Q03a] Order-item validity summary: unknown products, bad quantities / prices / discounts
SELECT COUNT(*) AS total_lines,
       SUM(CASE WHEN p.product_id IS NULL THEN 1 ELSE 0 END)                         AS unknown_product_lines,
       SUM(CASE WHEN oi.quantity IS NULL OR oi.quantity <= 0 THEN 1 ELSE 0 END)      AS zero_or_negative_quantity,
       SUM(CASE WHEN oi.unit_price IS NULL OR oi.unit_price <= 0 THEN 1 ELSE 0 END)  AS non_positive_price,
       SUM(CASE WHEN oi.discount_pct < 0 THEN 1 ELSE 0 END)                          AS negative_discount,
       SUM(CASE WHEN oi.discount_pct > 0.5 THEN 1 ELSE 0 END)                        AS discount_above_50pct,
       SUM(CASE WHEN ABS(oi.unit_selling_price - oi.unit_price * (1 - oi.discount_pct)) > 0.011 THEN 1 ELSE 0 END) AS selling_price_not_matching_discount,
       SUM(CASE WHEN ABS(oi.line_revenue - oi.quantity * oi.unit_selling_price) > 0.011 THEN 1 ELSE 0 END)        AS line_revenue_not_qty_x_price,
       SUM(CASE WHEN p.product_id IS NOT NULL AND ABS(oi.unit_price - p.list_price) > 0.011 THEN 1 ELSE 0 END)    AS price_differs_from_list_price
FROM dbo.order_items oi
LEFT JOIN dbo.products p ON p.product_id = oi.product_id;

-- [Q03b] The individual invalid lines (zero quantity or negative discount)
SELECT order_item_id, order_id, product_id, quantity, unit_price, discount_pct, unit_selling_price, line_revenue
FROM dbo.order_items
WHERE quantity <= 0 OR discount_pct < 0
ORDER BY order_item_id;

-- [Q03c] Same product repeated on one order (grain surprise: not unique on order_id + product_id)
SELECT COUNT(*) AS order_product_pairs_repeated, SUM(line_count) AS lines_involved
FROM (SELECT order_id, product_id, COUNT(*) AS line_count
      FROM dbo.order_items GROUP BY order_id, product_id HAVING COUNT(*) > 1) d;

-- [Q04a] Payment reconciliation: do SUCCESSFUL payments cover the order total?  (by order status)
SELECT order_status,
       COUNT(*)                                                                         AS orders,
       SUM(CASE WHEN payment_recon_status = 'Fully paid'            THEN 1 ELSE 0 END) AS fully_paid,
       SUM(CASE WHEN payment_recon_status = 'Partially paid'        THEN 1 ELSE 0 END) AS partially_paid,
       SUM(CASE WHEN payment_recon_status = 'No successful payment' THEN 1 ELSE 0 END) AS no_successful_payment,
       SUM(CASE WHEN payment_recon_status = 'Overpaid'              THEN 1 ELSE 0 END) AS overpaid,
       ROUND(100.0 * SUM(CASE WHEN payment_recon_status = 'Fully paid' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_fully_paid
FROM dbo.vw_order_summary
GROUP BY order_status
ORDER BY orders DESC;

-- [Q04b] Value view of the reconciliation gap
SELECT payment_recon_status,
       COUNT(*)                                       AS orders,
       ROUND(SUM(order_total), 2)                     AS order_total_value,
       ROUND(SUM(successful_amount), 2)               AS successful_payment_value,
       ROUND(SUM(order_total - successful_amount), 2) AS uncollected_value
FROM dbo.vw_order_summary
GROUP BY payment_recon_status
ORDER BY orders DESC;

-- [Q04c] Delivered orders with NO successful payment (the most worrying revenue-assurance case)
SELECT COUNT(*) AS delivered_orders_unpaid, ROUND(SUM(order_total), 2) AS value_at_risk
FROM dbo.vw_order_summary
WHERE order_status = 'Delivered' AND payment_recon_status = 'No successful payment';

-- [Q04e] Cancelled orders that still hold SUCCESSFUL payments (cash taken, no sale) - refund-liability check
SELECT COUNT(*)                                   AS cancelled_orders_with_successful_payment,
       ROUND(SUM(successful_amount), 2)           AS cash_held_on_cancelled_orders
FROM dbo.vw_order_summary
WHERE order_status = 'Cancelled' AND successful_amount > 0;

-- [Q04d] Sample of partially paid orders (split payment where the second leg did not succeed)
SELECT o.order_id, o.order_status, o.order_total, o.successful_amount,
       p.payment_id, p.payment_method, p.payment_amount, p.payment_status
FROM dbo.vw_order_summary o
JOIN dbo.payments p ON p.order_id = o.order_id
WHERE o.payment_recon_status = 'Partially paid'
  AND o.order_id IN (SELECT order_id FROM dbo.vw_order_summary WHERE payment_recon_status = 'Partially paid' AND order_id <= 'O0001500')
ORDER BY o.order_id, p.payment_id;

-- [Q05a] Return rows whose return_quantity exceeds the purchased quantity
SELECT r.return_id, r.order_id, r.order_item_id, r.return_quantity, oi.quantity AS purchased_quantity,
       r.refund_amount, oi.line_revenue
FROM dbo.returns r
JOIN dbo.order_items oi ON oi.order_item_id = r.order_item_id
WHERE r.return_quantity > oi.quantity
ORDER BY r.return_id;

-- [Q05b] Return-table integrity summary
SELECT COUNT(*)                                                                        AS return_rows,
       SUM(CASE WHEN r.return_quantity > oi.quantity THEN 1 ELSE 0 END)               AS qty_exceeds_purchase,
       SUM(CASE WHEN r.refund_amount > oi.line_revenue + 0.01 THEN 1 ELSE 0 END)      AS refund_exceeds_line_revenue,
       SUM(CASE WHEN r.return_date > (SELECT MAX(order_date) FROM dbo.orders) THEN 1 ELSE 0 END) AS return_date_after_last_order_date
FROM dbo.returns r
JOIN dbo.order_items oi ON oi.order_item_id = r.order_item_id;

-- [Q05c] Status vs returns-table consistency: how many 'Returned' orders have NO return rows?
SELECT o.order_status,
       COUNT(*)                                                        AS orders,
       SUM(CASE WHEN r.order_id IS NOT NULL THEN 1 ELSE 0 END)         AS orders_with_return_rows
FROM dbo.orders o
LEFT JOIN (SELECT DISTINCT order_id FROM dbo.returns) r ON r.order_id = o.order_id
GROUP BY o.order_status
ORDER BY orders DESC;

-- [Q05d] Other logical checks: dates, sessions and attribution reliability
SELECT 'Orders placed before the customer signup_date' AS check_name, COUNT(*) AS rows_affected
FROM dbo.orders o JOIN dbo.customers c ON c.customer_id = o.customer_id WHERE o.order_date < c.signup_date
UNION ALL SELECT 'Sessions with negative duration', COUNT(*) FROM dbo.website_sessions WHERE session_duration_sec < 0
UNION ALL SELECT 'Sessions dated BEFORE their campaign start_date', COUNT(*)
FROM dbo.website_sessions s JOIN dbo.campaigns c ON c.campaign_id = s.campaign_id WHERE s.session_date < c.start_date
UNION ALL SELECT 'Sessions whose traffic_source differs from the campaign channel', COUNT(*)
FROM dbo.website_sessions s JOIN dbo.campaigns c ON c.campaign_id = s.campaign_id WHERE s.traffic_source <> c.channel
UNION ALL SELECT 'Payments dated before the order date', COUNT(*)
FROM dbo.payments p JOIN dbo.orders o ON o.order_id = p.order_id WHERE p.payment_date < o.order_date
UNION ALL SELECT 'Orders where order_total <> item_subtotal + shipping_fee', COUNT(*)
FROM dbo.orders WHERE ABS(order_total - (item_subtotal + shipping_fee)) > 0.011
UNION ALL SELECT 'Orders where item_subtotal <> SUM(order_items.line_revenue)', COUNT(*)
FROM dbo.orders o JOIN (SELECT order_id, SUM(line_revenue) AS s FROM dbo.order_items GROUP BY order_id) l ON l.order_id = o.order_id
WHERE ABS(o.item_subtotal - l.s) > 0.011;
