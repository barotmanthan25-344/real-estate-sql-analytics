/* =====================================================================
   REAL ESTATE ANALYTICS — 20 ADVANCED KPIs (SQL SERVER)
   Tables used (as per actual DB schema):
     dbo.residential_listings   
     dbo.rental_market          
     dbo.transactions_trends    
   ===================================================================== */

-- KPI 1 | RANK() | Scenario: A buyer wants to know how each city ranks by avg price/sqft.
SELECT city, AVG(price_per_sqft) AS avg_price_sqft, RANK() OVER (ORDER BY AVG(price_per_sqft) DESC) AS city_price_rank
FROM dbo.residential_listings GROUP BY city;

-- KPI 2 | DENSE_RANK() | Scenario: Within each city, rank localities by price to spot premium pockets.
SELECT city, locality, AVG(price_per_sqft) AS avg_locality_price, DENSE_RANK() OVER (PARTITION BY city ORDER BY AVG(price_per_sqft) DESC) AS locality_tier
FROM dbo.residential_listings GROUP BY city, locality;

-- KPI 3 | NTILE(4) | Scenario: Split all listings into 4 price bands (budget to luxury) for marketing.
SELECT listing_id, city, total_price_lakh, NTILE(4) OVER (ORDER BY total_price_lakh) AS price_quartile
FROM dbo.residential_listings;

-- KPI 4 | LAG() | Scenario: Track how avg sale price changes quarter to quarter to detect slowdowns.
SELECT sale_year, sale_quarter, AVG(CAST(sale_price_inr AS BIGINT)) AS avg_sale_price, LAG(AVG(CAST(sale_price_inr AS BIGINT))) OVER (ORDER BY sale_year, sale_quarter) AS prev_qtr_price
FROM dbo.transactions_trends GROUP BY sale_year, sale_quarter;

-- KPI 5 | LEAD() | Scenario: Compare current quarter price to next quarter to validate forecasts.
SELECT sale_year, sale_quarter, AVG(price_per_sqft) AS curr_qtr_psf, LEAD(AVG(price_per_sqft)) OVER (ORDER BY sale_year, sale_quarter) AS next_qtr_psf
FROM dbo.transactions_trends GROUP BY sale_year, sale_quarter;

-- KPI 6 | FIRST_VALUE() | Scenario: Investors want the lowest-priced active listing in every city.
SELECT DISTINCT city, FIRST_VALUE(listing_id) OVER (PARTITION BY city ORDER BY total_price_lakh ASC) AS cheapest_listing_id
FROM dbo.residential_listings;

-- KPI 7 | LAST_VALUE() | Scenario: Identify the top-end luxury listing in each city for premium leads.
SELECT DISTINCT city, LAST_VALUE(listing_id) OVER (PARTITION BY city ORDER BY total_price_lakh ASC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS costliest_listing_id
FROM dbo.residential_listings;

-- KPI 8 | SUM() OVER() | Scenario: Track cumulative revenue closed across the year for target tracking.
SELECT sale_date, city, sale_price_inr, SUM(CAST(sale_price_inr AS BIGINT)) OVER (ORDER BY sale_date ROWS UNBOUNDED PRECEDING) AS running_total_sales
FROM dbo.transactions_trends;

-- KPI 9 | AVG() OVER() | Scenario: Smooth out price noise to see the real market trend per city.
SELECT transaction_id, city, sale_date, price_per_sqft, AVG(price_per_sqft) OVER (PARTITION BY city ORDER BY sale_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS moving_avg_3txn
FROM dbo.transactions_trends;

-- KPI 10 | PERCENT_RANK() | Scenario: Landlord wants to know how their rent compares to the market.
SELECT rental_id, city, monthly_rent_inr, PERCENT_RANK() OVER (PARTITION BY city ORDER BY monthly_rent_inr) AS rent_percentile
FROM dbo.rental_market;

-- KPI 11 | CUME_DIST() | Scenario: What fraction of listings are at or below a given carpet area (sizing demand).
SELECT listing_id, city, carpet_area_sqft, CUME_DIST() OVER (ORDER BY carpet_area_sqft) AS size_cume_dist
FROM dbo.residential_listings;

-- KPI 12 | PIVOT | Scenario: Management wants one row per city, columns = property types, for a board report.
SELECT city, Apartment, Villa, Studio, Penthouse FROM (SELECT city, property_type, price_per_sqft FROM dbo.residential_listings) AS src
PIVOT (AVG(price_per_sqft) FOR property_type IN (Apartment, Villa, Studio, Penthouse)) AS pvt;

-- KPI 13 | CTE + Window | Scenario: Build a reusable yield base table, then rank cities by rental yield.
WITH city_yield AS (SELECT r.city, AVG(CAST(r.annual_rent_inr AS BIGINT)) AS avg_annual_rent, AVG(CAST(t.sale_price_inr AS BIGINT)) AS avg_sale_price FROM dbo.rental_market r JOIN dbo.transactions_trends t ON r.city = t.city GROUP BY r.city)
SELECT city, ROUND((avg_annual_rent * 1.0 / avg_sale_price) * 100, 2) AS gross_rental_yield_pct, RANK() OVER (ORDER BY (avg_annual_rent * 1.0 / avg_sale_price) DESC) AS yield_rank FROM city_yield;

-- KPI 14 | Recursive CTE | Scenario: Project future price/sqft for a city assuming constant YoY growth.
WITH base AS (SELECT city, CAST(AVG(price_per_sqft) AS DECIMAL(18,2)) AS price_psf, AVG(yoy_price_appreciation_pct)/100.0 AS growth_rate FROM dbo.transactions_trends GROUP BY city),
forecast AS (SELECT city, price_psf, growth_rate, 0 AS yr_offset FROM base UNION ALL SELECT city, CAST(price_psf * (1 + growth_rate) AS DECIMAL(18,2)), growth_rate, yr_offset + 1 FROM forecast WHERE yr_offset < 5)
SELECT city, yr_offset AS years_ahead, ROUND(price_psf,2) AS projected_price_psf FROM forecast ORDER BY city, yr_offset;

-- KPI 15 | CASE WHEN | Scenario: Flag transactions where govt charges (stamp duty + registration) eat too much of the deal.
SELECT transaction_id, city, sale_price_inr, total_transaction_cost, CASE WHEN total_transaction_cost * 1.0 / sale_price_inr > 0.10 THEN 'High Cost Burden' WHEN total_transaction_cost * 1.0 / sale_price_inr BETWEEN 0.05 AND 0.10 THEN 'Moderate Burden' ELSE 'Low Burden' END AS cost_burden_flag
FROM dbo.transactions_trends;

-- KPI 16 | IIF() | Scenario: Flag stale listings that have been sitting unsold for too long.
SELECT listing_id, city, days_on_market, IIF(days_on_market > 180, 'Stale Listing', 'Active/Healthy') AS market_status
FROM dbo.residential_listings;

-- KPI 17 | DATENAME()/DATEPART() | Scenario: Identify which calendar months see faster sales (seasonality insight).
SELECT DATENAME(MONTH, listing_date) AS listing_month, AVG(days_on_market) AS avg_days_on_market
FROM dbo.residential_listings GROUP BY DATENAME(MONTH, listing_date), DATEPART(MONTH, listing_date) ORDER BY DATEPART(MONTH, listing_date);

-- KPI 18 | STRING_AGG()+TRIM()/UPPER() | Scenario: Clean inconsistent builder name casing/spacing, then find top builders by deal count.
SELECT UPPER(TRIM(builder_name)) AS builder_clean, COUNT(*) AS total_deals, (SELECT STRING_AGG(city, ', ') FROM (SELECT DISTINCT city FROM dbo.transactions_trends t2 WHERE UPPER(TRIM(t2.builder_name)) = UPPER(TRIM(t1.builder_name))) AS c) AS cities_active_in
FROM dbo.transactions_trends t1 GROUP BY UPPER(TRIM(builder_name)) ORDER BY total_deals DESC;

-- KPI 19 | Correlated Subquery | Scenario: Compare each property's rent against the city's average rent to flag overpriced units.
SELECT r.rental_id, r.city, r.monthly_rent_inr, (SELECT AVG(CAST(r2.monthly_rent_inr AS BIGINT)) FROM dbo.rental_market r2 WHERE r2.city = r.city) AS city_avg_rent
FROM dbo.rental_market r;

-- KPI 20 | STDEV() + Z-score | Scenario: Flag transactions whose cap rate is a statistical outlier vs the city norm (mispriced/distressed deals).
SELECT t.transaction_id, t.city, t.cap_rate_percent, ROUND((t.cap_rate_percent - cs.avg_cap) / cs.std_cap, 2) AS z_score
FROM dbo.transactions_trends t JOIN (SELECT city, AVG(cap_rate_percent) AS avg_cap, STDEV(cap_rate_percent) AS std_cap FROM dbo.transactions_trends GROUP BY city) cs ON t.city = cs.city;
