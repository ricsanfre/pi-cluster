#!/bin/bash
#
# Render every dev kustomization without touching a cluster.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

paths=(
  "kubernetes/clusters/dev"
  "kubernetes/clusters/dev/profiles"
  "kubernetes/platform/cilium/app/overlays/dev"
  "kubernetes/platform/cilium/config/overlays/dev"
  "kubernetes/platform/coredns/app/overlays/dev"
  "kubernetes/platform/istio/app/overlays/dev"
  "kubernetes/platform/vault/app/overlays/dev"
  "kubernetes/platform/external-dns/app/overlays/dev"
  "kubernetes/platform/kube-vip/overlays/dev"
  "kubernetes/platform/kiali/app/overlays/dev"
  "kubernetes/platform/eck-operator/app/overlays/dev"
  "kubernetes/platform/elastic-stack/app/overlays/dev"
  "kubernetes/platform/elastic-stack/config/overlays/dev"
  "kubernetes/platform/elastic-stack/prometheus-elasticsearch-exporter/overlays/dev"
  "kubernetes/platform/fluent/fluentd/overlays/dev"
  "kubernetes/platform/flux-operator/operator/overlays/dev"
  "kubernetes/platform/flux-operator/instance/overlays/dev"
  "kubernetes/platform/metrics-server/app/overlays/dev"
  "kubernetes/platform/cert-manager/app/overlays/dev"
  "kubernetes/platform/cert-manager/config/overlays/dev"
  "kubernetes/platform/envoy-gateway/app/overlays/dev"
  "kubernetes/platform/envoy-gateway/config/overlays/dev"
  "kubernetes/platform/databases/cloudnative-pg/app/overlays/dev"
  "kubernetes/platform/databases/plugin-barman-cloud/app/overlays/dev"
  "kubernetes/platform/external-secrets/app/overlays/dev"
  "kubernetes/platform/external-secrets/config/overlays/dev"
  "kubernetes/platform/kube-prometheus-stack/prometheus-operator-crds/overlays/dev"
  "kubernetes/platform/kube-prometheus-stack/app/overlays/dev"
  "kubernetes/platform/grafana/operator/overlays/dev"
  "kubernetes/platform/grafana/instance/overlays/dev"
  "kubernetes/platform/loki/app/overlays/dev"
  "kubernetes/platform/fluent/common/overlays/dev"
  "kubernetes/platform/fluent/fluent-bit/overlays/dev"
  "kubernetes/platform/tempo/app/overlays/dev"
  "kubernetes/platform/opentelemetry-collector/app/overlays/dev"
  "kubernetes/platform/kafka/strimzi-kafka-operator/overlays/dev"
  "kubernetes/platform/kafka/cluster/overlays/dev"
  "kubernetes/platform/databases/mongodb-community-operator/app/overlays/dev"
  "kubernetes/platform/databases/valkey-operator/app/overlays/dev"
  "kubernetes/platform/keycloak/operator/overlays/dev"
  "kubernetes/platform/keycloak/database/overlays/dev"
  "kubernetes/platform/keycloak/app/overlays/dev"
  "kubernetes/platform/velero/app/overlays/dev"
  "kubernetes/platform/velero/config/overlays/dev"
  "kubernetes/apps/e-commerce/app/overlays/dev"
  "kubernetes/apps/e-commerce/cart-service/overlays/dev"
  "kubernetes/apps/e-commerce/config/common/overlays/dev"
  "kubernetes/apps/e-commerce/config/databases/overlays/dev"
  "kubernetes/apps/e-commerce/config/kafka/overlays/dev"
  "kubernetes/apps/e-commerce/config/keycloak/overlays/dev"
  "kubernetes/apps/e-commerce/frontend-service/overlays/dev"
  "kubernetes/apps/e-commerce/notification-service/overlays/dev"
  "kubernetes/apps/e-commerce/order-service/overlays/dev"
  "kubernetes/apps/e-commerce/product-service/overlays/dev"
  "kubernetes/apps/e-commerce/reviews-service/overlays/dev"
  "kubernetes/apps/e-commerce/user-service/overlays/dev"
  "kubernetes/platform/cert-manager/webhook-ionos/overlays/dev"
  "kubernetes/platform/csi-external-snapshotter/app/overlays/dev"
  "kubernetes/platform/databases/common/overlays/dev"
  "kubernetes/platform/descheduler/app/overlays/dev"
  "kubernetes/platform/flux-operator/tofu-controller/overlays/dev"
  "kubernetes/platform/kafka/kafdrop/overlays/dev"
  "kubernetes/platform/kafka/schema-registry/overlays/dev"
  "kubernetes/platform/keycloak/config/overlays/dev"
  "kubernetes/platform/kube-prometheus-stack/externalnodes-monitoring/overlays/dev"
  "kubernetes/platform/kube-prometheus-stack/k3s-mixins/overlays/dev"
  "kubernetes/platform/longhorn/app/overlays/dev"
  "kubernetes/platform/system-upgrade/app/overlays/dev"
  "kubernetes/platform/system-upgrade/config/overlays/dev"
)

failed=0
for path in "${paths[@]}"; do
  printf '%-70s ' "$path"
  if kubectl kustomize "$ROOT/$path" >/dev/null 2>/tmp/dev-render.err; then
    echo "OK"
  else
    echo "FAIL"
    sed 's/^/    /' /tmp/dev-render.err
    failed=1
  fi
done

rm -f /tmp/dev-render.err
exit "$failed"
