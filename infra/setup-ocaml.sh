#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="carscope-ocaml"
IMAGE="images:ubuntu/noble"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

echo "==> Setting up OCaml analytics container: ${CONTAINER_NAME}"

# Check if container already exists
if incus info "${CONTAINER_NAME}" &>/dev/null; then
  echo "Container ${CONTAINER_NAME} already exists."
  state=$(incus info "${CONTAINER_NAME}" | grep "Status:" | awk '{print $2}')
  if [ "$state" != "RUNNING" ]; then
    echo "Starting existing container..."
    incus start "${CONTAINER_NAME}"
  fi
  echo "==> Container is running"
  exit 0
fi

# Launch container
echo "==> Launching container from ${IMAGE}..."
incus launch "${IMAGE}" "${CONTAINER_NAME}"

echo "==> Waiting for container networking..."
for i in $(seq 1 30); do
  if incus exec "${CONTAINER_NAME}" -- ip -4 addr show eth0 2>/dev/null | grep -q "inet "; then
    break
  fi
  sleep 1
done

echo "==> Installing OCaml toolchain..."
incus exec "${CONTAINER_NAME}" -- bash -c '
  export DEBIAN_FRONTEND=noninteractive

  apt-get update -qq
  apt-get install -y -qq build-essential curl git pkg-config \
    libev-dev libssl-dev libffi-dev zlib1g-dev \
    opam >/dev/null 2>&1

  # Initialize opam for root user (non-interactive)
  opam init --bare --disable-sandboxing --yes

  # Create a switch with OCaml 5.2
  opam switch create carscope 5.2.1 --yes

  # Install Dream web framework and dependencies
  eval $(opam env --switch=carscope)
  opam install dream yojson ppx_deriving_yojson core_unix --yes
'

# Push analytics source code if it exists
if [ -d "${PROJECT_ROOT}/analytics" ]; then
  echo "==> Pushing analytics source to container..."
  incus file push -r "${PROJECT_ROOT}/analytics/" "${CONTAINER_NAME}/opt/analytics/"
  incus exec "${CONTAINER_NAME}" -- bash -c '
    eval $(opam env --switch=carscope)
    cd /opt/analytics && dune build 2>/dev/null || echo "Will build after source is ready"
  '
fi

OCAML_IP=$(incus list "${CONTAINER_NAME}" --format csv -c 4 | cut -d' ' -f1)
echo ""
echo "==> OCaml analytics container ready!"
echo "    Container: ${CONTAINER_NAME}"
echo "    IP:        ${OCAML_IP}"
echo "    Analytics service will listen on port 8080"
echo ""
echo "    To build & run the service:"
echo "    incus exec ${CONTAINER_NAME} -- bash -c 'eval \$(opam env --switch=carscope) && cd /opt/analytics && dune exec bin/server.exe'"
