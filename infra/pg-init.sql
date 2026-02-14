-- CarScope database schema
-- Extensions: TimescaleDB for time-series, pg_duckdb for analytics

CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE IF NOT EXISTS vehicles (
  id BIGSERIAL PRIMARY KEY,
  make VARCHAR NOT NULL,
  model VARCHAR NOT NULL,
  year INTEGER NOT NULL,
  trim VARCHAR,
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
  url TEXT
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
CREATE INDEX IF NOT EXISTS idx_price_snapshots_vehicle_id ON price_snapshots(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_price_snapshots_source ON price_snapshots(source);
