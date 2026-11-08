#!/bin/bash
#
# Start the dev external services (RustFS, optionally Vault) and create the
# Kubernetes-side credentials/buckets.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VAULT="${VAULT:-0}"

# The k3d cluster and the external services share this network. If the cluster
# has not been created yet, create the network with the same parameters.
if ! docker network inspect picluster >/dev/null 2>&1; then
  echo "Creating docker network 'picluster'"
  docker network create \
    --driver bridge \
    --subnet 172.30.0.0/16 \
    --gateway 172.30.0.1 \
    --ip-range 172.30.0.0/17 \
    picluster
fi

./gen-env.sh
./gen-certs.sh

mkdir -p data/rustfs data/logs

args=(--project-directory "$SCRIPT_DIR" --env-file "$SCRIPT_DIR/.env" up -d)
if [ "$VAULT" = "1" ]; then
  echo "Starting RustFS + Vault"
  args=(--project-directory "$SCRIPT_DIR" --env-file "$SCRIPT_DIR/.env" --profile vault up -d)
else
  echo "Starting RustFS (Vault disabled; use VAULT=1 to enable)"
fi

docker compose "${args[@]}"

echo "Waiting for RustFS health endpoint"
for i in $(seq 1 60); do
  if curl --silent --fail --cacert certs/ca.crt https://127.0.0.1:9091/health >/dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "ERROR: RustFS did not become healthy" >&2
    exit 1
  fi
  sleep 2
done

./bootstrap.sh

# Publish the dev CA as the cluster trust anchor and cert-manager issuer seed.
# No-op when the current context is not the k3d cluster.
./seed-ca.sh

if [ "$VAULT" = "1" ]; then
  echo "Waiting for Vault health endpoint"
  for i in $(seq 1 60); do
    if curl --silent --fail --cacert certs/ca.crt https://127.0.0.1:8200/v1/sys/health >/dev/null 2>&1; then
      break
    fi
    if [ "$i" -eq 60 ]; then
      echo "ERROR: Vault did not become healthy" >&2
      exit 1
    fi
    sleep 2
  done

  if [ "$(kubectl config current-context 2>/dev/null || true)" = "k3d-picluster" ]; then
    # The `secrets` profile expects this token in the external-secrets
    # namespace. This is a dev-only imperative secret; it is never committed.
    # shellcheck disable=SC1091
    set -a; source .env; set +a
    kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl -n external-secrets create secret generic vault-token \
      --from-literal=token="$VAULT_DEV_ROOT_TOKEN" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    echo "Created dev-only vault-token Secret in namespace external-secrets"
  fi
fi

echo "External services are up"
