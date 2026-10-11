/* =====================================================================
   04_marketing_analytics.sql   |   README questions 23-27
   Dialect: SQL Server.  Requires 00b_staging_views.sql.
   CAUTION (documented in 01_data_quality Q05d): campaign attribution in
   this dataset is weak - most sessions pre-date their campaign start and
   rarely match the campaign's channel. Campaign results are therefore
   reported as "attributed sessions", never as ROI.
   ===================================================================== */
USE EcommerceAnalytics;
GO

-- [Q23a] Sessions, conversion rate and average duration BY TRAFFIC SOURCE
SELECT traffic_source,
       COUNT(*)                                              AS sessions,
       SUM(is_converted)                                     AS conversions,
       ROUND(100.0 * SUM(is_converted) / COUNT(*), 2)        AS conversion_rate_pct,
       ROUND(AVG(1.0 * session_duration_clean), 1)           AS avg_session_duration_sec,
       ROUND(AVG(1.0 * pages_viewed), 2)                     AS avg_pages_viewed
FROM dbo.stg_sessions
GROUP BY traffic_source
ORDER BY conversion_rate_pct DESC;

-- [Q23b] ... BY DEVICE
SELECT device_type,
       COUNT(*)                                              AS sessions,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS pct_of_sessions,
       SUM(is_converted)                                     AS conversions,
       ROUND(100.0 * SUM(is_converted) / COUNT(*), 2)        AS conversion_rate_pct,
       ROUND(AVG(1.0 * session_duration_clean), 1)           AS avg_session_duration_sec,
       ROUND(AVG(1.0 * pages_viewed), 2)                     AS avg_pages_viewed
FROM dbo.stg_sessions
GROUP BY device_type
ORDER BY sessions DESC;

-- [Q23c] ... BY TRAFFIC SOURCE x DEVICE
SELECT traffic_source, device_type,
       COUNT(*)                                              AS sessions,
       ROUND(100.0 * SUM(is_converted) / COUNT(*), 2)        AS conversion_rate_pct,
       ROUND(AVG(1.0 * session_duration_clean), 1)           AS avg_session_duration_sec
FROM dbo.stg_sessions
GROUP BY traffic_source, device_type
ORDER BY traffic_source, device_type;

-- [Q24a] Conversion rate by LANDING PAGE
SELECT landing_page,
       COUNT(*)                                              AS sessions,
       SUM(is_converted)                                     AS conversions,
       ROUND(100.0 * SUM(is_converted) / COUNT(*), 2)        AS conversion_rate_pct,
       ROUND(AVG(1.0 * session_duration_clean), 1)           AS avg_session_duration_sec,
       ROUND(AVG(1.0 * pages_viewed), 2)                     AS avg_pages_viewed
FROM dbo.stg_sessions
GROUP BY landing_page
ORDER BY conversion_rate_pct DESC;

-- [Q24b] Conversion rate by CAMPAIGN (ranked) - includes window-validity flag
SELECT s.campaign_id, c.campaign_name, c.channel AS campaign_channel,
       COUNT(*)                                              AS attributed_sessions,
       SUM(s.is_converted)                                   AS conversions,
       ROUND(100.0 * SUM(s.is_converted) / COUNT(*), 2)      AS conversion_rate_pct,
       ROUND(100.0 * SUM(s.within_campaign_window) / COUNT(*), 1) AS pct_sessions_inside_campaign_window,
       RANK() OVER (ORDER BY 1.0 * SUM(s.is_converted) / COUNT(*) DESC) AS conversion_rank
FROM dbo.stg_sessions s
JOIN dbo.campaigns c ON c.campaign_id = s.campaign_id
GROUP BY s.campaign_id, c.campaign_name, c.channel
ORDER BY conversion_rank;

-- [Q24c] Landing page x traffic source: best and worst converting combinations (min 300 sessions)
WITH combo AS (
    SELECT landing_page, traffic_source, COUNT(*) AS sessions,
           100.0 * SUM(is_converted) / COUNT(*) AS conversion_rate_pct
    FROM dbo.stg_sessions
    GROUP BY landing_page, traffic_source
    HAVING COUNT(*) >= 300),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY conversion_rate_pct DESC) AS rn_best,
              ROW_NUMBER() OVER (ORDER BY conversion_rate_pct ASC)  AS rn_worst
    FROM combo)
SELECT CASE WHEN rn_best <= 5 THEN 'Top 5' ELSE 'Bottom 5' END AS bucket,
       landing_page, traffic_source, sessions, ROUND(conversion_rate_pct, 2) AS conversion_rate_pct
FROM ranked
WHERE rn_best <= 5 OR rn_worst <= 5
ORDER BY conversion_rate_pct DESC;

-- [Q25] Campaign budget vs attributed sessions / conversions.  NOT ROI: there is no spend-to-order link.
WITH camp AS (
    SELECT campaign_id, COUNT(*) AS attributed_sessions, SUM(is_converted) AS attributed_conversions
    FROM dbo.stg_sessions GROUP BY campaign_id)
SELECT c.campaign_id, c.campaign_name, c.channel, c.target_segment, c.start_date, c.end_date,
       c.budget,
       x.attributed_sessions, x.attributed_conversions,
       ROUND(c.budget / x.attributed_sessions, 2)                              AS budget_per_attributed_session,
       ROUND(c.budget / NULLIF(x.attributed_conversions, 0), 2)                AS budget_per_attributed_conversion,
       ROUND(100.0 * x.attributed_conversions / x.attributed_sessions, 2)      AS conversion_rate_pct
FROM dbo.campaigns c
JOIN camp x ON x.campaign_id = c.campaign_id
ORDER BY budget_per_attributed_conversion DESC;

-- [Q25b] Budget efficiency by campaign CHANNEL (aggregated, more stable than 40 individual campaigns)
WITH camp AS (
    SELECT campaign_id, COUNT(*) AS sessions, SUM(is_converted) AS conversions
    FROM dbo.stg_sessions GROUP BY campaign_id)
SELECT c.channel,
       COUNT(*)                                          AS campaigns,
       ROUND(SUM(c.budget), 0)                           AS total_budget,
       SUM(x.sessions)                                   AS attributed_sessions,
       SUM(x.conversions)                                AS attributed_conversions,
       ROUND(SUM(c.budget) / SUM(x.sessions), 2)         AS budget_per_session,
       ROUND(SUM(c.budget) / SUM(x.conversions), 2)      AS budget_per_conversion,
       ROUND(100.0 * SUM(x.conversions) / SUM(x.sessions), 2) AS conversion_rate_pct
FROM dbo.campaigns c
JOIN camp x ON x.campaign_id = c.campaign_id
GROUP BY c.channel
ORDER BY budget_per_conversion DESC;

-- [Q26] Traffic sources with HIGH engagement but LOW conversion (index vs the all-session average; 1.00 = average)
WITH src AS (
    SELECT traffic_source,
           COUNT(*)                                  AS sessions,
           AVG(1.0 * session_duration_clean)         AS avg_duration,
           AVG(1.0 * pages_viewed)                   AS avg_pages,
           100.0 * SUM(is_converted) / COUNT(*)      AS conv_rate
    FROM dbo.stg_sessions
    GROUP BY traffic_source),
tot AS (
    SELECT AVG(1.0 * session_duration_clean) AS t_duration, AVG(1.0 * pages_viewed) AS t_pages,
           100.0 * SUM(is_converted) / COUNT(*) AS t_conv
    FROM dbo.stg_sessions)
SELECT s.traffic_source, s.sessions,
       ROUND(s.avg_duration, 1) AS avg_duration_sec, ROUND(s.avg_pages, 2) AS avg_pages, ROUND(s.conv_rate, 2) AS conversion_rate_pct,
       ROUND(s.avg_duration / t.t_duration, 3) AS duration_index,
       ROUND(s.avg_pages / t.t_pages, 3)       AS pages_index,
       ROUND(s.conv_rate / t.t_conv, 3)        AS conversion_index,
       CASE WHEN (s.avg_duration / t.t_duration + s.avg_pages / t.t_pages) / 2 > 1.05 AND s.conv_rate / t.t_conv < 0.95 THEN 'High engagement / low conversion'
            WHEN s.conv_rate / t.t_conv < 0.95 THEN 'Low conversion'
            ELSE 'Within +/-5% of average (no material gap)' END AS flag
FROM src s CROSS JOIN tot t
ORDER BY conversion_index;

-- [Q26b] Same lens by LANDING PAGE
WITH src AS (
    SELECT landing_page,
           COUNT(*)                                  AS sessions,
           AVG(1.0 * session_duration_clean)         AS avg_duration,
           AVG(1.0 * pages_viewed)                   AS avg_pages,
           100.0 * SUM(is_converted) / COUNT(*)      AS conv_rate
    FROM dbo.stg_sessions
    GROUP BY landing_page),
tot AS (
    SELECT AVG(1.0 * session_duration_clean) AS t_duration, AVG(1.0 * pages_viewed) AS t_pages,
           100.0 * SUM(is_converted) / COUNT(*) AS t_conv
    FROM dbo.stg_sessions)
SELECT s.landing_page, s.sessions,
       ROUND(s.avg_duration, 1) AS avg_duration_sec, ROUND(s.avg_pages, 2) AS avg_pages, ROUND(s.conv_rate, 2) AS conversion_rate_pct,
       ROUND(s.avg_duration / t.t_duration, 3) AS duration_index,
       ROUND(s.avg_pages / t.t_pages, 3)       AS pages_index,
       ROUND(s.conv_rate / t.t_conv, 3)        AS conversion_index,
       CASE WHEN (s.avg_duration / t.t_duration + s.avg_pages / t.t_pages) / 2 > 1.05 AND s.conv_rate / t.t_conv < 0.95 THEN 'High engagement / low conversion'
            WHEN s.conv_rate / t.t_conv < 0.95 THEN 'Low conversion'
            ELSE 'Within +/-5% of average (no material gap)' END AS flag
FROM src s CROSS JOIN tot t
ORDER BY conversion_index;

-- [Q27a] First-order behaviour by ACQUISITION CHANNEL (first revenue order per customer)
WITH ranked AS (
    SELECT o.customer_id, o.order_id, o.order_total, o.units, o.sales_channel, o.discount_code,
           o.gross_item_sales, o.net_item_revenue,
           ROW_NUMBER() OVER (PARTITION BY o.customer_id ORDER BY o.order_date, o.order_id) AS order_seq,
           COUNT(*)     OVER (PARTITION BY o.customer_id)                                   AS lifetime_orders
    FROM dbo.vw_order_summary o
    WHERE o.is_revenue_order = 1),
first_orders AS (SELECT * FROM ranked WHERE order_seq = 1)
SELECT c.acquisition_channel,
       COUNT(*)                                                         AS first_orders,
       ROUND(AVG(f.order_total), 0)                                     AS avg_first_order_value,
       ROUND(AVG(1.0 * f.units), 2)                                     AS avg_units,
       ROUND(100.0 * (SUM(f.gross_item_sales) - SUM(f.net_item_revenue)) / SUM(f.gross_item_sales), 1) AS discount_rate_pct,
       ROUND(100.0 * SUM(CASE WHEN f.discount_code <> 'NONE' THEN 1 ELSE 0 END) / COUNT(*), 1)       AS pct_used_discount_code,
       ROUND(100.0 * SUM(CASE WHEN f.sales_channel = 'Mobile App' THEN 1 ELSE 0 END) / COUNT(*), 1)   AS pct_first_order_on_app,
       ROUND(100.0 * SUM(CASE WHEN f.lifetime_orders >= 2 THEN 1 ELSE 0 END) / COUNT(*), 1)           AS pct_placed_second_order
FROM first_orders f
JOIN dbo.stg_customers c ON c.customer_id = f.customer_id
GROUP BY c.acquisition_channel
ORDER BY first_orders DESC;

-- [Q27b] First-order discount code mix (what do new customers use?)
WITH ranked AS (
    SELECT customer_id, discount_code, order_total,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS order_seq
    FROM dbo.vw_order_summary
    WHERE is_revenue_order = 1)
SELECT discount_code,
       COUNT(*)                                           AS first_orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_first_orders,
       ROUND(AVG(order_total), 0)                         AS avg_first_order_value
FROM ranked
WHERE order_seq = 1
GROUP BY discount_code
ORDER BY first_orders DESC;
