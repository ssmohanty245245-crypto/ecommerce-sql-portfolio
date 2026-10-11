/* =====================================================================
   00b_staging_views.sql   |   Dialect: SQL Server
   Purpose : Clean/standardise raw data in VIEWS (raw tables untouched)
             and encode the KPI business rules ONCE, so every analysis
             file uses identical definitions.
   Run order: after 00_setup + 01_data_quality, before 02-05.

   ---------------------- KPI DEFINITIONS ------------------------------
   Gross item sales   = SUM(quantity * unit_price)             (list value, before discounts)
   Discount value     = Gross item sales - Net item revenue
   Net item revenue   = SUM(quantity * unit_selling_price)  (the actual transaction price)
                        The discount_pct column is NOT used for revenue: 6 rows hold a corrupt negative
                        discount and 4 of them carry a real discounted selling price, so recomputing
                        from discount_pct would invent revenue. unit_selling_price reconciles to
                        orders.item_subtotal for 100% of orders (see 01_data_quality Q05d).
   Revenue order      = order_status IN ('Delivered','Shipped','Processing')
                        -> 'Cancelled' is excluded (no sale happened)
                        -> 'Returned' is excluded (whole order came back)
   Recognised revenue = Net item revenue of revenue orders (shipping fee excluded)
   Refunds            = returns.refund_amount (capped at the line's net revenue)
                        deducted ONLY for revenue orders, so a 'Returned' order
                        that also has return rows is never double counted.
   Net revenue        = Recognised revenue - Refunds
   Gross profit       = Recognised revenue - item cost (qty * unit_cost_at_sale), pre-refund
   Gross margin %     = Gross profit / Recognised revenue
   AOV                = AVG(order_total) over revenue orders (includes shipping)
   Cash collected     = SUM(payment_amount) WHERE payment_status = 'Successful'
   Cancellation rate  = Cancelled orders / all orders
   Return rate (order)= orders with status 'Returned' OR a returns row
                        / orders with status 'Delivered' or 'Returned'
   Analysis date      = MAX(order_date)  (2026-09-30) - never GETDATE()
   Conversion rate    = sessions with converted='Yes' / sessions
   ===================================================================== */
USE EcommerceAnalytics;
GO

CREATE OR ALTER VIEW dbo.stg_customers AS
SELECT customer_id,
       signup_date,
       COALESCE(NULLIF(LTRIM(RTRIM(city)), ''), 'Unknown') AS city,
       state,
       CASE WHEN acquisition_channel IS NULL OR LOWER(acquisition_channel) = 'unknown'
            THEN 'Unknown' ELSE acquisition_channel END    AS acquisition_channel,
       customer_segment, age_band, marketing_opt_in
FROM dbo.customers;
GO

CREATE OR ALTER VIEW dbo.stg_orders AS
WITH city_state AS (            -- each city maps to exactly one state, so a NULL state can be repaired
    SELECT shipping_city, MAX(shipping_state) AS shipping_state
    FROM dbo.orders
    WHERE shipping_state IS NOT NULL
    GROUP BY shipping_city)
SELECT o.order_id, o.customer_id, o.order_date,
       DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1) AS order_month,
       o.order_status, o.sales_channel, o.shipping_city,
       COALESCE(o.shipping_state, cs.shipping_state, 'Unknown')  AS shipping_state,
       o.discount_code, o.shipping_fee, o.item_subtotal, o.order_total, o.estimated_order_cost,
       CASE WHEN o.order_status IN ('Delivered','Shipped','Processing') THEN 1 ELSE 0 END AS is_revenue_order
FROM dbo.orders o
LEFT JOIN city_state cs ON cs.shipping_city = o.shipping_city;
GO

CREATE OR ALTER VIEW dbo.stg_order_items AS
SELECT oi.order_item_id, oi.order_id, oi.product_id,
       p.category, p.brand, p.product_name,
       oi.quantity, oi.unit_price, oi.discount_pct,
       CASE WHEN oi.discount_pct < 0 THEN 0 ELSE oi.discount_pct END      AS discount_pct_clean,
       oi.unit_cost_at_sale,
       CASE WHEN oi.quantity > 0 THEN 1 ELSE 0 END                         AS is_valid_line,
       oi.quantity * oi.unit_price                                         AS gross_line_sales,
       oi.quantity * oi.unit_selling_price                                  AS net_line_revenue,   -- transaction price: ties to orders.item_subtotal on 100% of orders
       ROUND(oi.quantity * oi.unit_cost_at_sale, 2)                        AS line_cost_clean
FROM dbo.order_items oi
LEFT JOIN dbo.products p ON p.product_id = oi.product_id;
GO

CREATE OR ALTER VIEW dbo.stg_returns AS
SELECT r.return_id, r.order_id, r.order_item_id, r.return_reason, r.return_date,
       r.return_quantity,
       CASE WHEN r.return_quantity > oi.quantity THEN oi.quantity ELSE r.return_quantity END AS return_quantity_clean,
       CASE WHEN r.return_quantity > oi.quantity THEN 1 ELSE 0 END                           AS qty_exceeds_purchase,
       r.refund_amount,
       CASE WHEN r.refund_amount > oi.net_line_revenue THEN oi.net_line_revenue ELSE r.refund_amount END AS refund_amount_clean,
       oi.product_id, oi.category
FROM dbo.returns r
JOIN dbo.stg_order_items oi ON oi.order_item_id = r.order_item_id;
GO

CREATE OR ALTER VIEW dbo.stg_payments_by_order AS      -- ONE row per order: prevents fan-out when joined
SELECT o.order_id,
       COUNT(p.payment_id)                                                         AS payment_attempts,
       SUM(CASE WHEN p.payment_status = 'Successful' THEN 1 ELSE 0 END)            AS successful_rows,
       SUM(CASE WHEN p.payment_status = 'Successful' THEN p.payment_amount ELSE 0 END) AS successful_amount,
       SUM(CASE WHEN p.payment_status = 'Refunded'   THEN p.payment_amount ELSE 0 END) AS refunded_amount
FROM dbo.orders o
LEFT JOIN dbo.payments p ON p.order_id = o.order_id
GROUP BY o.order_id;
GO

CREATE OR ALTER VIEW dbo.vw_order_summary AS          -- ONE row per order: the analytical workhorse
WITH refunds AS (
    SELECT order_id, SUM(refund_amount_clean) AS refund_amount, SUM(return_quantity_clean) AS returned_units
    FROM dbo.stg_returns GROUP BY order_id),
lines AS (
    SELECT order_id,
           SUM(CASE WHEN is_valid_line = 1 THEN quantity ELSE 0 END) AS units,
           SUM(is_valid_line)                                        AS line_count,
           SUM(gross_line_sales)                                     AS gross_item_sales,
           SUM(net_line_revenue)                                     AS net_item_revenue,
           SUM(line_cost_clean)                                      AS item_cost
    FROM dbo.stg_order_items GROUP BY order_id)
SELECT o.order_id, o.customer_id, o.order_date, o.order_month, o.order_status, o.sales_channel,
       o.shipping_city, o.shipping_state, o.discount_code, o.shipping_fee, o.order_total,
       o.is_revenue_order,
       COALESCE(l.units, 0)            AS units,
       COALESCE(l.gross_item_sales, 0) AS gross_item_sales,
       COALESCE(l.net_item_revenue, 0) AS net_item_revenue,
       COALESCE(l.item_cost, 0)        AS item_cost,
       CASE WHEN o.is_revenue_order = 1 THEN COALESCE(l.net_item_revenue, 0) ELSE 0 END AS recognised_revenue,
       CASE WHEN o.is_revenue_order = 1 THEN COALESCE(l.item_cost, 0)        ELSE 0 END AS recognised_cost,
       CASE WHEN o.is_revenue_order = 1 THEN COALESCE(rf.refund_amount, 0)   ELSE 0 END AS refund_amount,
       CASE WHEN o.is_revenue_order = 1
            THEN COALESCE(l.net_item_revenue, 0) - COALESCE(rf.refund_amount, 0) ELSE 0 END AS net_revenue,
       CASE WHEN o.order_status = 'Returned' OR rf.order_id IS NOT NULL THEN 1 ELSE 0 END AS has_return,
       pb.payment_attempts,
       pb.successful_amount,
       CASE WHEN pb.successful_amount = 0                              THEN 'No successful payment'
            WHEN ABS(pb.successful_amount - o.order_total) <= 0.05     THEN 'Fully paid'
            WHEN pb.successful_amount < o.order_total                  THEN 'Partially paid'
            ELSE 'Overpaid' END                                         AS payment_recon_status
FROM dbo.stg_orders o
LEFT JOIN lines l                    ON l.order_id  = o.order_id
LEFT JOIN refunds rf                 ON rf.order_id = o.order_id
LEFT JOIN dbo.stg_payments_by_order pb ON pb.order_id = o.order_id;
GO

CREATE OR ALTER VIEW dbo.vw_item_outcomes AS         -- ONE row per order line with its order context
WITH ret AS (
    SELECT order_item_id, SUM(return_quantity_clean) AS returned_units, SUM(refund_amount_clean) AS refund_amount
    FROM dbo.stg_returns GROUP BY order_item_id)
SELECT oi.order_item_id, oi.order_id, oi.product_id, oi.product_name, oi.category, oi.brand,
       oi.quantity, oi.is_valid_line, oi.gross_line_sales, oi.net_line_revenue, oi.line_cost_clean,
       o.order_month, o.order_date, o.order_status, o.sales_channel, o.shipping_state, o.is_revenue_order,
       CASE WHEN o.order_status = 'Cancelled' THEN 1 ELSE 0 END                        AS is_cancelled_line,
       CASE WHEN o.order_status = 'Returned' OR ret.order_item_id IS NOT NULL THEN 1 ELSE 0 END AS is_returned_line,
       COALESCE(ret.returned_units, 0)                                                 AS returned_units,
       COALESCE(ret.refund_amount, 0)                                                  AS refund_amount
FROM dbo.stg_order_items oi
JOIN dbo.stg_orders o   ON o.order_id = oi.order_id
LEFT JOIN ret           ON ret.order_item_id = oi.order_item_id;
GO

CREATE OR ALTER VIEW dbo.stg_sessions AS
SELECT s.session_id, s.customer_id, s.session_date, s.traffic_source, s.device_type, s.landing_page,
       CASE WHEN s.session_duration_sec < 0 THEN NULL ELSE s.session_duration_sec END AS session_duration_clean,
       s.pages_viewed,
       CASE WHEN s.converted = 'Yes' THEN 1 ELSE 0 END                                AS is_converted,
       s.campaign_id,
       CASE WHEN c.campaign_id IS NOT NULL
             AND s.session_date >= c.start_date AND s.session_date <= c.end_date
            THEN 1 ELSE 0 END                                                         AS within_campaign_window
FROM dbo.website_sessions s
LEFT JOIN dbo.campaigns c ON c.campaign_id = s.campaign_id;
GO
