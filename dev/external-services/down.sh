#!/bin/bash
#
# Stop the dev external services. Data in ./data and ./certs is kept.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f .env ]; then
  echo "No .env found; nothing to stop"
  exit 0
fi

docker compose --project-directory "$SCRIPT_DIR" --env-file "$SCRIPT_DIR/.env" --profile vault down
echo "External services stopped (data kept)"
