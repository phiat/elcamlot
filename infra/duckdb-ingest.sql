-- Bulk CSV/Parquet ingest via pg_duckdb
-- Usage: Push file to container /tmp/, then run with table parameter
--
-- For price_bars:
--   \set target_table 'price_bars'
--   \set import_file '/tmp/import.csv'
--   \i /tmp/duckdb-ingest.sql
--
-- For price_snapshots:
--   \set target_table 'price_snapshots'
--   \set import_file '/tmp/import.csv'
--   \i /tmp/duckdb-ingest.sql

-- ============================================================
-- price_bars ingest
-- CSV columns: time, symbol, open_cents, high_cents, low_cents,
--              close_cents, volume, timeframe
-- ============================================================

CREATE TEMP TABLE IF NOT EXISTS _import_bars (
  time        TIMESTAMPTZ,
  symbol      VARCHAR,
  open_cents  BIGINT,
  high_cents  BIGINT,
  low_cents   BIGINT,
  close_cents BIGINT,
  volume      BIGINT,
  timeframe   VARCHAR
);

TRUNCATE _import_bars;

INSERT INTO _import_bars
SELECT * FROM read_csv(
  :'import_file',
  columns := {
    'time':        'TIMESTAMPTZ',
    'symbol':      'VARCHAR',
    'open_cents':  'BIGINT',
    'high_cents':  'BIGINT',
    'low_cents':   'BIGINT',
    'close_cents': 'BIGINT',
    'volume':      'BIGINT',
    'timeframe':   'VARCHAR'
  },
  header := true,
  auto_detect := false
);

-- Resolve symbol -> instrument_id, skip unknown symbols
INSERT INTO price_bars (time, instrument_id, open_cents, high_cents, low_cents, close_cents, volume, timeframe)
SELECT
  ib.time,
  i.id,
  ib.open_cents,
  ib.high_cents,
  ib.low_cents,
  ib.close_cents,
  ib.volume,
  COALESCE(ib.timeframe, '1D')
FROM _import_bars ib
JOIN instruments i ON i.symbol = ib.symbol
ON CONFLICT DO NOTHING;

DO $$ BEGIN
  RAISE NOTICE 'price_bars import complete: % rows staged',
    (SELECT count(*) FROM _import_bars);
END $$;

DROP TABLE _import_bars;


-- ============================================================
-- price_snapshots ingest
-- CSV columns: time, vehicle_make, vehicle_model, vehicle_year,
--              vehicle_trim, price_cents, mileage, source,
--              location, url, condition
-- ============================================================

CREATE TEMP TABLE IF NOT EXISTS _import_snapshots (
  time          TIMESTAMPTZ,
  vehicle_make  VARCHAR,
  vehicle_model VARCHAR,
  vehicle_year  INTEGER,
  vehicle_trim  VARCHAR,
  price_cents   BIGINT,
  mileage       INTEGER,
  source        VARCHAR,
  location      VARCHAR,
  url           TEXT,
  condition     VARCHAR
);

TRUNCATE _import_snapshots;

INSERT INTO _import_snapshots
SELECT * FROM read_csv(
  :'import_file',
  columns := {
    'time':          'TIMESTAMPTZ',
    'vehicle_make':  'VARCHAR',
    'vehicle_model': 'VARCHAR',
    'vehicle_year':  'INTEGER',
    'vehicle_trim':  'VARCHAR',
    'price_cents':   'BIGINT',
    'mileage':       'INTEGER',
    'source':        'VARCHAR',
    'location':      'VARCHAR',
    'url':           'TEXT',
    'condition':     'VARCHAR'
  },
  header := true,
  auto_detect := false
);

-- Resolve vehicle identity -> vehicle_id, skip unknown vehicles
INSERT INTO price_snapshots (time, vehicle_id, price_cents, mileage, source, location, url, condition)
SELECT
  s.time,
  v.id,
  s.price_cents,
  s.mileage,
  s.source,
  s.location,
  s.url,
  s.condition
FROM _import_snapshots s
JOIN vehicles v
  ON v.make  = s.vehicle_make
 AND v.model = s.vehicle_model
 AND v.year  = s.vehicle_year
 AND COALESCE(v.trim, '') = COALESCE(s.vehicle_trim, '')
ON CONFLICT DO NOTHING;

DO $$ BEGIN
  RAISE NOTICE 'price_snapshots import complete: % rows staged',
    (SELECT count(*) FROM _import_snapshots);
END $$;

DROP TABLE _import_snapshots;
