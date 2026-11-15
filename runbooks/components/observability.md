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

Common cause: unbounded label cardinality.

`429 maximum active stream limit exceeded` and an OOM-looping ingester usually mean one label
value is unbounded, not that the ingester is undersized. `host` is the usual culprit: an upstream
parse failure puts a blob (often a full JSON log line) in `host`, and every distinct value becomes
a new stream.

```bash
# in-memory streams for the ingester (a healthy homelab is dozens, not thousands)
kubectl -n loki get --raw "/api/v1/namespaces/loki/pods/loki-write-0:3100/proxy/metrics" \
  | grep -E '^loki_ingester_memory_streams'
```

Fluentd drops records whose `host` is not a plain hostname before the Loki output
(`@OUTPUT_LOKI`); those records still reach Elasticsearch. If the count is still in the thousands,
the malformed streams are persisted in the ingester WAL and are replayed on every restart — check
`msg="Recovered from WAL segments"`. Clearing `/var/loki/wal` while the ingester is stopped
discards them, at the cost of the unflushed Loki copy (Elasticsearch keeps the full history).

Verify:

- New logs appear in Grafana Explore.
- Query latency/error rate returns to normal.
- Retention jobs complete without errors.

Rollback:

1. Revert recent Loki config/image changes.
2. Reconcile observability manifests and revalidate ingestion.
