--1.  Which products drive the most orders and revenue?
SELECT
  oi.product_id,
  p.product_name,
  COUNT(DISTINCT oi.order_id) AS orders_with_product,
  ROUND(SUM(oi.price_usd)::numeric, 2) AS product_revenue
FROM order_items oi
LEFT JOIN products p
  ON oi.product_id = p.product_id
GROUP BY 1,2
ORDER BY product_revenue DESC;


--2.  Which products have the highest average selling price / revenue per order?
SELECT
  oi.product_id,
  p.product_name,
  COUNT(DISTINCT oi.order_id) AS orders_with_product,
  SUM(oi.price_usd) AS product_revenue,
  SUM(oi.price_usd) / COUNT(DISTINCT oi.order_id) AS revenue_per_order_with_product
FROM order_items oi
LEFT JOIN products p
  ON oi.product_id = p.product_id
GROUP BY 1,2
ORDER BY revenue_per_order_with_product DESC;


-- 3. Are there product mix shifts over time that explain revenue per order changes?
WITH monthly_product AS (
  SELECT
    DATE_TRUNC('month', o.created_at)::date AS month,
    oi.product_id,
    ROUND(SUM(oi.price_usd)::numeric, 2) AS product_revenue
  FROM orders o
  JOIN order_items oi
    ON o.order_id = oi.order_id
  GROUP BY 1,2
),
monthly_total AS (
  SELECT
    month,
    SUM(product_revenue) AS total_revenue
  FROM monthly_product
  GROUP BY 1
)
SELECT
  mp.month,
  mp.product_id,
  mp.product_revenue,
  mt.total_revenue,
  ROUND((mp.product_revenue / mt.total_revenue),2) AS revenue_share
FROM monthly_product mp
JOIN monthly_total mt
  ON mp.month = mt.month
ORDER BY mp.month, revenue_share DESC;
