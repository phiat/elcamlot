# CarScope

Car research & price intelligence platform. Search for vehicles, track prices over time, and get market analytics.

## Architecture

```
Phoenix Web App (host)
├── LiveView UI / Dashboard
├── Brave Search API client
├── Ecto → Postgres (OLTP + stats)
└── HTTP client → OCaml Analytics

OCaml Analytics Service (Incus container)
├── REST API (Dream)
├── Deal scoring & depreciation curves
├── Outlier detection (IQR + MAD)
├── Data quality grading (A-F)
└── Histogram / binned distribution

Postgres (Incus container)
├── Core data (vehicles, snapshots, users)
├── TimescaleDB (time-series bucketing)
├── Aggregation queries (AVG, percentiles, STDDEV)
└── pg_duckdb (installed, ad-hoc analysis)
```

## What Each Layer Does

**Postgres** — source of truth + aggregation. Stores all vehicles, price snapshots, search logs, and users. Handles CRUD, filtering, JOINs, and statistical aggregates (AVG, MIN/MAX, PERCENTILE_CONT, STDDEV). TimescaleDB provides `time_bucket()` for time-series queries. Materialized views cache market overviews.

**OCaml (Dream)** — compute that Postgres can't easily do. Exponential/linear depreciation curve fitting with R². Weighted deal scoring (percentile rank + distance blending). Outlier detection via modified Z-scores (MAD) and IQR fencing. Data quality grading with skewness, kurtosis, and coefficient of variation. Histogram binning with multimodal detection.

**pg_duckdb** — installed in the Postgres container for ad-hoc analytical queries and future bulk data ingest. Currently not used by the application directly — all live queries use standard Postgres + TimescaleDB. See notes below.

## pg_duckdb: Pros, Cons, and Use Cases

pg_duckdb embeds DuckDB's columnar query engine inside Postgres, letting you run OLAP-style queries without a separate warehouse.

**Pros:**
- Columnar scans are 10-100x faster than row-based Postgres for aggregations over large datasets
- Can query external Parquet/CSV files directly (useful for bulk data ingest from scrapers)
- No separate service to deploy — runs as a Postgres extension
- Same SQL interface, same connection, same transactions
- Good for periodic batch analytics (e.g., weekly market reports)

**Cons:**
- Adds memory overhead to the Postgres container
- Not useful at small data volumes — Postgres is already fast enough for <100K rows
- Extension maturity — pg_duckdb is newer and less battle-tested than pure Postgres
- Can't use TimescaleDB hypertable features and DuckDB columnar on the same table
- Query planner interaction is opaque — hard to know when DuckDB path kicks in

**When it would matter for CarScope:**
- Bulk importing price data from external CSV/Parquet dumps (e.g., historical auction data)
- Cross-market aggregations across millions of snapshots
- Ad-hoc analysis in psql without spinning up a Jupyter notebook
- Currently overkill for our data volume — keeping it installed for future use

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Web app | Elixir 1.19 / Phoenix 1.8 LiveView |
| Analytics | OCaml 5.2.1 + Dream web framework |
| Database | Postgres 16 + TimescaleDB + pg_duckdb |
| Search | Brave Search API |
| Containers | Incus (not Docker) |

## How It Works

1. Search for a car (e.g., "2021 Toyota Camry")
2. Brave Search fetches current listings/prices from the web
3. Prices are stored as time-series data in Postgres/TimescaleDB
4. Postgres computes stats (avg, median, percentiles, std dev)
5. OCaml service computes deal scores, depreciation curves, outliers, data quality
6. Phoenix LiveView renders dashboard with charts and recommendations

## Setup

```bash
# Install dependencies via mise
mise install

# Provision Incus containers (Postgres + OCaml analytics)
./infra/setup-pg.sh
./infra/setup-ocaml.sh

# Start Phoenix app
cd carscope && mix deps.get && mix phx.server

# Or start everything at once
./scripts/dev.sh
```

## Project Structure

```
tc-lander/
├── infra/          # Incus container management scripts
├── carscope/       # Phoenix application
├── analytics/      # OCaml analytics service
└── scripts/        # Dev workflow scripts
```

## Learning Goals

- Testcontainers-style workflows using Incus (not Docker)
- Custom container lifecycle management from Elixir
- TimescaleDB for time-series price data
- pg_duckdb for analytical queries (ad-hoc for now)
- OCaml for numerical analysis (curve fitting, outlier detection, scoring)
