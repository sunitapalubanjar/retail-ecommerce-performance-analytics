---------------
-- A. Overall Business
----------------
--1.  Is the overall number of orders increasing over time?
----------------

SELECT
  DATE_TRUNC('month', o.created_at)::date AS month,
  COUNT(DISTINCT o.order_id) AS orders
FROM orders o
GROUP BY 1
ORDER BY 1;



-----------------
-- 2. Is total revenue growing compared to earlier periods?
-----------------
SELECT
   DATE_TRUNC('month', o.created_at)::date AS month,
  SUM(o.price_usd) AS total_revenue
FROM orders o
GROUP BY 1
ORDER BY 1;


-----------------
-- 3. Is the average conversion rate stable, improving, or declining?
---------------------

SELECT
	DATE_TRUNC('month', ws.created_at)::date AS MONTH,
	COUNT(DISTINCT ws.website_session_id) AS sessions,
	COUNT(DISTINCT o.order_id) AS orders,
	COUNT(DISTINCT o.order_id)::float / COUNT(DISTINCT ws.website_session_id) AS conversion_rate
FROM website_sessions AS ws
	LEFT JOIN orders AS o 
	ON o.website_session_id = ws.website_session_id
GROUP BY 1 
ORDER BY 1;

------------
-- B. Traffic vs Sales Quality
------------
--4.  Are orders growing at the same pace as website sessions?
-- → Distinguishes traffic-driven vs conversion-driven growth.
-- mom = month over month growth percentage
-- mom_growth = current - previous  / previous

-- April sessions = 15,000
-- March sessions = 12,000

-- (15,000 - 12,000) / 12,000 = 0.25 → 25% growth
---------------


WITH monthly AS (
  SELECT
    DATE_TRUNC('month', ws.created_at)::date AS month,
    COUNT(DISTINCT ws.website_session_id) AS sessions,
    COUNT(DISTINCT o.order_id) AS orders
  FROM website_sessions ws
  LEFT JOIN orders o
    ON ws.website_session_id = o.website_session_id
  GROUP BY 1
),

mom AS (
  SELECT
    month,
    sessions,
    orders,
    (sessions - LAG(sessions) OVER (ORDER BY month))::float / NULLIF(LAG(sessions) OVER (ORDER BY month), 0) AS sessions_mom_growth,   -- if current value 0 then result becomes null
    (orders - LAG(orders) OVER (ORDER BY month))::float / NULLIF(LAG(orders) OVER (ORDER BY month), 0) AS orders_mom_growth
  FROM monthly
)


SELECT *
FROM mom
ORDER BY month;



--------------
--5.  Has the business become better at converting visitors into customers over time?
-- compare conversion in first 3 months and last 3 months
--------------
WITH monthly AS (
  SELECT
    DATE_TRUNC('month', ws.created_at)::date AS month,
    COUNT(DISTINCT ws.website_session_id) AS sessions,
    COUNT(DISTINCT o.order_id) AS orders,
    COUNT(DISTINCT o.order_id)::float / COUNT(DISTINCT ws.website_session_id) AS conversion_rate
  FROM website_sessions ws
  LEFT JOIN orders o
    ON ws.website_session_id = o.website_session_id
  GROUP BY 1
),
bounds AS (
  SELECT MIN(month) AS min_month, MAX(month) AS max_month FROM monthly
),
labeled AS (
  SELECT
    m.*,
    CASE
      WHEN m.month < (SELECT min_month FROM bounds) + INTERVAL '3 months' THEN 'first_3_months'
      WHEN m.month >= (SELECT max_month FROM bounds) - INTERVAL '2 months' THEN 'last_3_months'
      ELSE 'middle'
    END AS period_bucket
  FROM monthly m
)
SELECT
  period_bucket,
  SUM(orders) AS orders,
  SUM(sessions) AS sessions,
  SUM(orders)::float / NULLIF(SUM(sessions), 0) AS conversion_rate
FROM labeled
WHERE period_bucket IN ('first_3_months', 'last_3_months')
GROUP BY 1
ORDER BY 1;

 



-----------------
-- C. Marketing Channel Effectiveness
----------------

-- 6. Which marketing channel brings in the most website traffic?
--------------------

SELECT
	channel_group,
	COUNT(DISTINCT website_session_id) AS sessions
FROM website_sessions
GROUP BY 1
ORDER BY sessions DESC;


----------
-- 7. Which marketing channel generates the most orders?
----------
SELECT
	ws.channel_group,
	COUNT(DISTINCT o.order_id) AS orders
FROM
	website_sessions AS ws
	LEFT JOIN orders AS o USING (website_session_id)
GROUP BY channel_group
ORDER BY orders dESC;



------------
-- 8. Which marketing channel produces the highest total revenue?
-----------
SELECT
  ws.channel_group,
  ROUND(COALESCE(SUM(o.price_usd), 0) ::numeric, 2) AS revenue
FROM website_sessions ws
LEFT JOIN orders o
  USING (website_session_id)
GROUP BY 1
ORDER BY revenue DESC;



-----------
-- 9. Which marketing channel has the highest conversion rate?
--------------
SELECT
	ws.channel_group,
	COUNT(DISTINCT o.order_id) AS orders,
	COUNT(DISTINCT ws.website_session_id) AS sessions,
	COUNT(DISTINCT o.order_id)::float / COUNT(DISTINCT ws.website_session_id) AS conversion_rate
FROM
	website_sessions ws
	LEFT JOIN orders o 
	USING (website_session_id)
GROUP BY 1
ORDER BY conversion_rate DESC;



-------
-- D. Revenue & Efficiency
---------------
-- 10. Which channel generates the most revenue per session?
-----------------
SELECT
	ws.channel_group,
	ROUND(COALESCE(SUM(o.price_usd), 0)::numeric, 2) AS revenue,
	COALESCE(SUM(o.price_usd), 0) / COUNT(DISTINCT ws.website_session_id) AS revenue_per_session
FROM website_sessions ws
	LEFT JOIN orders o 
	USING (website_session_id)
GROUP BY 1
ORDER BY revenue_per_session DESC;




----------
-- 11. Is the channel with the most traffic also the most valuable?
-----------
WITH
	base AS (
		SELECT
			ws.channel_group,
			COUNT(DISTINCT o.order_id) AS orders,
			COUNT(DISTINCT ws.website_session_id) AS sessions,
			COALESCE(SUM(o.price_usd)) AS revenue
		FROM
			website_sessions ws
			LEFT JOIN orders o USING (website_session_id)
		GROUP BY 1
	),
	channel_kpis AS (
		SELECT
			channel_group,
			orders,
			sessions,
			revenue,
			orders::float / NULLIF(sessions, 0) AS conversion_rate,
			revenue / NULLIF(sessions, 0) AS revenue_per_session
		FROM base
	),
	top_sessions AS (
		SELECT
			channel_group AS top_traffic_channel
		FROM channel_kpis
		ORDER BY sessions DESC
		LIMIT 1
	),
	top_rps AS (
		SELECT
			channel_group AS top_value_channel
		FROM channel_kpis
		ORDER BY revenue_per_session DESC
		LIMIT 1
	)
SELECT
	(SELECT top_traffic_channel FROM top_sessions) AS top_traffic_channel,
	(SELECT top_value_channel FROM top_rps) AS top_value_channel;




------------
-- E. Risk & Decision Support
-------------

-- 12. Is the business overly dependent on a single marketing channel for revenue?
-- → Identifies concentration risk.
---------------


WITH
	channel_rev AS (
		SELECT
			ws.channel_group,
			ROUND(COALESCE(SUM(o.price_usd), 0) :: numeric, 2) AS revenue
		FROM website_sessions ws
			LEFT JOIN orders o
			USING (website_session_id)
		GROUP BY 1
	),
	tot AS (
		SELECT
			SUM(revenue) AS total_revenue
		FROM channel_rev
	)
	
SELECT
	cr.channel_group,
	cr.revenue,
	ROUND(cr.revenue / NULLIF(t.total_revenue, 0), 2) AS revenue_share
FROM channel_rev cr 
CROSS JOIN tot t
ORDER BY revenue_share DESC;


---------------------
-- 13. Which channel is underperforming across traffic, conversion, and revenue?
--------------------



WITH channel_kpis AS (
  SELECT
    ws.channel_group,
    COUNT(DISTINCT ws.website_session_id) AS sessions,
    COUNT(DISTINCT o.order_id) AS orders,
    COUNT(DISTINCT o.order_id)::float / COUNT(DISTINCT ws.website_session_id) AS conversion_rate,
    COALESCE(SUM(o.price_usd), 0) / COUNT(DISTINCT ws.website_session_id) AS revenue_per_session
  FROM website_sessions ws
  LEFT JOIN orders o
    ON ws.website_session_id = o.website_session_id
  GROUP BY 1
),
ranked AS (
  SELECT
    *,
    RANK() OVER (ORDER BY sessions ASC) AS sessions_rank_low,
    RANK() OVER (ORDER BY conversion_rate ASC) AS cvr_rank_low,
    RANK() OVER (ORDER BY revenue_per_session ASC) AS rps_rank_low
  FROM channel_kpis
)
SELECT
  channel_group,
  sessions,
  conversion_rate,
  revenue_per_session,
  (sessions_rank_low + cvr_rank_low + rps_rank_low) AS underperformance_score
FROM ranked
ORDER BY underperformance_score DESC;



