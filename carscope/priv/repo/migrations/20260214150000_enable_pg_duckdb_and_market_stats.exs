defmodule Carscope.Repo.Migrations.EnablePgDuckdbAndMarketStats do
  use Ecto.Migration

  def up do
    # pg_duckdb extension — requires package installed in container
    execute("CREATE EXTENSION IF NOT EXISTS pg_duckdb")

    # Materialized view for cached market stats
    execute("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS market_stats AS
    SELECT
      v.make,
      v.model,
      v.year,
      COUNT(DISTINCT p.vehicle_id) as listing_count,
      ROUND(AVG(p.price_cents))::bigint as avg_price,
      MIN(p.price_cents) as min_price,
      MAX(p.price_cents) as max_price,
      ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.price_cents))::bigint as median_price,
      ROUND(STDDEV(p.price_cents))::bigint as price_stddev,
      MAX(p.time) as last_updated
    FROM vehicles v
    JOIN price_snapshots p ON v.id = p.vehicle_id
    WHERE p.time > NOW() - INTERVAL '90 days'
    GROUP BY v.make, v.model, v.year
    """)

    execute("CREATE INDEX IF NOT EXISTS idx_market_stats_make_model ON market_stats(make, model)")
    execute("CREATE INDEX IF NOT EXISTS idx_market_stats_year ON market_stats(year)")
  end

  def down do
    execute("DROP MATERIALIZED VIEW IF EXISTS market_stats")
    execute("DROP EXTENSION IF EXISTS pg_duckdb")
  end
end
