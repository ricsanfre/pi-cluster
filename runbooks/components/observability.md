# Monitoring and Tracing Runbooks

## OBS-001 Prometheus Target Missing Triage

<a id="runbook-obs-001"></a>
Runbook ID: `OBS-001`
Owner: Observability Platform
Severity: `SEV-2`

Objective: Restore monitoring visibility when scrape targets disappear or are down.

Procedure:

1. Identify missing targets in Prometheus UI and confirm namespace/workload impact.
2. Check ServiceMonitor/PodMonitor existence and selector alignment.

```bash
kubectl get servicemonitor,podmonitor -A | grep -i <target>
kubectl -n <ns> get svc,pods --show-labels
```

3. Validate scrape endpoint reachability and TLS/auth requirements.
4. Check Prometheus and operator logs.

```bash
kubectl -n monitoring logs deploy/kube-prometheus-stack-operator --tail=200
kubectl -n monitoring get pods
```

5. Fix labels/selectors/ports/certs in Git and reconcile.

Verify:

- Target appears as `UP` in Prometheus.
- Alert noise related to missing target clears.

Rollback:

1. Revert monitor changes to last known-good commit.
2. Reconcile monitoring Kustomization.

## OBS-004 Loki Ingestion and Retention Issues

<a id="runbook-obs-004"></a>
Runbook ID: `OBS-004`
Owner: Observability Platform
Severity: `SEV-2`

Objective: Restore Loki ingestion/query health and retention behavior.

Procedure:

1. Check Loki and agent pod health.

```bash
kubectl -n monitoring get pods | grep -i loki
kubectl -n monitoring logs deploy/loki --tail=200
```

2. Validate ingest path from Fluent Bit/Promtail to Loki endpoint.
3. Check object storage connectivity and auth for chunks/index.
4. Verify retention/compaction settings and available storage.
5. Reconcile observability stack config if drift is suspected.

Verify:

- New logs appear in Grafana Explore.
- Query latency/error rate returns to normal.
- Retention jobs complete without errors.

Rollback:

1. Revert recent Loki config/image changes.
2. Reconcile observability manifests and revalidate ingestion.
