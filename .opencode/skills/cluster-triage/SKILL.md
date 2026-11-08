---
name: Cluster Triage
description: Use when the Pi cluster is unhealthy — pods failing, Flux not reconciling, nodes NotReady, storage, TLS, DNS or external-service problems — to run a read-only, layer-ordered sweep and hand off to the right runbook.
---

# Cluster Triage

A read-only investigation procedure. Do not propose a fix until the failing layer is identified.

## Preconditions

- A valid kubeconfig. Confirm the target first:

  ```bash
  kubectl config current-context
  kubectl version
  ```

- Nothing in this skill mutates the cluster. If a step needs a write, stop and ask.

## Sweep order

Work top-down. Stop at the first layer that is broken; lower layers are often symptoms of it.

### 1. Context

Record the context, server version, and current time. A stale kubeconfig or the wrong cluster is a
common cause of "everything is down".

### 2. Nodes

```bash
kubectl get nodes -o wide
kubectl get nodes -o custom-columns=NAME:.metadata.name,READY:.status.conditions[-1].type,STATUS:.status.conditions[-1].status
kubectl describe node <node> | sed -n '/Conditions:/,/Addresses:/p'
kubectl top nodes
```

Healthy: all nodes `Ready`, no `MemoryPressure` / `DiskPressure` / `PIDPressure`, CPU and memory not
saturated. Pi nodes also suffer from throttling and SD-card wear — check with `make get-pi-status`.

### 3. Control plane and system components

```bash
kubectl -n kube-system get pods
kubectl -n kube-system get events --sort-by=.lastTimestamp | tail -30
```

On K3s, `kube-system` includes CoreDNS, metrics-server, and local-path. For HA control plane issues,
check that the kube-vip VIP is reachable and that all servers agree on the API endpoint.

### 4. Flux sources and Kustomizations

```bash
flux get sources all -A
flux get kustomizations -A
flux get kustomizations -A --status-selector ready=false
```

Healthy: every source `READY=True` with a recent revision, and every Kustomization `READY=True`.
A `False` source makes every downstream Kustomization stale — fix the source before touching apps.

### 5. HelmReleases

```bash
flux get helmreleases -A
flux get helmreleases -A --status-selector ready=false
kubectl -n <ns> describe helmrelease <name>
```

Read the `Ready` condition message and the last Helm failure. Typical causes: chart version not
available in the repository, values schema change, dependency Kustomization not ready, or an existing
resource that cannot be adopted.

### 6. Workloads

```bash
kubectl get pods -A --field-selector status.phase!=Running
kubectl get pods -A | grep -Ev '([0-9]+)/\1|Completed'
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -40
```

For a specific pod:

```bash
kubectl -n <ns> describe pod <pod>
kubectl -n <ns> logs <pod> --tail=200
kubectl -n <ns> logs <pod> --previous --tail=200
```

Check restart counts before reading logs — a repeatedly restarted pod often has the useful error in
`--previous`.

### 7. Storage

```bash
kubectl -n longhorn-system get pods
kubectl get pvc -A | grep -v Bound
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get nodes.longhorn.io -n longhorn-system
```

Healthy: Longhorn manager/engine pods running, every PVC `Bound`, every volume `healthy` with the
expected replica count. Degraded replicas often surface as an app pod stuck `ContainerCreating`.

### 8. Gateway, TLS and DNS

```bash
kubectl -n envoy-gateway-system get pods,svc
kubectl get gateway,httproute -A
kubectl -n cert-manager get pods
kubectl get certificates -A
kubectl -n cert-manager get challenges,orders -A
kubectl -n external-dns get pods
kubectl get dnsendpoints -A 2>/dev/null || true
```

Healthy: certificates `READY=True` and not near expiry, no pending `Challenge`, gateway address
assigned, DNS records matching the gateway. DNS-01 issuance depends on IONOS credentials and on
DNS propagation — a failed challenge is usually credential or propagation, not the app.

### 9. Observability

```bash
kubectl -n kube-prom-stack get pods
kubectl -n loki get pods
kubectl -n tempo get pods
kubectl -n elastic get pods
kubectl -n grafana get pods
```

If Prometheus targets are missing, use runbook `OBS-001`; for Loki ingestion use `OBS-004`.

### 10. External services

Vault and RustFS run **outside** the cluster on `node1`, so they will not appear as cluster
workloads. Check reachability from the runner, not from assumptions:

```bash
./ansible-runner/ansible-runner.sh bash -lc 'curl -sS -o /dev/null -w "%{http_code}\n" -k https://vault.homelab.ricsanfre.com/v1/sys/health'
```

For Vault, `503` usually means sealed; `200`/`429` mean it is up. For RustFS, verify the S3 endpoint
and that backups are still landing.

## Known failure modes in this cluster

| Symptom | Likely cause | Runbook |
| --- | --- | --- |
| API server unreachable, all nodes NotReady | etcd quorum loss or kube-vip endpoint | `CLUSTER-014` |
| API `ServiceUnavailable`; a node answers TCP 22 but never sends a banner | Control-plane node hung at userspace level (often under-voltage) | `CLUSTER-014` |
| `ping` to `10.0.0.x` fails, everything "looks down" | Gateway rejects IPv4 ICMP by design — not a fault | `CLUSTER-014` |
| Kustomization stuck `False`, no new revision | Git source cannot fetch (auth, branch, network) | `GITOPS-001` |
| One Kustomization `False`, others fine | Manifest/patch error or missing dependency | `GITOPS-002` |
| Terraform CR `error acquiring the state lock` | Stale lock from an interrupted runner | `GITOPS-007` |
| HelmRelease `False`, chart or values error | Chart version, schema change, stuck release | `GITOPS-003` |
| Pods `ContainerCreating`, PVC pending | Longhorn replica degradation or disk pressure | `CLUSTER-012` |
| App logs `connection refused` to Vault | Vault sealed or auth backend issue | `VAULT-001`, `VAULT-004` |
| Certificate not issued, Challenge pending | IONOS credentials or DNS propagation | `NET-005` |
| Served cert does not match secret | Stale secret / wrong gateway listener | `NET-008` |
| Keycloak login broken, CNPG unhealthy | Database failover or config drift | `KEYCLOAK-006`, `KEYCLOAK-008` |
| S3 backups failing | RustFS outage or credentials | `MINIO-001`, `MINIO-003` |
| Elasticsearch red/yellow | Disk watermark, node loss, shard allocation | `ELASTIC-001` |

## Stop conditions

Hand off to the runbook as soon as the failing layer is clear. Escalate to the user immediately when:

- the API server or etcd is unavailable;
- a node shows `DiskPressure` and workloads are being evicted;
- Vault is sealed and dependent apps are down;
- certificates are expired or a private key may be compromised;
- the evidence suggests data loss or a compromised node.

## Output

Report only what is abnormal, in this shape:

```
Symptom:  <what the user sees>
Evidence: <commands + key lines of output>
Layer:    <nodes | system | flux | helm | workloads | storage | gateway | observability | external>
Cause:    <most likely cause, confidence>
Next:     <runbook ID and first step>
```

If everything is healthy, say so explicitly and list the checks that passed. Do not invent problems.
