#!/bin/bash
#
# Read-only status report for the dev cluster.
#
set -euo pipefail

KUBE_CONTEXT="${KUBE_CONTEXT:-k3d-picluster}"

current="$(kubectl config current-context 2>/dev/null || true)"
if [ "$current" != "$KUBE_CONTEXT" ]; then
  echo "ERROR: kubectl context is '${current:-<none>}', expected '$KUBE_CONTEXT'" >&2
  exit 1
fi

echo "== Nodes =="
kubectl get nodes -o wide

echo
echo "== Flux Kustomizations =="
if command -v flux >/dev/null 2>&1; then
  flux get kustomizations -A || true
else
  kubectl get kustomizations -A || true
fi

echo
echo "== HelmReleases =="
kubectl get helmreleases -A || true

echo
echo "== Non-running pods =="
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded || true

echo
echo "== Recent warning events =="
kubectl get events -A --field-selector=type=Warning --sort-by=.lastTimestamp 2>/dev/null | tail -20 || true
