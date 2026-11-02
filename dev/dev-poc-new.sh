#!/bin/bash
#
# Create a new POC workspace under test/<name>/ from dev/poc-template/ and a
# Flux Kustomization that points at it.
#
# Usage: ./dev-poc-new.sh <name>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAME="${1:-}"

if [ -z "$NAME" ]; then
  echo "Usage: $0 <name>" >&2
  exit 1
fi

if [[ ! "$NAME" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
  echo "ERROR: '$NAME' is not a valid Kubernetes namespace name" >&2
  exit 1
fi

DEST="$ROOT/test/$NAME"
PROFILE="$ROOT/kubernetes/clusters/dev/profiles/poc-$NAME.yaml"

if [ -e "$DEST" ]; then
  echo "ERROR: $DEST already exists" >&2
  exit 1
fi

mkdir -p "$ROOT/test"
cp -r "$ROOT/dev/poc-template" "$DEST"
sed -i "s/poc-template/$NAME/g" "$DEST"/*.yaml

cat >"$PROFILE" <<EOF
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: poc-$NAME
  namespace: flux-system
spec:
  interval: 30m
  targetNamespace: $NAME
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./test/$NAME
  prune: true
  wait: true
EOF

# If the dev cluster is up, create the namespace and copy the RustFS CA now so
# the POC can use TLS on day one. The namespace is still managed by Flux.
if [ "$(kubectl config current-context 2>/dev/null || true)" = "k3d-picluster" ]; then
  kubectl create namespace "$NAME" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  if [ -f "$ROOT/dev/external-services/certs/ca.crt" ]; then
    kubectl -n "$NAME" create secret generic rustfs-ca \
      --from-file=ca.crt="$ROOT/dev/external-services/certs/ca.crt" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    echo "Created rustfs-ca Secret in namespace $NAME"
  fi
fi

echo "Created $DEST"
echo "Created $PROFILE"
echo
echo "Enable it by adding this line to kubernetes/clusters/dev/profiles/kustomization.yaml:"
echo "  - poc-$NAME.yaml"
