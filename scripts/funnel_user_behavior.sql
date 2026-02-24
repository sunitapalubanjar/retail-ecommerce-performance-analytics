-- Funnel & behavior (pageviews)

-- Which landing pages generate the most sessions and the best conversion rate?ø
WITH first_pageview AS (
  SELECT
    wp.website_session_id,
    wp.pageview_url AS landing_page,
    ROW_NUMBER() OVER (
      PARTITION BY wp.website_session_id
      ORDER BY wp.created_at, wp.website_pageview_id
    ) AS rn
  FROM website_pageviews wp
),
landing_sessions AS (
  SELECT
    fp.website_session_id,
    fp.landing_page
  FROM first_pageview fp
  WHERE fp.rn = 1
),
session_orders AS (
  SELECT DISTINCT website_session_id
  FROM orders
)
SELECT
  ls.landing_page,
  COUNT(DISTINCT ls.website_session_id) AS sessions,
  COUNT(DISTINCT so.website_session_id) AS orders,
  ROUND(COUNT(DISTINCT so.website_session_id)::numeric / COUNT(DISTINCT ls.website_session_id), 3) AS conversion_rate
FROM landing_sessions ls
LEFT JOIN session_orders so
  ON ls.website_session_id = so.website_session_id
GROUP BY 1
ORDER BY sessions DESC;




-- What is the average pageviews per session by channel and device?
WITH pv_per_session AS (
		SELECT
			wp.website_session_id,
			COUNT(*) AS pageviews
		FROM website_pageviews wp
		GROUP BY 1
	)
SELECT
	ws.channel_group,
	ws.device_type,
	COUNT(DISTINCT ws.website_session_id) AS sessions,
	AVG(pv.pageviews)::numeric(10, 2) AS avg_pageviews_per_session
FROM website_sessions ws
	JOIN pv_per_session pv
	USING (website_session_id)
	GROUP BY 1,2
ORDER BY 1,2;




-- Where do users drop off most in the funnel (landing → product → cart → checkout)?
WITH session_steps AS (
  SELECT
    wp.website_session_id,
    MAX(CASE WHEN wp.pageview_url = '/products' THEN 1 ELSE 0 END) AS reached_product,
    MAX(CASE WHEN wp.pageview_url = '/cart' THEN 1 ELSE 0 END) AS reached_cart,
    MAX(CASE WHEN wp.pageview_url IN ('/shipping', '/billing', '/checkout') THEN 1 ELSE 0 END) AS reached_checkout,
    MAX(CASE WHEN wp.pageview_url = '/thank-you-for-your-order' THEN 1 ELSE 0 END) AS reached_thankyou
  FROM website_pageviews wp
  GROUP BY 1
),
base AS (
  SELECT
    COUNT(*) AS sessions,
    SUM(reached_product) AS to_product,
    SUM(reached_cart) AS to_cart,
    SUM(reached_checkout) AS to_checkout,
    SUM(reached_thankyou) AS to_thankyou
  FROM session_steps
)
SELECT
  sessions,
  to_product,
  to_cart,
  to_checkout,
  to_thankyou,

  -- drop counts
  (sessions - to_product) AS drop_before_product,
  (to_product - to_cart) AS drop_before_cart,
  (to_cart - to_checkout) AS drop_before_checkout,
  (to_checkout - to_thankyou) AS drop_before_thankyou,

  -- drop-off rates (%)
  ROUND((sessions - to_product)::numeric / NULLIF(sessions, 0), 4) AS drop_before_product_rate,
  ROUND((to_product - to_cart)::numeric / NULLIF(to_product, 0), 4) AS drop_before_cart_rate,
  ROUND((to_cart - to_checkout)::numeric / NULLIF(to_cart, 0), 4) AS drop_before_checkout_rate,
  ROUND((to_checkout - to_thankyou)::numeric / NULLIF(to_checkout, 0), 4) AS drop_before_thankyou_rate

FROM base;
