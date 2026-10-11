/* Run the whole project in order. Open in SSMS and enable  Query > SQLCMD Mode.
   Paths are relative to the folder the script is opened from (the /sql folder). */
:r 00_setup_schema_and_load.sql
:r 00b_staging_views.sql
:r 01_data_quality.sql
:r 02_revenue_operations.sql
:r 03_customer_analytics.sql
:r 04_marketing_analytics.sql
:r 05_advanced_sql.sql
