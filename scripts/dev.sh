#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Load .env file
if [ -f "${PROJECT_ROOT}/.env" ]; then
  set -a
  source "${PROJECT_ROOT}/.env"
  set +a
  echo "==> Loaded .env"
fi

echo "==> Starting CarScope dev environment..."

# Ensure containers are up
echo "==> Setting up Postgres..."
bash "${PROJECT_ROOT}/infra/setup-pg.sh"

echo ""
echo "==> Setting up OCaml analytics..."
bash "${PROJECT_ROOT}/infra/setup-ocaml.sh"

# Get container IPs
PG_IP=$(incus list carscope-pg --format csv -c 4 | cut -d' ' -f1)
OCAML_IP=$(incus list carscope-ocaml --format csv -c 4 | cut -d' ' -f1)

echo ""
echo "==> Dev environment ready!"
echo "    Postgres:  postgres://carscope:carscope@${PG_IP}:5432/carscope"
echo "    OCaml API: http://${OCAML_IP}:8080"
echo ""
echo "==> Starting Phoenix..."
cd "${PROJECT_ROOT}/carscope"

export CARSCOPE_PG_HOST="${PG_IP}"
export DATABASE_URL="postgres://carscope:carscope@${PG_IP}:5432/carscope"
export ANALYTICS_URL="http://${OCAML_IP}:8080"

mix phx.server
