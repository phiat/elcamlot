# CarScope — common development tasks

# Default: show available commands
default:
    @just --list

# --- Infrastructure ---

# Provision Postgres container (idempotent)
pg-up:
    bash infra/setup-pg.sh

# Provision OCaml analytics container (idempotent)
ocaml-up:
    bash infra/setup-ocaml.sh

# Start all containers
up: pg-up ocaml-up

# Stop all project containers
down:
    bash infra/teardown.sh

# Show container status
ps:
    incus list -c ns4t --format table | grep -E "carscope|NAME"

# Get Postgres container IP
pg-ip:
    @incus list carscope-pg --format csv -c 4 | cut -d' ' -f1

# Get OCaml container IP
ocaml-ip:
    @incus list carscope-ocaml --format csv -c 4 | cut -d' ' -f1

# Connect to Postgres via psql
psql:
    incus exec carscope-pg -- sudo -u postgres psql -d carscope

# Shell into Postgres container
pg-shell:
    incus exec carscope-pg -- bash

# Shell into OCaml container
ocaml-shell:
    incus exec carscope-ocaml -- bash

# --- Phoenix ---

# Start Phoenix dev server
server:
    cd carscope && CARSCOPE_PG_HOST=$(just pg-ip) mix phx.server

# Start Phoenix with iex
console:
    cd carscope && CARSCOPE_PG_HOST=$(just pg-ip) iex -S mix phx.server

# Run Ecto migrations
migrate:
    cd carscope && CARSCOPE_PG_HOST=$(just pg-ip) mix ecto.migrate

# Reset database (drop + create + migrate)
db-reset:
    cd carscope && CARSCOPE_PG_HOST=$(just pg-ip) mix ecto.reset

# Seed vehicles from SQL files
seed:
    incus file push infra/seed-vehicles.sql carscope-pg/tmp/seed.sql
    incus exec carscope-pg -- sudo -u postgres psql -d carscope -f /tmp/seed.sql

# Seed SUV data
seed-suvs:
    incus file push infra/seed-suvs.sql carscope-pg/tmp/seed-suvs.sql
    incus exec carscope-pg -- sudo -u postgres psql -d carscope -f /tmp/seed-suvs.sql

# --- Testing ---

# Run all unit tests
test:
    cd carscope && CARSCOPE_PG_HOST=$(just pg-ip) mix test --exclude integration

# Run integration tests (launches/destroys containers)
test-integration:
    cd carscope && CARSCOPE_PG_HOST=$(just pg-ip) mix test --only integration --timeout 120000

# Run all tests
test-all:
    cd carscope && CARSCOPE_PG_HOST=$(just pg-ip) mix test --timeout 120000

# --- OCaml Analytics ---

# Build OCaml analytics service (inside container)
ocaml-build:
    incus exec carscope-ocaml -- su - analytics -c 'eval $$(opam env --switch=carscope) && cd ~/app && dune build'

# Run OCaml analytics service (inside container)
ocaml-run:
    incus exec carscope-ocaml -- su - analytics -c 'eval $$(opam env --switch=carscope) && cd ~/app && dune exec bin/server.exe'

# Push analytics source to container and rebuild
ocaml-deploy:
    incus exec carscope-ocaml -- mkdir -p /home/analytics/app
    incus file push -r analytics/ carscope-ocaml/home/analytics/app/
    incus exec carscope-ocaml -- chown -R analytics:analytics /home/analytics/app
    just ocaml-build

# Test analytics health endpoint
ocaml-health:
    @curl -s http://$(just ocaml-ip):8080/health | python3 -m json.tool

# Test analytics with sample data
ocaml-test-analyze:
    @curl -s -X POST http://$(just ocaml-ip):8080/analyze \
        -H "Content-Type: application/json" \
        -d '{"prices": [25000, 23500, 27000, 24000, 26500]}' | python3 -m json.tool

# --- Brave Search ---

# Search for a car (usage: just search "2021 Toyota Camry")
search query:
    @source .env && curl -s "https://api.search.brave.com/res/v1/web/search?q={{query}}+price+for+sale&count=10" \
        -H "Accept: application/json" \
        -H "X-Subscription-Token: $BRAVE_SEARCH_API_KEY" | python3 -m json.tool | head -80

# --- Dev Workflow ---

# Full dev startup (containers + Phoenix)
dev:
    bash scripts/dev.sh

# Format Elixir code
fmt:
    cd carscope && mix format

# Compile and check for warnings
check:
    cd carscope && CARSCOPE_PG_HOST=$(just pg-ip) mix compile --warnings-as-errors

# Show project stats
stats:
    @echo "=== Vehicles ===" && \
    incus exec carscope-pg -- sudo -u postgres psql -d carscope -t -c "SELECT count(*) FROM vehicles;" && \
    echo "=== Price Snapshots ===" && \
    incus exec carscope-pg -- sudo -u postgres psql -d carscope -t -c "SELECT count(*) FROM price_snapshots;" && \
    echo "=== Search Queries ===" && \
    incus exec carscope-pg -- sudo -u postgres psql -d carscope -t -c "SELECT count(*) FROM search_queries;"

# Show connection info for all services
info:
    @echo "Postgres:  postgres://carscope:carscope@$(just pg-ip):5432/carscope"
    @echo "Analytics: http://$(just ocaml-ip):8080"
    @echo "Phoenix:   http://localhost:4000"

# --- Logs & Debug ---

# Tail Postgres logs
pg-logs:
    incus exec carscope-pg -- tail -f /var/log/postgresql/postgresql-18-main.log

# View OCaml analytics logs
ocaml-logs:
    incus exec carscope-ocaml -- cat /tmp/analytics.log 2>/dev/null || echo "No logs yet"

# Run an arbitrary SQL query
sql query:
    incus exec carscope-pg -- sudo -u postgres psql -d carscope -c "{{query}}"

# Show top vehicles by price snapshot count
top-vehicles:
    @just sql "SELECT v.year, v.make, v.model, count(p.*) as snapshots, round(avg(p.price_cents)/100) as avg_price FROM vehicles v LEFT JOIN price_snapshots p ON v.id = p.vehicle_id GROUP BY v.id ORDER BY snapshots DESC LIMIT 15;"

# Show recent price snapshots
recent-prices:
    @just sql "SELECT v.year, v.make, v.model, p.price_cents/100 as price, p.source, p.time FROM price_snapshots p JOIN vehicles v ON v.id = p.vehicle_id ORDER BY p.time DESC LIMIT 20;"

# --- OCaml Analytics Testing ---

# Test deal scoring
ocaml-test-score:
    @curl -s -X POST http://$(just ocaml-ip):8080/deal-score \
        -H "Content-Type: application/json" \
        -d '{"price": 22000, "market_prices": [25000, 23500, 27000, 24000, 26500]}' | python3 -m json.tool

# Test depreciation curve
ocaml-test-depreciation:
    @curl -s -X POST http://$(just ocaml-ip):8080/depreciation \
        -H "Content-Type: application/json" \
        -d '{"history": [{"time":"2023-01-01T00:00:00Z","price":35000},{"time":"2024-01-01T00:00:00Z","price":30000},{"time":"2025-01-01T00:00:00Z","price":26000}]}' | python3 -m json.tool

# Run OCaml analytics as background daemon
ocaml-start:
    incus exec carscope-ocaml -- su - analytics -c 'eval $$(opam env --switch=carscope) && cd ~/app && nohup dune exec bin/server.exe > /tmp/analytics.log 2>&1 &'
    @echo "Analytics service started in background"

# Stop OCaml analytics daemon
ocaml-stop:
    incus exec carscope-ocaml -- pkill -f server.exe 2>/dev/null || true
    @echo "Analytics service stopped"

# --- Snapshot & Backup ---

# Snapshot the Postgres container
pg-snapshot name="backup":
    incus snapshot create carscope-pg {{name}}
    @echo "Created snapshot: {{name}}"

# List Postgres snapshots
pg-snapshots:
    incus info carscope-pg | grep -A 50 "Snapshots:"

# Restore Postgres from snapshot
pg-restore name="backup":
    incus snapshot restore carscope-pg {{name}}
    @echo "Restored from snapshot: {{name}}"

# --- Versions ---

# Check versions of all tools in the stack
versions:
    @echo "=== Host Tools ==="
    @printf "  Elixir:       " && elixir --version 2>/dev/null | tail -1 || echo "not found"
    @printf "  Erlang/OTP:   " && erl -eval 'io:format("~s~n", [erlang:system_info(otp_release)]), halt().' -noshell 2>/dev/null || echo "not found"
    @printf "  Mix Phoenix:  " && cd carscope && mix deps 2>/dev/null | grep "phoenix " | awk '{print $3}' || echo "not found"
    @printf "  Mix LiveView: " && cd carscope && mix deps 2>/dev/null | grep "phoenix_live_view" | awk '{print $3}' || echo "not found"
    @printf "  Mix Req:      " && cd carscope && mix deps 2>/dev/null | grep "req " | awk '{print $3}' || echo "not found"
    @printf "  Tailwind CSS: " && grep 'version:' carscope/config/config.exs | grep tailwind | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "not found"
    @printf "  esbuild:      " && grep 'version:' carscope/config/config.exs | grep esbuild | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "not found"
    @echo ""
    @echo "=== Containers ==="
    @printf "  PostgreSQL:   " && incus exec carscope-pg -- psql --version 2>/dev/null | awk '{print $3}' || echo "container not running"
    @printf "  TimescaleDB:  " && incus exec carscope-pg -- sudo -u postgres psql -d carscope -t -c "SELECT extversion FROM pg_extension WHERE extname='timescaledb';" 2>/dev/null | tr -d ' ' || echo "container not running"
    @printf "  pg_duckdb:    " && incus exec carscope-pg -- sudo -u postgres psql -d carscope -t -c "SELECT extversion FROM pg_extension WHERE extname='pg_duckdb';" 2>/dev/null | tr -d ' ' || echo "not installed"
    @printf "  OCaml:        " && incus exec carscope-ocaml -- su - analytics -c "ocaml --version" 2>/dev/null || echo "container not running"
    @printf "  Dream:        " && incus exec carscope-ocaml -- su - analytics -c "opam show dream --field=version 2>/dev/null" 2>/dev/null || echo "container not running"
    @echo ""
    @echo "=== Latest Available ==="
    @echo "  PostgreSQL:   18.2"
    @echo "  Elixir:       1.19.5"
    @echo "  Phoenix:      1.8.3"
    @echo "  LiveView:     1.1.23"
    @echo "  Tailwind CSS: 4.1.x"
    @echo "  OCaml:        5.4.0"
    @echo "  TimescaleDB:  2.25.0"
    @echo "  pg_duckdb:    1.1.1"

# --- Cleanup ---

# Remove all project containers and data
nuke:
    @echo "This will destroy ALL CarScope containers. Ctrl+C to cancel."
    @sleep 3
    bash infra/teardown.sh
    @echo "All containers destroyed."

# Clean Elixir build artifacts
clean:
    cd carscope && mix clean
    rm -rf carscope/_build/dev carscope/_build/test
