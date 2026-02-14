#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="carscope-pg"
IMAGE="images:ubuntu/noble"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Setting up Postgres container: ${CONTAINER_NAME}"

# Check if container already exists
if incus info "${CONTAINER_NAME}" &>/dev/null; then
  echo "Container ${CONTAINER_NAME} already exists."
  state=$(incus info "${CONTAINER_NAME}" | grep "Status:" | awk '{print $2}')
  if [ "$state" != "RUNNING" ]; then
    echo "Starting existing container..."
    incus start "${CONTAINER_NAME}"
  fi
  echo "==> Container is running"
  incus exec "${CONTAINER_NAME}" -- pg_isready -U carscope && echo "==> Postgres is ready" && exit 0
  echo "Postgres not ready yet, waiting..."
fi

# Launch container
if ! incus info "${CONTAINER_NAME}" &>/dev/null; then
  echo "==> Launching container from ${IMAGE}..."
  incus launch "${IMAGE}" "${CONTAINER_NAME}"

  echo "==> Waiting for container networking..."
  for i in $(seq 1 30); do
    if incus exec "${CONTAINER_NAME}" -- ip -4 addr show eth0 2>/dev/null | grep -q "inet "; then
      break
    fi
    sleep 1
  done
fi

echo "==> Installing Postgres 16 + TimescaleDB..."
incus exec "${CONTAINER_NAME}" -- bash -c '
  export DEBIAN_FRONTEND=noninteractive

  # Add PostgreSQL APT repo
  apt-get update -qq
  apt-get install -y -qq curl gnupg lsb-release >/dev/null 2>&1

  # PostgreSQL official repo
  curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg
  echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list

  # TimescaleDB repo
  curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor -o /usr/share/keyrings/timescaledb.gpg
  echo "deb [signed-by=/usr/share/keyrings/timescaledb.gpg] https://packagecloud.io/timescale/timescaledb/ubuntu/ $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/timescaledb.list

  apt-get update -qq
  apt-get install -y -qq postgresql-16 timescaledb-2-postgresql-16 >/dev/null 2>&1

  # Configure TimescaleDB
  timescaledb-tune --quiet --yes

  # Configure Postgres to accept connections from host
  PG_HBA="/etc/postgresql/16/main/pg_hba.conf"
  PG_CONF="/etc/postgresql/16/main/postgresql.conf"

  # Listen on all interfaces
  sed -i "s/#listen_addresses = .*/listen_addresses = '\''*'\''/" "$PG_CONF"

  # Allow connections from Incus bridge subnet
  echo "host all all 0.0.0.0/0 md5" >> "$PG_HBA"

  # Restart Postgres
  systemctl restart postgresql
  systemctl enable postgresql

  # Create carscope database and user
  sudo -u postgres psql -c "CREATE USER carscope WITH PASSWORD '\''carscope'\'' CREATEDB;"
  sudo -u postgres psql -c "CREATE DATABASE carscope OWNER carscope;"
  sudo -u postgres psql -d carscope -c "GRANT ALL PRIVILEGES ON DATABASE carscope TO carscope;"
'

echo "==> Loading schema..."
incus file push "${SCRIPT_DIR}/pg-init.sql" "${CONTAINER_NAME}/tmp/pg-init.sql"
incus exec "${CONTAINER_NAME}" -- sudo -u postgres psql -d carscope -f /tmp/pg-init.sql

echo "==> Waiting for Postgres to be ready..."
for i in $(seq 1 15); do
  if incus exec "${CONTAINER_NAME}" -- pg_isready -U carscope 2>/dev/null; then
    break
  fi
  sleep 1
done

# Print connection info
PG_IP=$(incus list "${CONTAINER_NAME}" --format csv -c 4 | cut -d' ' -f1)
echo ""
echo "==> Postgres container ready!"
echo "    Container: ${CONTAINER_NAME}"
echo "    IP:        ${PG_IP}"
echo "    Port:      5432"
echo "    Database:  carscope"
echo "    User:      carscope"
echo "    Password:  carscope"
echo ""
echo "    Connection string:"
echo "    postgres://carscope:carscope@${PG_IP}:5432/carscope"
