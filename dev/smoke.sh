#!/bin/bash
#
# Smoke test for the dev cluster base. Safe to re-run.
#
set -euo pipefail

KUBE_CONTEXT="${KUBE_CONTEXT:-k3d-picluster}"
failed=0

fail() {
  echo "FAIL: $*" >&2
  failed=1
}

pass() {
  echo "OK:   $*"
}

current="$(kubectl config current-context 2>/dev/null || true)"
if [ "$current" != "$KUBE_CONTEXT" ]; then
  echo "ERROR: kubectl context is '${current:-<none>}', expected '$KUBE_CONTEXT'" >&2
  exit 1
fi

echo "== Nodes =="
if kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null 2>&1; then
  pass "all nodes Ready"
else
  fail "nodes not Ready"
fi

echo
echo "== Base workloads =="
check_rollout() {
  local ns="$1" kind="$2" name="$3"
  if kubectl -n "$ns" rollout status "$kind/$name" --timeout=120s >/dev/null 2>&1; then
    pass "$ns/$kind/$name"
  else
    fail "$ns/$kind/$name not ready"
  fi
}

check_rollout kube-system daemonset cilium
check_rollout kube-system deployment coredns
check_rollout kube-system deployment metrics-server
check_rollout flux-system deployment source-controller
check_rollout flux-system deployment kustomize-controller
check_rollout flux-system deployment helm-controller

echo
echo "== DNS =="
dns_ok=0
for _ in $(seq 1 6); do
  kubectl delete pod dev-smoke-dns -n default --ignore-not-found >/dev/null 2>&1 || true
  if kubectl run dev-smoke-dns -n default --image=busybox:1.37 --restart=Never --command -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1 \
    && kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/dev-smoke-dns -n default --timeout=60s >/dev/null 2>&1; then
    dns_ok=1
    break
  fi
  sleep 5
done
if [ "$dns_ok" = "1" ]; then
  pass "cluster DNS resolves kubernetes.default.svc.cluster.local"
else
  fail "cluster DNS check"
  kubectl logs dev-smoke-dns -n default 2>/dev/null | tail -5 || true
fi
kubectl delete pod dev-smoke-dns -n default --ignore-not-found >/dev/null 2>&1 || true

echo
echo "== Storage =="
# local-path uses WaitForFirstConsumer, so a consumer pod is required to bind.
cat <<'EOF' | kubectl apply -f - >/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dev-smoke-pvc
  namespace: default
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources:
    requests:
      storage: 64Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: dev-smoke-pvc
  namespace: default
spec:
  restartPolicy: Never
  containers:
    - name: sleep
      image: busybox:1.37
      command: ["sh", "-c", "sleep 60"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: dev-smoke-pvc
EOF
if kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/dev-smoke-pvc -n default --timeout=90s >/dev/null 2>&1; then
  pass "local-path PVC binds"
else
  fail "local-path PVC did not bind"
fi
kubectl delete pod dev-smoke-pvc -n default --ignore-not-found >/dev/null 2>&1 || true
kubectl delete pvc dev-smoke-pvc -n default --ignore-not-found >/dev/null 2>&1 || true

echo
echo "== Metrics =="
metrics_ok=0
for _ in $(seq 1 6); do
  if kubectl top nodes >/dev/null 2>&1; then
    metrics_ok=1
    break
  fi
  sleep 5
done
if [ "$metrics_ok" = "1" ]; then
  pass "kubectl top nodes"
else
  fail "metrics-server is not returning metrics"
fi

echo
echo "== External RustFS =="
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/external-services/certs/ca.crt" ]; then
  if curl --silent --fail --cacert "$SCRIPT_DIR/external-services/certs/ca.crt" https://127.0.0.1:9091/health >/dev/null 2>&1; then
    pass "RustFS health endpoint"
  else
    fail "RustFS is not reachable on 127.0.0.1:9091"
  fi
else
  echo "SKIP: dev/external-services/certs/ca.crt not found"
fi

echo
if [ "$failed" -ne 0 ]; then
  echo "Smoke test FAILED" >&2
  exit 1
fi
echo "Smoke test passed"
