#!/bin/bash
#
# Host and cluster resource usage for the dev environment.
#
set -euo pipefail

KUBE_CONTEXT="${KUBE_CONTEXT:-k3d-picluster}"

echo "== Host memory =="
free -h

echo
echo "== Docker containers =="
docker stats --no-stream \
  $(docker ps --filter "name=k3d-picluster" --filter "name=dev-rustfs" --filter "name=dev-vault" --format '{{.Names}}') 2>/dev/null || true

if [ "$(kubectl config current-context 2>/dev/null || true)" != "$KUBE_CONTEXT" ]; then
  echo
  echo "kubectl context is not $KUBE_CONTEXT; skipping cluster usage"
  exit 0
fi

echo
echo "== Node usage =="
kubectl top nodes || true

echo
echo "== Top pods =="
kubectl top pods -A --sort-by=memory 2>/dev/null | head -25 || true
