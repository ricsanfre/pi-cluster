---
name: Service Testing
description: Use when proving a deployed or new service works — dev-cluster deployment, smoke and integration checks, metrics/logs/traces verification, promotion checklist, and cleanup.
---

# Service Testing

A service is not delivered until it has been tested. Test in the dev cluster first, then present the
evidence before promotion.

## Test ladder

Work in this order. Do not skip to prod because the manifests render.

1. **Static**: `kubectl kustomize` both overlays; `helm template` the chart with the overlay values.
2. **Dev deploy**: apply the dev overlay to the k3d cluster.
3. **Smoke**: pods ready, endpoints populated, health endpoint responds.
4. **Functional**: the service actually does its job (read/write, produce/consume, login, backup).
5. **Integration**: secrets sync, SSO login, metrics scrape, logs arrive, traces present, DNS/TLS.
6. **Negative**: unauthenticated access is rejected; bad credentials fail cleanly.
7. **Promotion**: checklist signed off, then wire prod.

## 1. Static checks

```bash
kubectl kustomize kubernetes/platform/<service>/app/overlays/dev
kubectl kustomize kubernetes/platform/<service>/app/overlays/prod
```

For a chart, verify the values you set are actually consumed:

```bash
helm template <release> <repo>/<chart> --version <version> -f <overlay-values.yaml> | grep -A3 '<key>'
```

If the value does not appear in the rendered output, it is in the wrong place or the key is wrong.

## 2. Dev cluster

```bash
cd dev
make create-k3d
make helm-setup
make cluster-setup
make cluster-bootstrap
```

Caveat: `dev/Makefile`'s `cluster-bootstrap` target references `kubernetes/clusters/bootstrap/flux`,
which is not present in this repository. Verify the target before running it; if it fails, apply the
dev config path directly:

```bash
kubectl kustomize ../kubernetes/clusters/dev/config | kubectl apply -f -
```

Deploy the service's dev overlay (after approval, since this mutates the dev cluster):

```bash
kubectl kustomize kubernetes/platform/<service>/app/overlays/dev | kubectl apply -f -
```

Or, if the dev cluster is Flux-managed, point the dev Kustomization at the branch.

## 3. Smoke

```bash
kubectl -n <ns> get pods,svc,endpoints
kubectl -n <ns> rollout status deploy/<name> --timeout=5m
kubectl -n <ns> get events --sort-by=.lastTimestamp | tail -20
```

Healthy: pods `Running` with low restart counts, endpoints non-empty, no `Warning` events, rollout
complete. For an operator/CRD service, also check the CR reaches `Ready`.

## 4. Functional

Run the service's own protocol, not just an HTTP 200:

- **Databases**: create a database, write/read a row, drop it.
- **Kafka**: produce and consume a message (`test/kafka/` has clients and a Makefile).
- **Object storage**: `mc` or `aws s3` put/get/delete against RustFS.
- **Backup**: `velero backup create` a namespace, inspect status (`test/velero/nginx.yaml` is the
  sample workload).
- **Tracing**: deploy the sample app (`test/tracing/emojivoto-ingress.yaml`) and confirm traces.
- **Auth**: complete a real login through Keycloak; assert the token has the expected claims.

Reusable test assets belong under `test/<service>/` with a `Makefile` and a short `README.md`, following
`test/kafka/`.

## 5. Integration checks

| Concern | Command | Expected |
| --- | --- | --- |
| Secrets | `kubectl -n <ns> get externalsecret` | `SecretSynced=True` |
| Metrics | Prometheus targets / `kubectl -n kube-prom-stack get servicemonitor` | target `UP` |
| Logs | `kubectl -n <ns> logs deploy/<name> --tail=100` | structured, no errors |
| Traces | Tempo/Grafana query for the service | spans present |
| TLS | `kubectl -n <ns> get certificate` and the served chain | `READY=True`, chain valid |
| DNS | `dig +short <host>` / ExternalDNS logs | record points at the gateway |
| Architecture | `kubectl -n <ns> get pods -o wide` | scheduled and running on both ARM and x86 where expected |
| Resources | `kubectl -n <ns> top pods` | within requests/limits, no OOMKills |

A service that is `Running` but not scraped, not logging, and not authenticating is not tested.

## 6. Negative tests

- Request the endpoint without credentials: expect `401`/`403`, not a redirect loop.
- Send an invalid token or wrong client secret: expect a clean rejection and a useful log line.
- Kill a pod and confirm it reschedules and recovers.
- For stateful services, confirm the PVC rebinds and data survives a pod restart.

## 7. Promotion checklist

Before proposing to wire prod, report each line:

```
[ ] dev overlay renders and deploys
[ ] smoke: pods ready, endpoints populated
[ ] functional test passed (what you ran)
[ ] ExternalSecret synced
[ ] metrics scrape UP
[ ] logs arriving
[ ] traces present (if applicable)
[ ] TLS certificate issued and valid
[ ] DNS record resolves
[ ] SSO login works (if applicable)
[ ] runs on both architectures
[ ] resources sized; no OOM/eviction
[ ] rollback path identified
[ ] docs page + nav updated
[ ] runbook written or updated
```

Only then follow `new-service` §9 to wire prod, or use `flux-change` to validate the branch.

## 8. Cleanup

- Remove test topics, buckets, databases, and users you created.
- Delete test workloads and namespaces from the dev cluster.
- `cd dev && make delete-k3d` when finished with the local cluster.
- Never leave test workloads or debug pods in prod.

## Guardrails

- Mutating the dev cluster requires approval; mutating prod requires an explicit request.
- Do not use production data for destructive tests. Create a throwaway database/topic/bucket.
- Do not promote a service whose only evidence is "the pod is Running".
- If a test cannot run (no dev cluster, missing credentials), say so and keep the item unchecked.
