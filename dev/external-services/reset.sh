#!/bin/bash
#
# Stop the dev external services and delete all local data, certificates and
# generated credentials. Destructive: asks for confirmation unless FORCE=1.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ "${FORCE:-0}" != "1" ]; then
  echo "This deletes external-services/data, certs and .env."
  read -r -p "Type 'yes' to continue: " answer
  if [ "$answer" != "yes" ]; then
    echo "Aborted"
    exit 1
  fi
fi

if [ -f .env ]; then
  docker compose --project-directory "$SCRIPT_DIR" --env-file "$SCRIPT_DIR/.env" --profile vault down -v || true
fi

rm -rf data certs .env
echo "External services reset"
