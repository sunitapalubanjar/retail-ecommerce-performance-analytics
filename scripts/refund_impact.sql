--1.  What % of revenue is lost to refunds?
SELECT
  ROUND(SUM(oir.refund_amount_usd)::numeric, 2) AS total_refund_usd,
  ROUND(SUM(oi.price_usd)::numeric, 2) AS total_item_revenue_usd,
  ROUND(
    SUM(oir.refund_amount_usd)::numeric / NULLIF(SUM(oi.price_usd)::numeric, 0),
    4
  ) AS pct_revenue_lost_to_refunds
FROM order_items oi
LEFT JOIN order_item_refunds oir
  ON oi.order_item_id = oir.order_item_refund_id;

--2.  Which products have the highest refund amounts?

SELECT
  oi.product_id,
  ROUND(SUM(oir.refund_amount_usd)::numeric, 2) AS total_refund_usd,
  ROUND(SUM(oi.price_usd)::numeric, 2) AS total_revenue_usd,
  ROUND(
    SUM(oir.refund_amount_usd)::numeric / NULLIF(SUM(oi.price_usd)::numeric, 0),
    4
  ) AS refund_rate
FROM order_items oi
LEFT JOIN order_item_refunds oir
  ON oi.order_item_id = oir.order_item_id
GROUP BY 1
ORDER BY refund_rate DESC;



-- 3. Are refunds increasing over time?
SELECT
  DATE_TRUNC('month', oir.created_at)::date AS month,
  ROUND(SUM(oir.refund_amount_usd)::numeric, 2) AS refund_amount_usd
FROM order_item_refunds oir
GROUP BY 1
ORDER BY 1;


-- 4. What is the refund rate (items refunded / items sold) by product?
SELECT
  oi.product_id,
  COUNT(oi.order_item_id) AS items_sold,
  COUNT(oir.order_item_id) AS items_refunded,
  ROUND(COUNT(oir.order_item_id)::numeric
    / NULLIF(COUNT(oi.order_item_id), 0)::numeric,4) AS refund_rate
FROM order_items oi
LEFT JOIN order_item_refunds oir
  ON oi.order_item_id = oir.order_item_id
GROUP BY 1
ORDER BY refund_rate DESC;



-- 5. How much revenue is lost to refunds each month (net revenue trend)?
SELECT
  DATE_TRUNC('month', o.created_at)::date AS month,
  SUM(o.price_usd) AS gross_revenue,
  COALESCE(r.refund_amount, 0) AS refunds,
  SUM(o.price_usd) - COALESCE(r.refund_amount, 0) AS net_revenue
FROM orders o
LEFT JOIN (
  SELECT
    DATE_TRUNC('month', created_at)::date AS month,
    SUM(refund_amount_usd) AS refund_amount
  FROM order_item_refunds
  GROUP BY 1
) r
  ON DATE_TRUNC('month', o.created_at)::date = r.month
GROUP BY 1, r.refund_amount
ORDER BY 1;


-- 6. Do certain channels have higher refund rates (quality of customers)?
SELECT
  ws.channel_group,
  COUNT(oi.order_item_id) AS items_sold,
  COUNT(oir.order_item_id) AS items_refunded,
  COUNT(oir.order_item_id)::float / NULLIF(COUNT(oi.order_item_id), 0) AS refund_rate
FROM website_sessions ws
JOIN orders o
  ON ws.website_session_id = o.website_session_id
JOIN order_items oi
  ON o.order_id = oi.order_id
LEFT JOIN order_item_refunds oir
  ON oi.order_item_id = oir.order_item_id
GROUP BY 1
ORDER BY refund_rate DESC;
