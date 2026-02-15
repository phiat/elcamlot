-- Elcamlot database schema
-- Extensions: TimescaleDB for time-series, pg_duckdb for analytics

CREATE EXTENSION IF NOT EXISTS timescaledb;

-- pg_duckdb for analytical queries (optional — skip if not installed)
DO $$ BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_duckdb;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_duckdb not available, skipping';
END $$;

CREATE TABLE IF NOT EXISTS vehicles (
  id BIGSERIAL PRIMARY KEY,
  make VARCHAR NOT NULL,
  model VARCHAR NOT NULL,
  year INTEGER NOT NULL,
  trim VARCHAR,
  body_style VARCHAR,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(make, model, year, trim)
);

CREATE TABLE IF NOT EXISTS price_snapshots (
  time TIMESTAMPTZ NOT NULL,
  vehicle_id BIGINT REFERENCES vehicles(id),
  price_cents BIGINT NOT NULL,
  mileage INTEGER,
  source VARCHAR,
  location VARCHAR,
  url TEXT,
  condition VARCHAR,
  listed_at TIMESTAMPTZ
);

SELECT create_hypertable('price_snapshots', 'time', if_not_exists => TRUE);

CREATE TABLE IF NOT EXISTS search_queries (
  id BIGSERIAL PRIMARY KEY,
  query TEXT NOT NULL,
  filters JSONB,
  result_count INTEGER,
  searched_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_vehicles_make_model ON vehicles(make, model);
CREATE INDEX IF NOT EXISTS idx_vehicles_year ON vehicles(year);
CREATE INDEX IF NOT EXISTS idx_vehicles_body_style ON vehicles(body_style);
CREATE INDEX IF NOT EXISTS idx_price_snapshots_vehicle_id ON price_snapshots(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_price_snapshots_source ON price_snapshots(source);
CREATE INDEX IF NOT EXISTS idx_price_snapshots_condition ON price_snapshots(condition);
CREATE INDEX IF NOT EXISTS idx_price_snapshots_listed_at ON price_snapshots(listed_at);
