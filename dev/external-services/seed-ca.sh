#!/bin/bash
#
# Seed the dev CA into the k3d cluster.
#
# The CA in ./certs is the dev root of trust: it signs the RustFS server
# certificate and, through cert-manager's `ca-issuer`, the certificates used by
# the cluster (Envoy Gateway wildcard, Fluentd). This script publishes the
# public certificate so workloads can verify the services and the issuer can
# sign leaf certificates:
#
#   - Secret/dev-root-ca in the cert-manager namespace (issuer seed, contains
#     the CA key: the issuer cannot sign without it)
#   - Secret/rustfs-ca in every namespace whose workloads verify RustFS TLS
#   - Secret/vault-ca in the external-secrets namespace (caProvider)
#
# The cert-manager and external-secrets namespaces are created here, so the
# seed can run before (or without) the profiles that install those components.
#
# Safe to re-run. No-op on clusters other than k3d-picluster or when that
# cluster is not reachable.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBE_CONTEXT="${KUBE_CONTEXT:-k3d-picluster}"
CA_CRT="$SCRIPT_DIR/certs/ca.crt"
CA_KEY="$SCRIPT_DIR/certs/ca.key"

# Namespaces with workloads that verify the RustFS certificate. Only the ones
# that exist are seeded; the rest are picked up on the next run.
RUSTFS_CONSUMERS="${RUSTFS_CONSUMERS:-velero databases loki tempo}"

# Namespaces whose workloads verify the Vault server certificate (the dev
# ClusterSecretStore references this Secret through caProvider).
VAULT_CONSUMERS="${VAULT_CONSUMERS:-external-secrets}"

if [ ! -f "$CA_CRT" ] || [ ! -f "$CA_KEY" ]; then
  echo "ERROR: $CA_CRT or $CA_KEY not found. Run ./gen-certs.sh first." >&2
  exit 1
fi

if [ ! -r "$CA_KEY" ]; then
  echo "ERROR: cannot read $CA_KEY (owner UID $(stat -c %u "$CA_KEY"))" >&2
  echo "       Restore ownership with: sudo chown -R $(id -u):$(id -g) $SCRIPT_DIR/certs" >&2
  exit 1
fi

current="$(kubectl config current-context 2>/dev/null || true)"
if [ "$current" != "$KUBE_CONTEXT" ]; then
  echo "Skipping CA seed: kubectl context is '${current:-<none>}', expected '$KUBE_CONTEXT'"
  exit 0
fi

if ! kubectl get --raw /readyz >/dev/null 2>&1; then
  echo "Skipping CA seed: cluster '$KUBE_CONTEXT' is not reachable"
  exit 0
fi

# The issuer seed does not need cert-manager (a Secret only needs the API
# server), and creating the namespace here removes the ordering trap where
# `dev-up` seeded too early and `cert-manager-config` then waited forever on a
# ClusterIssuer whose secret did not exist. The profile applies the same
# Namespace later; the manifest is identical, so the apply is idempotent.
#
# `external-secrets` is created for the same reason: the dev ClusterSecretStore
# reads Secret/external-secrets/vault-ca through `caProvider`.
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n cert-manager create secret tls dev-root-ca \
  --cert="$CA_CRT" \
  --key="$CA_KEY" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "Seeded Secret/cert-manager/dev-root-ca"

for ns in $RUSTFS_CONSUMERS; do
  if kubectl get namespace "$ns" >/dev/null 2>&1; then
    kubectl -n "$ns" create secret generic rustfs-ca \
      --from-file=ca.crt="$CA_CRT" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    echo "Seeded Secret/$ns/rustfs-ca"
  fi
done

for ns in $VAULT_CONSUMERS; do
  if kubectl get namespace "$ns" >/dev/null 2>&1; then
    kubectl -n "$ns" create secret generic vault-ca \
      --from-file=ca.crt="$CA_CRT" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    echo "Seeded Secret/$ns/vault-ca"
  fi
done
