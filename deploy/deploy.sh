#!/usr/bin/env bash
# Deploys MIKAN STUDIO to the production host and (re)starts the stack.
# Idempotent. Never touches the remote .env or data/.
#
# Usage: deploy/deploy.sh            (ssh host alias "mikan", target /opt/mikan)
#        MIKAN_HOST=other MIKAN_DIR=/srv/mikan deploy/deploy.sh
set -euo pipefail

HOST="${MIKAN_HOST:-mikan}"
REMOTE_DIR="${MIKAN_DIR:-/opt/mikan}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_UID=1000 # "node" user inside the container image

RSYNC_EXCLUDES=(
  --exclude node_modules
  --exclude dist
  --exclude coverage
  --exclude data
  --exclude .env
  --exclude '*.log'
  --exclude .DS_Store
)

say() { printf '\n→ %s\n' "$*"; }

say "Checking ${HOST}"
ssh "$HOST" "command -v docker >/dev/null && docker compose version >/dev/null" \
  || { echo "docker / docker compose not found on ${HOST}"; exit 1; }
ssh "$HOST" "mkdir -p '${REMOTE_DIR}/server' '${REMOTE_DIR}/deploy/data'"

say "Syncing server/ and deploy/ (excluding node_modules, data, .env)"
rsync -az --delete "${RSYNC_EXCLUDES[@]}" "${ROOT}/server/" "${HOST}:${REMOTE_DIR}/server/"
rsync -az --delete "${RSYNC_EXCLUDES[@]}" "${ROOT}/deploy/" "${HOST}:${REMOTE_DIR}/deploy/"

if ! ssh "$HOST" "test -f '${REMOTE_DIR}/deploy/.env'"; then
  echo "Remote ${REMOTE_DIR}/deploy/.env is missing."
  echo "Create it once:  ssh ${HOST} 'cp ${REMOTE_DIR}/deploy/.env.example ${REMOTE_DIR}/deploy/.env && nano ${REMOTE_DIR}/deploy/.env'"
  exit 1
fi

say "Ensuring data/ is writable by the container user (uid ${APP_UID})"
ssh "$HOST" "chown ${APP_UID}:${APP_UID} '${REMOTE_DIR}/deploy/data' 2>/dev/null || sudo -n chown ${APP_UID}:${APP_UID} '${REMOTE_DIR}/deploy/data'"

say "Building and starting containers"
ssh "$HOST" "cd '${REMOTE_DIR}/deploy' && docker compose up -d --build --remove-orphans && docker compose ps"

say "Waiting for /api/health"
ssh "$HOST" "cd '${REMOTE_DIR}/deploy' && for i in \$(seq 1 30); do
  if docker compose exec -T api node -e \"fetch('http://127.0.0.1:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\"; then
    echo 'API is healthy'; exit 0
  fi
  sleep 2
done
echo 'API did not become healthy — see: docker compose logs --tail=100 api'; exit 1"

say "Done"
