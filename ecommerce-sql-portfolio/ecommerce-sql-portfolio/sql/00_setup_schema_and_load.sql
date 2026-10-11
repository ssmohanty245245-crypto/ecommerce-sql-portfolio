/* =====================================================================
   00_setup_schema_and_load.sql   |   Dialect: Microsoft SQL Server (2017+)
   Project : E-commerce Business Performance & Customer Analytics
   Purpose : Create the database + 8 raw tables and bulk-load the CSVs.
   HOW TO RUN:
     1. Copy the repo's /data folder somewhere SQL Server can read it
        (the *server* must have access to the path).
     2. Edit @DataPath below (keep the trailing backslash).
     3. Run the whole script.
   No SQL Server file access? Use SSMS: right-click DB > Tasks >
   Import Flat File..., import each CSV into a table with the SAME name,
   then skip the BULK INSERT section.
   NOTE: Raw tables are loaded "as is". Cleaning happens in
   00b_staging_views.sql, never by editing the raw data.
   ===================================================================== */

IF DB_ID('EcommerceAnalytics') IS NULL CREATE DATABASE EcommerceAnalytics;
GO
USE EcommerceAnalytics;
GO

DROP TABLE IF EXISTS dbo.returns, dbo.payments, dbo.order_items, dbo.website_sessions,
                     dbo.orders, dbo.campaigns, dbo.products, dbo.customers;
GO

CREATE TABLE dbo.customers (
    customer_id         VARCHAR(10)  NOT NULL PRIMARY KEY,
    signup_date         DATE         NULL,
    city                VARCHAR(50)  NULL,
    state               VARCHAR(50)  NULL,
    acquisition_channel VARCHAR(30)  NULL,
    customer_segment    VARCHAR(20)  NULL,
    age_band            VARCHAR(10)  NULL,
    marketing_opt_in    VARCHAR(3)   NULL);

CREATE TABLE dbo.products (
    product_id   VARCHAR(10)   NOT NULL PRIMARY KEY,
    product_name VARCHAR(100)  NULL,
    category     VARCHAR(50)   NULL,
    brand        VARCHAR(50)   NULL,
    unit_cost    DECIMAL(12,2) NULL,
    list_price   DECIMAL(12,2) NULL,
    supplier_id  VARCHAR(10)   NULL,
    launch_date  DATE          NULL,
    is_active    VARCHAR(3)    NULL);

CREATE TABLE dbo.campaigns (
    campaign_id    VARCHAR(10)   NOT NULL PRIMARY KEY,
    campaign_name  VARCHAR(100)  NULL,
    channel        VARCHAR(30)   NULL,
    start_date     DATE          NULL,
    end_date       DATE          NULL,
    budget         DECIMAL(14,2) NULL,
    target_segment VARCHAR(20)   NULL);

CREATE TABLE dbo.orders (
    order_id             VARCHAR(10)   NOT NULL PRIMARY KEY,
    customer_id          VARCHAR(10)   NULL,
    order_date           DATE          NULL,
    order_status         VARCHAR(20)   NULL,
    sales_channel        VARCHAR(30)   NULL,
    shipping_city        VARCHAR(50)   NULL,
    shipping_state       VARCHAR(50)   NULL,
    discount_code        VARCHAR(20)   NULL,
    shipping_fee         DECIMAL(10,2) NULL,
    item_subtotal        DECIMAL(14,2) NULL,
    order_total          DECIMAL(14,2) NULL,
    estimated_order_cost DECIMAL(14,2) NULL);

CREATE TABLE dbo.order_items (
    order_item_id      VARCHAR(12)   NOT NULL PRIMARY KEY,
    order_id           VARCHAR(10)   NULL,
    product_id         VARCHAR(10)   NULL,
    quantity           INT           NULL,
    unit_price         DECIMAL(12,2) NULL,
    discount_pct       DECIMAL(6,3)  NULL,
    unit_selling_price DECIMAL(12,2) NULL,
    unit_cost_at_sale  DECIMAL(12,2) NULL,
    line_revenue       DECIMAL(14,2) NULL,
    line_cost          DECIMAL(14,2) NULL);

CREATE TABLE dbo.payments (
    payment_id     VARCHAR(12)   NOT NULL PRIMARY KEY,
    order_id       VARCHAR(10)   NULL,
    payment_method VARCHAR(30)   NULL,
    payment_amount DECIMAL(14,2) NULL,
    payment_status VARCHAR(20)   NULL,
    payment_date   DATE          NULL);

CREATE TABLE dbo.returns (
    return_id       VARCHAR(10)   NOT NULL PRIMARY KEY,
    order_id        VARCHAR(10)   NULL,
    order_item_id   VARCHAR(12)   NULL,
    return_reason   VARCHAR(40)   NULL,
    return_quantity INT           NULL,
    return_date     DATE          NULL,
    refund_amount   DECIMAL(14,2) NULL);

CREATE TABLE dbo.website_sessions (
    session_id           VARCHAR(12) NOT NULL PRIMARY KEY,
    customer_id          VARCHAR(10) NULL,
    session_date         DATE        NULL,
    traffic_source       VARCHAR(30) NULL,
    device_type          VARCHAR(20) NULL,
    landing_page         VARCHAR(20) NULL,
    session_duration_sec INT         NULL,
    pages_viewed         INT         NULL,
    converted            VARCHAR(3)  NULL,
    campaign_id          VARCHAR(10) NULL);
GO

/* ---------- BULK LOAD (edit the path) ---------- */
DECLARE @DataPath NVARCHAR(400) = N'C:\ecommerce-sql-portfolio\data\';
DECLARE @opts     NVARCHAR(400) = N') WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', KEEPNULLS, CODEPAGE = ''65001'');';
DECLARE @sql NVARCHAR(MAX);

SET @sql = N'BULK INSERT dbo.customers         FROM ''' + @DataPath + N'customers.csv''' + @opts;         EXEC (@sql);
SET @sql = N'BULK INSERT dbo.products          FROM ''' + @DataPath + N'products.csv''' + @opts;          EXEC (@sql);
SET @sql = N'BULK INSERT dbo.campaigns         FROM ''' + @DataPath + N'campaigns.csv''' + @opts;         EXEC (@sql);
SET @sql = N'BULK INSERT dbo.orders            FROM ''' + @DataPath + N'orders.csv''' + @opts;            EXEC (@sql);
SET @sql = N'BULK INSERT dbo.order_items       FROM ''' + @DataPath + N'order_items.csv''' + @opts;       EXEC (@sql);
SET @sql = N'BULK INSERT dbo.payments          FROM ''' + @DataPath + N'payments.csv''' + @opts;          EXEC (@sql);
SET @sql = N'BULK INSERT dbo.returns           FROM ''' + @DataPath + N'returns.csv''' + @opts;           EXEC (@sql);
SET @sql = N'BULK INSERT dbo.website_sessions  FROM ''' + @DataPath + N'website_sessions.csv''' + @opts;  EXEC (@sql);
GO

/* ---------- Load check: expected 8,000 / 600 / 40 / 30,000 / 65,570 / 31,323 / 1,772 / 70,000 ---------- */
SELECT 'customers' AS table_name, COUNT_BIG(*) AS row_count FROM dbo.customers
UNION ALL SELECT 'products', COUNT_BIG(*) FROM dbo.products
UNION ALL SELECT 'campaigns', COUNT_BIG(*) FROM dbo.campaigns
UNION ALL SELECT 'orders', COUNT_BIG(*) FROM dbo.orders
UNION ALL SELECT 'order_items', COUNT_BIG(*) FROM dbo.order_items
UNION ALL SELECT 'payments', COUNT_BIG(*) FROM dbo.payments
UNION ALL SELECT 'returns', COUNT_BIG(*) FROM dbo.returns
UNION ALL SELECT 'website_sessions', COUNT_BIG(*) FROM dbo.website_sessions;
