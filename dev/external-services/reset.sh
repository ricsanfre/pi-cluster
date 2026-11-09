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

# Deleting certs/ while the cluster survives leaves its CA material stale: the
# seeded dev-root-ca still signs new certificates with the old key.
if [ "$(kubectl config current-context 2>/dev/null || true)" = "k3d-picluster" ] \
  && kubectl get --raw /readyz >/dev/null 2>&1; then
  echo "WARNING: the cluster still holds dev-root-ca, rustfs-ca/vault-ca and" >&2
  echo "         certificates issued from the CA that is being deleted." >&2
  echo "         Run 'make dev-services-up' then 'make dev-seed-ca', and delete the" >&2
  echo "         cert-manager Certificate secrets so they are re-issued." >&2
fi

# Bind-mounted state is owned by the service UIDs (RustFS runs as 10001) and by
# root after `rustfs-perms`, so the invoking user cannot unlink it. Empty each
# tree from a throwaway root container first; the directories themselves are
# then removable because their parent is host-owned.
cleanup_tree() {
  local path="$1"
  [ -e "$path" ] || return 0
  docker run --rm -v "$SCRIPT_DIR/$path:/cleanup" --entrypoint sh alpine:3.22 \
    -c 'find /cleanup -mindepth 1 -delete 2>/dev/null || true' >/dev/null 2>&1 || true
  rm -rf "$path" 2>/dev/null || echo "WARNING: could not remove $path" >&2
}

cleanup_tree data
cleanup_tree certs
rm -f .env
echo "External services reset"
