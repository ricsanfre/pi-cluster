# Kube-vip Control Plane HA Monitoring (Layer 2)

This document provides a comprehensive guide to configuring monitoring, alerting, and visualization for **kube-vip** when deployed exclusively for **Control Plane High Availability (HA)** using **Layer 2 (ARP)** mode. It has been validated against kube-vip **v1.2.0** and documents known gaps.

---

## 1. Important: Version-specific metric availability

Kube-vip's Prometheus application metrics (`kube_vip_*`) were introduced in **v1.2.0**. Earlier versions (v1.0.x and below) only serve Go runtime and process metrics on the `/metrics` endpoint.

| Version | `kube_vip_build_info` | `kube_vip_is_leader` | `kube_vip_leader_election_transitions_total` | `kube_vip_arp_packets_total` |
|---------|----------------------|---------------------|---------------------------------------------|------------------------------|
| v1.0.x  | Not registered        | Not registered       | Not registered                               | Not registered                |
| v1.2.0  | ✅ Populated          | Registered, **not populated in CP mode** | Registered, **not populated in CP mode** | Removed entirely              |

> **🔴 Critical finding (v1.2.0):** `kube_vip_is_leader` and `kube_vip_leader_election_transitions_total` are only populated by the **services** leader election code path (`svc_enable=true`). The **control plane** leader election (`cp_enable=true`) in `pkg/cluster/clusterLeaderElection.go` runs its own `OnStartedLeading`/`OnStoppedLeading` callbacks that never call `metrics.IsLeader.Set()` or `metrics.LeaderTransitionsTotal.Inc()`. This means in a control-plane-only deployment, these metrics are registered but permanently empty.

### Metric name changes across versions

| v0.6.x document name | v1.2.0 actual name | Labels (v1.2.0) |
|---|---|---|
| `kube_vip_is_leader` | `kube_vip_is_leader` | `node`, `lease_name` (was: `instance`) |
| `kube_vip_leader_changes_total` | `kube_vip_leader_election_transitions_total` | `lease_name` (was: none) |
| `kube_vip_arp_packets_total` | Removed | — |
| — | `kube_vip_build_info` (new) | `version`, `build`, `node` |

---

## 2. Working metrics in control-plane-only mode (v1.2.0)

When running with `cp_enable=true, svc_enable=false`, these are the only kube-vip application metrics that carry data:

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `kube_vip_build_info` | GaugeVec | `version`, `build`, `node` | Constant 1; tracks version/build per node |

**Additional data sources that work regardless of kube-vip version:**

| Source | Metric | What it provides |
|--------|--------|-----------------|
| PodMonitor `up` | `up{job="kube-system/kube-vip"}` | Per-pod scrape health |
| kube-state-metrics | `kube_daemonset_status_number_ready` | DaemonSet ready pod count |
| kube-state-metrics | `kube_daemonset_status_desired_number_scheduled` | Expected pod count |
| kube-state-metrics | `kube_daemonset_status_number_unavailable` | Unavailable pod count |
| kube-state-metrics | `kube_daemonset_status_number_misscheduled` | Pods on wrong nodes |

> **Note:** The PodMonitor job label follows the Prometheus Operator convention of `namespace/releaseName`. For a Helm release named `kube-vip` in `kube-system`, the label is `job="kube-system/kube-vip"`.

---

## 3. Helm deployment notes

Kube-vip is deployed as a DaemonSet via the Helm chart, not as a static pod as older documentation suggests.

```yaml
# kubernetes/platform/kube-vip/overlays/prod/values.yaml (key excerpts)
image:
  tag: "v1.2.0"  # Required for any kube_vip_* metrics

config:
  address: 10.0.0.10

env:
  cp_enable: "true"
  svc_enable: "false"
  vip_arp: "true"
  vip_leaderelection: "true"
  prometheus_server: ":2112"
```

The PodMonitor is enabled via a Kustomize monitoring component:

```yaml
# values.yaml in components/monitoring/
podMonitor:
  enabled: true
```

---

## 4. Alerting Rules (`PrometheusRule`)

Since the leader-specific metrics are not populated in control-plane mode, alerts focus on pod health, DaemonSet status, and metrics availability.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: kube-vip-alerts
  namespace: monitoring
  labels:
    prometheus: k8s
spec:
  groups:
  - name: kube-vip.rules
    rules:
    - alert: KubeVipMetricsMissing
      expr: absent(kube_vip_build_info)
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "Kube-vip metrics are not being reported"
        description: "Prometheus is not receiving metrics from any kube-vip pod. All kube-vip instances may be down or unreachable. The control plane VIP is unavailable."

    - alert: KubeVipPodDown
      expr: up{job="kube-system/kube-vip"} == 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Kube-vip metrics scrape failing on {{ $labels.instance }}"
        description: "The kube-vip metrics endpoint on {{ $labels.instance }} is not responding. The pod may be down or the Prometheus metrics server is failing on this node."

    - alert: KubeVipDaemonSetUnavailable
      expr: kube_daemonset_status_number_unavailable{namespace="kube-system", daemonset="kube-vip"} > 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Kube-vip DaemonSet has unavailable pods"
        description: "{{ $value }} kube-vip pod(s) are not available on control plane nodes. The API server VIP may fail over if the leader is affected."

    - alert: KubeVipDaemonSetMisscheduled
      expr: kube_daemonset_status_number_misscheduled{namespace="kube-system", daemonset="kube-vip"} > 0
      for: 10m
      labels:
        severity: info
      annotations:
        summary: "Kube-vip pods running on unexpected nodes"
        description: "{{ $value }} kube-vip pod(s) are scheduled on nodes that should not run the DaemonSet. Check node affinity rules."
```

### What's missing until upstream fix

The following alerts **cannot fire** until kube-vip wires metrics into the control plane leader election callbacks in `clusterLeaderElection.go`:

```yaml
# These will NOT work in cp_enable=true, svc_enable=false mode (v1.2.0):
- alert: KubeVipNoLeader
  expr: sum(kube_vip_is_leader) == 0
- alert: KubeVipMultipleLeaders
  expr: sum(kube_vip_is_leader) > 1
- alert: KubeVipFlappingLeader
  expr: increase(kube_vip_leader_election_transitions_total[5m]) > 3
```

The upstream fix requires adding these lines to `pkg/cluster/clusterLeaderElection.go`:
- `OnStartedLeading`: `metrics.LeaderTransitionsTotal.WithLabelValues(leaseID.Name()).Inc()` and `metrics.IsLeader.WithLabelValues(config.NodeName, leaseID.Name()).Set(1)`
- `OnStoppedLeading`: `metrics.IsLeader.WithLabelValues(config.NodeName, leaseID.Name()).Set(0)`

---

## 5. Grafana Dashboard

The dashboard focuses on pod health and DaemonSet status rather than leader election (since those metrics are not available in control-plane-only mode). It uses the `$datasource` templating variable for Prometheus data source selection.

### Panel layout

| # | Panel | Type | Query |
|---|-------|------|-------|
| 1 | Pods Scrapeable | stat | `count(up{job="kube-system/kube-vip"} == 1)` |
| 2 | Pods Down | stat | `count(up{job="kube-system/kube-vip"} == 0) OR vector(0)` |
| 3 | DaemonSet Ready | stat | `kube_daemonset_status_number_ready{namespace="kube-system", daemonset="kube-vip"}` |
| 4 | DaemonSet Desired | stat | `kube_daemonset_status_desired_number_scheduled{namespace="kube-system", daemonset="kube-vip"}` |
| 5 | Pod Status Detail | table | `up{job="kube-system/kube-vip"}` with UP/DOWN value mapping |
| 6 | Build Info per Node | table | `kube_vip_build_info` |

### Thresholds

- **Pods Scrapeable**: red below 1 → yellow 1-2 → green 3 (3 control plane nodes)
- **Pods Down**: green 0 → red ≥1
- **DaemonSet Ready**: red below 1 → yellow 1-2 → green 3
- **DaemonSet Desired**: red below 3 → green 3
- **Pod Status Detail**: red 0 / green 1 with `UP`/`DOWN` text mappings

### Deployment

The dashboard is deployed as a `GrafanaDashboard` CR via the Grafana Operator:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: grafana-dashboard-kube-vip
spec:
  allowCrossNamespaceImport: true
  folder: Kube-Vip
  instanceSelector:
    matchLabels:
      dashboards: grafana
  json: |-
    { ... }
```

See `kubernetes/platform/kube-vip/components/monitoring/grafana-dashboard.yaml` for the complete dashboard JSON.

---

## 6. Verification

After deploying, verify metrics are flowing:

```bash
# Check kube-vip image version (must be ≥ v1.2.0)
kubectl get daemonset -n kube-system kube-vip -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check that build_info is populated
kubectl port-forward -n kube-system pod/$(kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip -o name | head -1) 2112:2112 &
curl -s http://localhost:2112/metrics | grep kube_vip_build_info

# Check that up metric is present (note: job includes namespace)
kubectl port-forward -n kube-prom-stack svc/kube-prometheus-stack-prometheus 9090:9090 &
curl -s 'http://localhost:9090/api/v1/query?query=up{job="kube-system/kube-vip"}'

# Verify leader election is active (from kube-vip logs)
kubectl logs -n kube-system -l app.kubernetes.io/name=kube-vip --tail=10 | grep -i leader
```
