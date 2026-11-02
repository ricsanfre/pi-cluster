#!/bin/bash
#
# Bootstrap CNI, DNS and Flux on a freshly created k3d cluster.
#
# Cilium and CoreDNS must exist before the Flux controllers can schedule pods
# and resolve github.com. The Flux HelmReleases in clusters/dev adopt these
# releases on the first reconciliation.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KUBE_CONTEXT="${KUBE_CONTEXT:-k3d-picluster}"

CILIUM_VERSION="${CILIUM_VERSION:-1.20.4}"
COREDNS_VERSION="${COREDNS_VERSION:-1.49.0}"
FLUX_OPERATOR_VERSION="${FLUX_OPERATOR_VERSION:-0.62.1}"
FLUX_INSTANCE_VERSION="${FLUX_INSTANCE_VERSION:-0.62.1}"

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

if [ "$(kubectl config current-context)" != "$KUBE_CONTEXT" ]; then
  echo "ERROR: kubectl context is '$(kubectl config current-context)', expected '$KUBE_CONTEXT'" >&2
  exit 1
fi

release_exists() {
  helm -n "$1" status "$2" >/dev/null 2>&1
}

echo "Installing Cilium ${CILIUM_VERSION}"
if release_exists kube-system cilium; then
  echo "Cilium release already exists; leaving it to Flux"
else
  helm upgrade --install cilium oci://quay.io/cilium/charts/cilium \
    --version "$CILIUM_VERSION" \
    --namespace kube-system \
    --values "$ROOT/kubernetes/platform/cilium/app/base/values.yaml" \
    --values "$ROOT/kubernetes/platform/cilium/app/components/istio-config/values.yaml" \
    --values "$ROOT/kubernetes/platform/cilium/app/overlays/dev/values.yaml" \
    --wait --timeout 10m
fi

echo "Waiting for the node to become Ready (CNI is now installed)"
kubectl wait --for=condition=Ready node --all --timeout=180s

echo "Installing CoreDNS ${COREDNS_VERSION}"
if release_exists kube-system coredns; then
  echo "CoreDNS release already exists; leaving it to Flux"
else
  helm upgrade --install coredns oci://ghcr.io/coredns/charts/coredns \
    --version "$COREDNS_VERSION" \
    --namespace kube-system \
    --values "$ROOT/kubernetes/platform/coredns/app/base/values.yaml" \
    --values "$ROOT/kubernetes/platform/coredns/app/overlays/dev/values.yaml" \
    --wait --timeout 10m
fi

echo "Installing flux-operator ${FLUX_OPERATOR_VERSION}"
if release_exists flux-system flux-operator; then
  echo "flux-operator release already exists; leaving it to Flux"
else
  helm upgrade --install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
    --version "$FLUX_OPERATOR_VERSION" \
    --namespace flux-system \
    --create-namespace \
    --values "$ROOT/kubernetes/platform/flux-operator/operator/base/values.yaml" \
    --values "$ROOT/kubernetes/platform/flux-operator/operator/overlays/dev/values.yaml" \
    --wait --timeout 10m
fi

echo "Installing flux-instance ${FLUX_INSTANCE_VERSION}"
if release_exists flux-system flux-instance; then
  echo "flux-instance release already exists; leaving it to Flux"
else
  helm upgrade --install flux-instance oci://ghcr.io/controlplaneio-fluxcd/charts/flux-instance \
    --version "$FLUX_INSTANCE_VERSION" \
    --namespace flux-system \
    --values "$ROOT/kubernetes/platform/flux-operator/instance/base/values.yaml" \
    --values "$ROOT/kubernetes/platform/flux-operator/instance/overlays/dev/values.yaml" \
    --wait --timeout 10m
fi

echo "Applying dev cluster settings"
if kubectl -n flux-system get kustomization flux-system >/dev/null 2>&1; then
  echo "Flux root already exists; skipping direct cluster-settings apply"
else
  kubectl kustomize "$ROOT/kubernetes/clusters/dev/config" | kubectl apply -f -
fi

echo "Waiting for the Flux root Kustomization"
for i in $(seq 1 60); do
  if kubectl -n flux-system get kustomization flux-system >/dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "ERROR: Flux did not create the flux-system Kustomization" >&2
    exit 1
  fi
  sleep 5
done

kubectl -n flux-system wait --for=condition=Ready kustomization/flux-system --timeout=10m

if command -v flux >/dev/null 2>&1; then
  flux reconcile source git flux-system -n flux-system >/dev/null 2>&1 || true
  flux reconcile kustomization flux-system -n flux-system --with-source >/dev/null 2>&1 || true
fi

echo "Flux bootstrap complete"
