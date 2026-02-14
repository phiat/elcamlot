# CarScope

Car research & price intelligence platform. Search for vehicles, track prices over time, and get market analytics.

## Architecture

```
Phoenix Web App (host)
├── LiveView UI / Dashboard
├── Brave Search API client
├── Ecto → Postgres
└── HTTP client → OCaml Analytics

OCaml Analytics Service (Incus container)
├── REST API (Dream)
├── Price statistics & deal scoring
└── Depreciation curve fitting

Postgres (Incus container)
├── TimescaleDB (price time-series)
└── pg_duckdb (analytical queries)
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Web app | Elixir / Phoenix 1.7+ LiveView |
| Analytics | OxCaml + Dream web framework |
| Database | Postgres 16 + TimescaleDB + pg_duckdb |
| Search | Brave Search API |
| Containers | Incus (custom lifecycle management) |

## How It Works

1. Search for a car (e.g., "2021 Toyota Camry")
2. Brave Search fetches current listings/prices from the web
3. Prices are stored as time-series data in TimescaleDB
4. OCaml service analyzes: avg price, distribution, depreciation rate, deal score
5. Phoenix LiveView renders dashboard with charts and recommendations

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
- DuckDB-in-Postgres for analytical queries
- OCaml for numerical analysis (via OxCaml/Jane Street fork)
