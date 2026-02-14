#!/usr/bin/env bash
set -euo pipefail

CONTAINERS=("carscope-pg" "carscope-ocaml")

echo "==> Tearing down CarScope containers..."

for container in "${CONTAINERS[@]}"; do
  if incus info "${container}" &>/dev/null; then
    echo "    Stopping and deleting ${container}..."
    incus stop "${container}" --force 2>/dev/null || true
    incus delete "${container}" --force
    echo "    Deleted ${container}"
  else
    echo "    ${container} does not exist, skipping"
  fi
done

echo "==> Teardown complete"
