# Descheduler — Cluster Pod Distribution

Design and configuration of the Kubernetes descheduler in the Pi Cluster, including the metrics-server prerequisite changes required for reliable operation.

## Overview

The descheduler is a Kubernetes component that monitors node utilization and evicts pods from over-utilized nodes so they can be rescheduled onto under-utilized ones. It addresses a fundamental limitation of the default kube-scheduler: the scheduler makes a point-in-time decision at pod creation and never re-evaluates pod placement. Over time, workloads drift toward nodes that score higher by the scheduler's percentage-based ranking, creating hot spots.

### Why the scheduler alone isn't enough

The cluster has a **hybrid architecture** — three x86 nodes (16GB RAM each) and four ARM64 nodes (8GB each). The Kubernetes default scheduler uses `NodeResourcesLeastAllocated` scoring, which ranks nodes by *percentage* of free resources:

| Factor | x86 node (node-hp-2, 16GB) | ARM node (node6, 8GB) |
|--------|---------------------------|----------------------|
| Platform service baseline | ~5GB allocated | ~2GB allocated |
| Free memory (absolute) | ~11GB | ~6GB |
| Free memory (percent) | 68% | 74% |
| Scheduler score | **lower** | **higher** |

The ARM nodes carry less platform overhead so their *percentage* free is higher — even though x86 nodes have more absolute capacity. The scheduler preference for higher-percentage-free nodes, combined with a complete absence of spreading constraints, means workload pods pile onto ARM nodes until they melt, while x86 nodes sit nearly idle.

The descheduler fixes this by using **actual node utilization** (from the metrics-server), not resource requests, to detect and correct imbalances continuously.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    kube-scheduler                        │
│  Places pods initially (percentage-based scoring)        │
└────────────────────┬────────────────────────────────────┘
                     │ pods land on "best" node at creation
                     ▼
┌─────────────────────────────────────────────────────────┐
│                 Cluster Nodes                            │
│  node-hp-1/2/3 (x86, 16GB)  node5/6 (ARM64, 8GB)      │
│  node2/3/4 (ARM64, control-plane, tainted)              │
└────────┬────────────────────────┬───────────────────────┘
         │                        │
         │  kubelet metrics        │  evict pods
         │  (every 30s)            │
         ▼                        │
┌─────────────────────┐           │
│   metrics-server    │           │
│  (kube-system)      │──────────▶│
│  25s scrape timeout │  provides │
│  30s resolution     │  actual   │
└─────────────────────┘  metrics  │
                                  │
                         ┌────────┴──────────────┐
                         │     descheduler        │
                         │    (kube-system)       │
                         │  Deployment, 5m cycle  │
                         │                        │
                         │  LowNodeUtilization:   │
                         │   thresholds:   20%    │
                         │   targetThresh: 50%    │
                         │                        │
                         │  RemoveDuplicates      │
                         └────────────────────────┘
```

### Component relationship

1. **metrics-server** scrapes kubelet metrics from every node and exposes them via the `metrics.k8s.io/v1beta1` API
2. **descheduler** queries the metrics API every 5 minutes to get actual CPU/memory/pod counts
3. Descheduler compares actual utilization against configured thresholds to classify nodes
4. Pods on overutilized nodes are evicted (respecting protections: system-critical, PVCs, DaemonSets)
5. kube-scheduler reschedules evicted pods onto valid nodes

## Metrics-server configuration

The descheduler depends on the metrics-server for accurate, timely node metrics. The default metrics-server configuration was insufficient for this cluster.

### Problem: stale metrics on busy nodes

When a node hits high CPU utilization (e.g., node6 at 99%), its kubelet becomes unresponsive to metrics scrape requests within the default 10-second timeout. The metrics-server logs:

```
E0613 09:56:58 scraper.go:147] "Failed to scrape node, timeout to access kubelet"
  node="node6" timeout="10s"
```

This creates a **death spiral**:

```
node6 CPU at 99%
  → kubelet can't respond within 10s
  → metrics-server returns stale metrics (e.g., 45% CPU instead of 99%)
  → descheduler classifies node6 as "appropriately utilized" (below 50%)
  → no pods evicted from node6
  → node6 stays at 99% CPU
  → repeat forever
```

Additionally, when the metrics-server blocks on timeout for one node, the scrape cycle backs up and other nodes' metrics go stale too — causing the descheduler to see phantom spikes on idle nodes.

### Fix: increased scrape timeout

**File:** `kubernetes/platform/metrics-server/app/base/values.yaml`

```yaml
args:
  - --kubelet-request-timeout=25s   # default 10s → 25s (gives busy kubelets time)
  - --kubelet-insecure-tls          # K3s kubelets use self-signed certs
  - --metric-resolution=30s         # must be strictly > kubelet-request-timeout
```

**Constraint:** metrics-server enforces `metric-resolution > kubelet-request-timeout`. Setting both to 30s causes a panic:

```
panic: metric-resolution should be larger than kubelet-request-timeout
```

**HelmRelease:** `kubernetes/platform/metrics-server/app/base/helm.yaml`
- Chart: `metrics-server` v3.13.0 from `https://kubernetes-sigs.github.io/metrics-server`
- Target namespace: `kube-system`

## Descheduler configuration

### Deployment

**Flux Kustomization:** `kubernetes/clusters/prod/infra/descheduler-app.yaml`
- Path: `./kubernetes/platform/descheduler/app/overlays/prod`
- Target namespace: `kube-system`
- Prune and wait enabled

**HelmRelease:** `kubernetes/platform/descheduler/app/base/helm.yaml`
- Chart: `descheduler` v0.36.0 from `https://kubernetes-sigs.github.io/descheduler`
- Mode: `Deployment` (continuous, not CronJob)
- Interval: every 5 minutes
- Leader election: enabled (required for Deployment mode)

### Descheduler policy

**File:** `kubernetes/platform/descheduler/app/base/values.yaml`

```yaml
deschedulerPolicyAPIVersion: descheduler/v1alpha2
deschedulerPolicy:
  profiles:
    - name: default
      pluginConfig:
        - name: DefaultEvictor
          args:
            nodeFit: false       # See "nodeFit and control-plane taints" below
            evictSystemCriticalPods: false
            evictLocalStoragePods: false
            podProtections:
              extraEnabled:
              - PodsWithPVC     # Don't evict pods with PersistentVolumeClaims
        - name: LowNodeUtilization
          args:
            thresholds:          # Node is "underutilized" below these values
              cpu: 20
              memory: 20
              pods: 20
            targetThresholds:     # Node is "overutilized" above these values
              cpu: 50
              memory: 50
              pods: 50
        - name: RemoveDuplicates
      plugins:
        balance:
          enabled:
          - RemoveDuplicates
          - LowNodeUtilization
```

### Strategies

#### LowNodeUtilization

Identifies overutilized and underutilized nodes based on **actual** CPU, memory, and pod counts (from metrics-server), then evicts pods from overutilized nodes so they can be rescheduled onto underutilized ones.

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `thresholds.cpu` | 20% | Node below 20% CPU → underutilized (eviction target) |
| `thresholds.memory` | 20% | Node below 20% memory → underutilized |
| `thresholds.pods` | 20% | Node below 20% pod capacity → underutilized |
| `targetThresholds.cpu` | 50% | Node above 50% CPU → overutilized (eviction source) |
| `targetThresholds.memory` | 50% | Node above 50% memory → overutilized |
| `targetThresholds.pods` | 50% | Node above 50% pod capacity → overutilized |

Nodes between 20% and 50% on all dimensions are "appropriately utilized" and left alone.

#### RemoveDuplicates

Ensures no two pods belonging to the same owner (ReplicaSet, StatefulSet, Job) run on the same node. This spreads single-replica deployments across nodes when multiple services share a common label or when multi-replica workloads get co-located.

### Pod protections (DefaultEvictor)

The descheduler will **not** evict:

| Protection | Reason |
|------------|--------|
| `system-cluster-critical` priority | Control-plane stability |
| DaemonSet pods | One-per-node by design |
| Pods with PVCs (`PodsWithPVC`) | Avoid storage disruption |
| Pods with local storage (`PodsWithLocalStorage`) | Prevent data loss |
| Mirror pods | Kubelet-managed |
| Static pods | Kubelet-managed |

### nodeFit and control-plane taints

`nodeFit: false` requires explanation.

The default `nodeFit: true` runs each pod candidate through the scheduler framework's filter plugins against every node before eviction. But the cluster has three control-plane nodes (node2/3/4) tainted with `node-role.kubernetes.io/control-plane:NoSchedule`. No workload pod tolerates this taint.

The descheduler evaluates pods against **all** nodes, including the tainted ones. When a pod fails the taint check on even one node, the descheduler skips eviction entirely — even though the pod would fit fine on the untainted underutilized nodes (like node-hp-3).

With `nodeFit: false`, the descheduler evicts pods without pre-checking target node compatibility. This is safe because:
- kube-scheduler correctly handles taint filtering during rescheduling
- The underutilized target nodes (e.g., node-hp-3) have no taints
- All workload images are multi-arch (can run on x86 or ARM64)

## Files

| File | Purpose |
|------|---------|
| `design/adr/0010-descheduler-for-pod-distribution.md` | Architecture Decision Record |
| `kubernetes/platform/descheduler/app/base/helm.yaml` | HelmRepository + HelmRelease |
| `kubernetes/platform/descheduler/app/base/values.yaml` | Descheduler policy and configuration |
| `kubernetes/platform/descheduler/app/base/kustomization.yaml` | Kustomize base |
| `kubernetes/platform/descheduler/app/base/kustomizeconfig.yaml` | Name reference config |
| `kubernetes/platform/descheduler/app/overlays/prod/kustomization.yaml` | Prod overlay (namespace: kube-system) |
| `kubernetes/platform/descheduler/app/overlays/prod/helm-patch.yaml` | Adds overlay values ConfigMap ref |
| `kubernetes/platform/descheduler/app/overlays/prod/values.yaml` | Prod-specific values |
| `kubernetes/platform/descheduler/app/overlays/dev/kustomization.yaml` | Dev overlay (replicas: 0, disabled in k3d) |
| `kubernetes/platform/descheduler/app/overlays/dev/values.yaml` | Dev values |
| `kubernetes/clusters/prod/infra/descheduler-app.yaml` | Flux Kustomization CR |
| `kubernetes/platform/metrics-server/app/base/values.yaml` | Metrics-server args (25s timeout, 30s resolution) |

## Troubleshooting

### All pods skipped with "doesn't tolerate node taint"

The underutilized nodes include tainted control-plane nodes. Verify with:

```bash
kubectl logs -n kube-system deployment/descheduler | grep "Node has been classified"
```

If the only underutilized nodes are control-plane (e.g., node3), and `nodeFit: true`, all evictions will be blocked. Set `nodeFit: false` in the descheduler values or lower thresholds so an untainted node qualifies as underutilized.

### Descheduler doesn't detect overutilized nodes

Check that the metrics-server is successfully scraping all nodes:

```bash
kubectl logs -n kube-system deployment/metrics-server | grep "Failed to scrape"
```

If timeouts appear, increase `--kubelet-request-timeout` (ensuring it remains strictly less than `--metric-resolution`).

### Verifying descheduler operation

```bash
# See node classification
kubectl logs -n kube-system deployment/descheduler | grep "classified"

# See eviction decisions
kubectl logs -n kube-system deployment/descheduler | grep "Evicting\|evicted"

# Check HelmRelease health
flux get helmrelease -n kube-system descheduler
```

🤖 Generated with [Claude Code](https://claude.com/claude-code)
