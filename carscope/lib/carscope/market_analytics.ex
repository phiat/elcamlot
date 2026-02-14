defmodule Carscope.MarketAnalytics do
  @moduledoc """
  Market-level analytics using Postgres aggregation queries.

  Cross-vehicle market overviews, price trends, geographic pricing, and
  activity metrics. Uses TimescaleDB time_bucket for time-series bucketing
  and PERCENTILE_CONT for distribution stats.
  """
  alias Carscope.Repo

  @doc """
  Get average prices by make/model/year across all tracked vehicles.
  Returns list of maps with aggregated pricing data.
  """
  def market_overview(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    days_back = Keyword.get(opts, :days_back, 90)

    Repo.query!(
      """
      SELECT
        v.make,
        v.model,
        v.year,
        COUNT(DISTINCT p.vehicle_id) as listing_count,
        ROUND(AVG(p.price_cents))::bigint as avg_price,
        MIN(p.price_cents) as min_price,
        MAX(p.price_cents) as max_price,
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.price_cents))::bigint as median_price,
        ROUND(PERCENTILE_CONT(0.1) WITHIN GROUP (ORDER BY p.price_cents))::bigint as p10,
        ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY p.price_cents))::bigint as p90,
        ROUND(STDDEV(p.price_cents))::bigint as stddev
      FROM vehicles v
      JOIN price_snapshots p ON v.id = p.vehicle_id
      WHERE p.time > NOW() - make_interval(days => $1)
      GROUP BY v.make, v.model, v.year
      ORDER BY listing_count DESC
      LIMIT $2
      """,
      [days_back, limit]
    )
    |> rows_to_maps()
  end

  @doc """
  Get price trends over time for a specific make/model.
  Returns time-bucketed averages using TimescaleDB time_bucket.
  """
  def price_trends(make, model, opts \\ []) do
    bucket = validate_bucket(Keyword.get(opts, :bucket, "7 days"))
    days_back = Keyword.get(opts, :days_back, 365)

    Repo.query!(
      """
      SELECT
        time_bucket($1::interval, p.time) as period,
        v.year,
        COUNT(*) as sample_count,
        ROUND(AVG(p.price_cents))::bigint as avg_price,
        MIN(p.price_cents) as min_price,
        MAX(p.price_cents) as max_price
      FROM vehicles v
      JOIN price_snapshots p ON v.id = p.vehicle_id
      WHERE v.make = $2
        AND v.model = $3
        AND p.time > NOW() - make_interval(days => $4)
      GROUP BY period, v.year
      ORDER BY period DESC, v.year DESC
      """,
      [bucket, make, model, days_back]
    )
    |> rows_to_maps()
  end

  @doc """
  Compare a specific vehicle to market averages for the same make/model/year.
  Returns z-score, market average, and sample count.
  """
  def vehicle_market_position(vehicle_id) do
    Repo.query!(
      """
      WITH vehicle_info AS (
        SELECT v.id, v.make, v.model, v.year,
               AVG(p.price_cents) as vehicle_avg_price
        FROM vehicles v
        JOIN price_snapshots p ON v.id = p.vehicle_id
        WHERE v.id = $1
          AND p.time > NOW() - INTERVAL '90 days'
        GROUP BY v.id, v.make, v.model, v.year
      ),
      market AS (
        SELECT
          AVG(p.price_cents) as market_avg,
          STDDEV(p.price_cents) as market_stddev,
          COUNT(*) as market_count
        FROM vehicles v
        JOIN price_snapshots p ON v.id = p.vehicle_id
        JOIN vehicle_info vi ON v.make = vi.make AND v.model = vi.model AND v.year = vi.year
        WHERE p.time > NOW() - INTERVAL '90 days'
      )
      SELECT
        vi.make,
        vi.model,
        vi.year,
        ROUND(vi.vehicle_avg_price)::bigint as vehicle_avg_price,
        ROUND(m.market_avg)::bigint as market_avg,
        ROUND(m.market_stddev)::bigint as market_stddev,
        m.market_count,
        CASE WHEN m.market_stddev > 0
          THEN ROUND(((vi.vehicle_avg_price - m.market_avg) / m.market_stddev)::numeric, 2)
          ELSE 0
        END as z_score
      FROM vehicle_info vi, market m
      """,
      [vehicle_id]
    )
    |> rows_to_maps()
    |> List.first()
  end

  @doc """
  Get price variations by location for a make/model.
  """
  def geographic_pricing(make, model, opts \\ []) do
    days_back = Keyword.get(opts, :days_back, 90)

    Repo.query!(
      """
      SELECT
        p.location,
        COUNT(*) as listing_count,
        ROUND(AVG(p.price_cents))::bigint as avg_price,
        MIN(p.price_cents) as min_price,
        MAX(p.price_cents) as max_price
      FROM vehicles v
      JOIN price_snapshots p ON v.id = p.vehicle_id
      WHERE v.make = $1
        AND v.model = $2
        AND p.location IS NOT NULL
        AND p.time > NOW() - make_interval(days => $3)
      GROUP BY p.location
      HAVING COUNT(*) >= 3
      ORDER BY listing_count DESC
      """,
      [make, model, days_back]
    )
    |> rows_to_maps()
  end

  @doc """
  Get daily listing activity metrics.
  """
  def activity_metrics(opts \\ []) do
    days_back = Keyword.get(opts, :days_back, 30)

    Repo.query!(
      """
      SELECT
        DATE(time) as date,
        COUNT(*) as new_listings,
        COUNT(DISTINCT vehicle_id) as unique_vehicles,
        COUNT(DISTINCT source) as sources_count,
        ROUND(AVG(price_cents))::bigint as avg_price
      FROM price_snapshots
      WHERE time > NOW() - make_interval(days => $1)
      GROUP BY DATE(time)
      ORDER BY date DESC
      """,
      [days_back]
    )
    |> rows_to_maps()
  end

  @doc """
  Refresh the materialized view cache.
  Run periodically (e.g. every hour) via MarketStatsRefresher.
  """
  def refresh_market_stats do
    Repo.query!("REFRESH MATERIALIZED VIEW CONCURRENTLY market_stats")
    :ok
  rescue
    # View may not exist yet or CONCURRENTLY may fail without unique index
    Postgrex.Error ->
      Repo.query!("REFRESH MATERIALIZED VIEW market_stats")
      :ok
  end

  @doc """
  Get cached market stats from materialized view (fast).
  """
  def cached_market_overview(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Repo.query!(
      "SELECT * FROM market_stats ORDER BY listing_count DESC LIMIT $1",
      [limit]
    )
    |> rows_to_maps()
  end

  # --- Helpers ---

  defp rows_to_maps(%{columns: columns, rows: rows}) do
    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new()
    end)
  end

  defp rows_to_maps(_), do: []

  @valid_buckets ~w(1 day 7 days 14 days 1 month)
  defp validate_bucket(bucket) when bucket in @valid_buckets, do: bucket
  defp validate_bucket(_), do: "7 days"
end
