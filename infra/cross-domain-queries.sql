-- Cross-domain analytical queries: vehicles vs financial markets
-- Requires tables: vehicles, price_snapshots, instruments, price_bars

-- ============================================================
-- 1. Monthly vehicle depreciation vs SPY returns
-- ============================================================

\echo '=== Monthly Vehicle Depreciation vs SPY Returns ==='

WITH monthly_vehicle AS (
  SELECT
    date_trunc('month', ps.time) AS month,
    round(avg(ps.price_cents) / 100.0, 2) AS avg_price,
    round(
      (avg(ps.price_cents) - lag(avg(ps.price_cents)) OVER (ORDER BY date_trunc('month', ps.time)))
      / NULLIF(lag(avg(ps.price_cents)) OVER (ORDER BY date_trunc('month', ps.time)), 0)
      * 100, 2
    ) AS vehicle_pct_change
  FROM price_snapshots ps
  GROUP BY date_trunc('month', ps.time)
),
monthly_spy AS (
  SELECT
    date_trunc('month', pb.time) AS month,
    (last(pb.close_cents, pb.time) - first(pb.close_cents, pb.time))::numeric
      / NULLIF(first(pb.close_cents, pb.time), 0) * 100 AS spy_pct_return
  FROM price_bars pb
  JOIN instruments i ON i.id = pb.instrument_id
  WHERE i.symbol = 'SPY'
    AND pb.timeframe = '1D'
  GROUP BY date_trunc('month', pb.time)
)
SELECT
  to_char(v.month, 'YYYY-MM') AS month,
  v.avg_price AS avg_vehicle_price,
  v.vehicle_pct_change AS vehicle_chg_pct,
  round(s.spy_pct_return, 2) AS spy_return_pct
FROM monthly_vehicle v
LEFT JOIN monthly_spy s ON s.month = v.month
WHERE v.vehicle_pct_change IS NOT NULL
ORDER BY v.month;


-- ============================================================
-- 2. Correlation: vehicle price drops during market downturns
-- ============================================================

\echo ''
\echo '=== Months Where Both Markets and Vehicles Declined ==='

WITH monthly_vehicle AS (
  SELECT
    date_trunc('month', ps.time) AS month,
    avg(ps.price_cents) AS avg_cents,
    round(
      (avg(ps.price_cents) - lag(avg(ps.price_cents)) OVER (ORDER BY date_trunc('month', ps.time)))
      / NULLIF(lag(avg(ps.price_cents)) OVER (ORDER BY date_trunc('month', ps.time)), 0)
      * 100, 2
    ) AS vehicle_chg
  FROM price_snapshots ps
  GROUP BY date_trunc('month', ps.time)
),
monthly_market AS (
  SELECT
    date_trunc('month', pb.time) AS month,
    round(
      (last(pb.close_cents, pb.time) - first(pb.close_cents, pb.time))::numeric
      / NULLIF(first(pb.close_cents, pb.time), 0) * 100, 2
    ) AS market_chg
  FROM price_bars pb
  JOIN instruments i ON i.id = pb.instrument_id
  WHERE i.symbol = 'SPY' AND pb.timeframe = '1D'
  GROUP BY date_trunc('month', pb.time)
)
SELECT
  to_char(v.month, 'YYYY-MM') AS month,
  v.vehicle_chg AS vehicle_pct,
  m.market_chg AS spy_pct,
  CASE
    WHEN v.vehicle_chg < -2 AND m.market_chg < -2 THEN 'BOTH DOWN'
    WHEN v.vehicle_chg < -2 THEN 'VEHICLES ONLY'
    WHEN m.market_chg < -2 THEN 'MARKET ONLY'
    ELSE 'STABLE'
  END AS regime
FROM monthly_vehicle v
JOIN monthly_market m ON m.month = v.month
WHERE v.vehicle_chg IS NOT NULL
ORDER BY v.month;


-- ============================================================
-- 3. Best & worst months for car buying vs stock market
-- ============================================================

\echo ''
\echo '=== Best Months to Buy Cars (lowest avg price) vs SPY Performance ==='

WITH vehicle_by_cal_month AS (
  SELECT
    extract(month FROM ps.time)::int AS cal_month,
    to_char(ps.time, 'Mon') AS month_name,
    round(avg(ps.price_cents) / 100.0, 2) AS avg_price,
    count(*) AS snapshot_count
  FROM price_snapshots ps
  GROUP BY extract(month FROM ps.time), to_char(ps.time, 'Mon')
),
spy_by_cal_month AS (
  SELECT
    extract(month FROM pb.time)::int AS cal_month,
    round(avg(
      (pb.close_cents - pb.open_cents)::numeric / NULLIF(pb.open_cents, 0) * 100
    ), 3) AS avg_daily_return_pct,
    count(*) AS bar_count
  FROM price_bars pb
  JOIN instruments i ON i.id = pb.instrument_id
  WHERE i.symbol = 'SPY' AND pb.timeframe = '1D'
  GROUP BY extract(month FROM pb.time)
)
SELECT
  v.month_name,
  v.avg_price AS avg_car_price,
  v.snapshot_count AS car_samples,
  s.avg_daily_return_pct AS spy_avg_daily_ret,
  s.bar_count AS spy_trading_days,
  rank() OVER (ORDER BY v.avg_price ASC) AS buy_rank
FROM vehicle_by_cal_month v
LEFT JOIN spy_by_cal_month s ON s.cal_month = v.cal_month
ORDER BY v.cal_month;


-- ============================================================
-- 4. Rolling 3-month vehicle depreciation vs market volatility
-- ============================================================

\echo ''
\echo '=== Rolling 3-Month Depreciation vs Market Volatility ==='

WITH monthly_vehicle AS (
  SELECT
    date_trunc('month', ps.time) AS month,
    avg(ps.price_cents) AS avg_cents
  FROM price_snapshots ps
  GROUP BY date_trunc('month', ps.time)
),
vehicle_rolling AS (
  SELECT
    month,
    round(
      (avg_cents - lag(avg_cents, 3) OVER (ORDER BY month))
      / NULLIF(lag(avg_cents, 3) OVER (ORDER BY month), 0) * 100, 2
    ) AS depreciation_3m_pct
  FROM monthly_vehicle
),
market_vol AS (
  SELECT
    date_trunc('month', pb.time) AS month,
    round(stddev(
      (pb.close_cents - pb.open_cents)::numeric / NULLIF(pb.open_cents, 0) * 100
    ), 3) AS daily_vol_pct,
    count(*) AS trading_days
  FROM price_bars pb
  JOIN instruments i ON i.id = pb.instrument_id
  WHERE i.symbol = 'SPY' AND pb.timeframe = '1D'
  GROUP BY date_trunc('month', pb.time)
)
SELECT
  to_char(vr.month, 'YYYY-MM') AS month,
  vr.depreciation_3m_pct AS car_depr_3m,
  mv.daily_vol_pct AS spy_daily_vol,
  mv.trading_days
FROM vehicle_rolling vr
LEFT JOIN market_vol mv ON mv.month = vr.month
WHERE vr.depreciation_3m_pct IS NOT NULL
ORDER BY vr.month;


-- ============================================================
-- 5. Per-model depreciation vs sector ETF
-- ============================================================

\echo ''
\echo '=== Per-Model Price Trend (Top 10 by Data Points) ==='

SELECT
  v.year,
  v.make,
  v.model,
  count(ps.*) AS snapshots,
  round(min(ps.price_cents) / 100.0, 2) AS min_price,
  round(max(ps.price_cents) / 100.0, 2) AS max_price,
  round(avg(ps.price_cents) / 100.0, 2) AS avg_price,
  round(
    (last(ps.price_cents, ps.time) - first(ps.price_cents, ps.time))::numeric
    / NULLIF(first(ps.price_cents, ps.time), 0) * 100, 2
  ) AS total_chg_pct,
  min(ps.time)::date AS first_seen,
  max(ps.time)::date AS last_seen
FROM price_snapshots ps
JOIN vehicles v ON v.id = ps.vehicle_id
GROUP BY v.id, v.year, v.make, v.model
HAVING count(ps.*) >= 3
ORDER BY count(ps.*) DESC
LIMIT 10;
