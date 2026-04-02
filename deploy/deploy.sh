#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/deploy/docker-compose.prod.yml"
FRONTEND_BUILD_DIR="$PROJECT_ROOT/frontend/build/web"
FRONTEND_TARGET_DIR="/var/www/fit.ileonov.ru"

echo "==> Switching to project directory: $PROJECT_ROOT"
cd "$PROJECT_ROOT"

echo "==> Pulling latest changes from Git"
git pull --ff-only

echo "==> Rebuilding and restarting backend"
docker compose -f "$COMPOSE_FILE" up -d --build

if command -v flutter >/dev/null 2>&1; then
  echo "==> Flutter detected, building web frontend"
  (
    cd "$PROJECT_ROOT/frontend"
    flutter pub get
    flutter build web
  )

  echo "==> Publishing frontend to $FRONTEND_TARGET_DIR"
  sudo mkdir -p "$FRONTEND_TARGET_DIR"
  sudo rsync -av --delete "$FRONTEND_BUILD_DIR"/ "$FRONTEND_TARGET_DIR"/
else
  echo "==> Flutter not found on server, skipping frontend build"
  echo "    Install Flutter on VPS if you want the web frontend to deploy from Git too."
fi

echo "==> Deployment finished"
