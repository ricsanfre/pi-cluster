# ADR 0010: Deploy Descheduler for Cluster-Wide Pod Distribution

Date: 2026-06-10

## Status

Proposed

## Context

### Problem

Workloads across the cluster are concentrating on a small subset of nodes, overloading them while other nodes sit nearly idle. This creates hot spots that degrade application availability and waste cluster capacity.

#### Observed symptoms

| Node | Arch | Memory | CPU Requested | Mem Requested | Actual CPU |
|------|------|--------|--------------|---------------|-------------|
| node-hp-1 | x86 | 16GB | 57% | 55% | 22% |
| node-hp-2 | x86 | 16GB | 51% | 68% | **8%** |
| node-hp-3 | x86 | 16GB | 100% | 65% | 39% |
| node5 | ARM64 | 8GB | 54% | 38% | ~100% |
| node6 | ARM64 | 8GB | 29% | 26% | **99%** |

- node-hp-2 is nearly idle (8% actual CPU, ~5GB free memory) yet receives zero new pods
- node5 and node6 (ARM64) are CPU-saturated but continue to attract new pods
- When the e-commerce stack was recently redeployed, all 7 new pods landed on node5 simultaneously
- This pattern affects all namespaces, not just e-commerce

#### Root cause analysis

**1. Percentage-based scheduler scoring favors ARM nodes**

The Kubernetes default scheduler's `NodeResourcesFit` plugin uses a `LeastAllocated` strategy that scores nodes by *fraction* of free resources, not absolute capacity:

- node6: 74% memory free (percent) / ~6GB free (absolute) → high scheduler score
- node-hp-2: 32% memory free (percent) / ~5GB free (absolute) → low scheduler score

The ARM nodes (8GB) carry lighter baseline platform load than the x86 nodes (16GB), so their *percentage* free is higher even when *absolute* free memory is comparable. The scheduler interprets this as "ARM nodes are emptier."

**2. Scheduler is blind to actual utilization**

The scheduler evaluates only *requested* resources, not actual usage. node6 shows 29% CPU *requested* but runs at 99% *actual* CPU. The scheduler considers it an excellent candidate while the node is melting.

**3. No spreading constraints exist**

Only one workload in the entire cluster (Kafka) defines any `podAntiAffinity`. No deployments have `topologySpreadConstraints`. With `replicas: 1` being the norm, the scheduler has zero incentive to spread pods across nodes — it independently picks the single "best" node for each pod, and they all land on the same place.

**4. Control-plane taint reduces ARM targets**

node2/3/4 (ARM64) are tainted `control-plane:NoSchedule`, leaving only node5 and node6 as ARM schedulable nodes. When the scheduler prefers ARM nodes (for the reasons above), it has only two to choose from, accelerating hot-spot formation.

#### Why this can't be fixed with per-workload patches alone

Adding `topologySpreadConstraints` to individual deployments would help, but:
- It requires touching every Deployment/StatefulSet in the cluster
- Helm-managed charts are harder to patch consistently
- New workloads would regress unless the constraint is remembered
- It doesn't address the underlying scoring mismatch

### Decision

Deploy the [descheduler](https://github.com/kubernetes-sigs/descheduler) as a cluster-wide component that continuously detects and corrects scheduling imbalances by evicting pods from over-utilized nodes.

**Descheduler strategies enabled:**

| Strategy | Type | Purpose |
|----------|------|---------|
| `LowNodeUtilization` | Balance | Evict pods from nodes above `targetThresholds` (50% CPU/mem) when nodes exist below `thresholds` (20% CPU/mem) |
| `RemoveDuplicates` | Balance | Ensure no two pods from the same ReplicaSet/StatefulSet run on the same node |

**Deployment mode:** `Deployment` (continuous) with a 5-minute descheduling interval and leader election.

## Options Considered

### Option 1: Descheduler (selected)

Deploy the CNCF descheduler as a Kubernetes-native component.

- **Pros:**
  - Purpose-built for exactly this problem (upstream Kubernetes project)
  - Uses actual node utilization (via metrics-server), not just resource requests
  - Simple Helm chart, one-and-done deployment
  - No control-plane changes needed
  - Strategies are configurable and scoped (can exclude namespaces/workloads)
  - `RemoveDuplicates` handles the single-replica-spread case
- **Cons:**
  - Evicts running pods (controlled disruption)
  - Adds a small resource footprint (500m CPU, 256Mi memory requested)
  - Reacts after pods are scheduled, not during scheduling

### Option 2: Custom kube-scheduler configuration

Modify the K3s server's `kube-scheduler-arg` to pass a custom `KubeSchedulerConfiguration` with adjusted scoring weights.

- **Pros:**
  - Fixes scheduling at the source — pods land correctly the first time
  - No additional workload running in the cluster
- **Cons:**
  - Requires SSH access to control-plane nodes and `k3s` service restart
  - `LeastAllocated` → `RequestedToCapacityRatio` curve tuning is complex and error-prone
  - Still blind to actual utilization (only sees requests)
  - Risk of destabilizing scheduling for all workloads
  - Doesn't help pods already scheduled to hot nodes
  - K3s embeds the scheduler; changes require server restart

### Option 3: Kyverno/OPA mutating policy

Deploy a policy engine to inject `topologySpreadConstraints` into every Pod.

- **Pros:**
  - Enforces distribution at admission time
  - No eviction needed
- **Cons:**
  - Adds an entire policy engine (`~200MB` memory) for one policy
  - Policy authoring and testing overhead
  - Doesn't rebalance existing pods
  - `topologySpreadConstraints` doesn't cover all scheduling scenarios

## Consequences

### Positive

- Cluster nodes will be utilized more evenly, avoiding hot spots
- `LowNodeUtilization` will move pods off the overloaded ARM nodes (node5, node6) to the underutilized x86 nodes (node-hp-2)
- `RemoveDuplicates` will spread single-replica workloads across different nodes when multiple deployments share the same owner kind
- Pods evicted by the descheduler will be rescheduled by the standard scheduler, respecting PDBs and graceful termination

### Negative

- Evicted pods experience a brief disruption (Kubernetes handles this via graceful shutdown + reschedule)
- Descheduler itself consumes cluster resources (~500m CPU, 256Mi memory)
- Descheduler cannot evict pods protected by `DefaultEvictor` protections (pods with local storage, PDBs, mirror pods, critical addons)
- The descheduler's `nodeFit: true` (default) ensures evicted pods will fit on a target node, but this check uses the same resource *request* data the scheduler uses — actual utilization could still diverge

### Neutral

- Descheduler decisions are logged and observable via Prometheus metrics
- The component follows the same FluxCD GitOps deployment pattern as all other platform services

## References

- [Descheduler GitHub](https://github.com/kubernetes-sigs/descheduler)
- [Descheduler v0.36.0 release](https://github.com/kubernetes-sigs/descheduler/releases/tag/v0.36.0)
- [LowNodeUtilization strategy docs](https://github.com/kubernetes-sigs/descheduler?tab=readme-ov-file#lownodeutilization)
- [RemoveDuplicates strategy docs](https://github.com/kubernetes-sigs/descheduler?tab=readme-ov-file#removeduplicates)
