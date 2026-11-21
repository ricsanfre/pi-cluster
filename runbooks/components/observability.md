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
kubectl -n loki get pods
kubectl -n fluent get pods
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

Second common cause: **Fluent Bit ≥ 5.0.4 sending Forward protocol v1.5**. If `skip invalid event`
appears with `time=[..., {}]` and the fields themselves parse correctly, the agent is missing
`Retain_Metadata_In_Forward_Mode false` (`retain_metadata_in_forward_mode: false` in Helm values).
fluentd < 1.20 cannot decode that format and drops every event. See
[Fluent Bit upgrade notes](https://docs.fluentbit.io/manual/installation/upgrade-notes#forward-output-retain_metadata_in_forward_mode-default-changed-to-true).

Third common cause: **an output buffer overflow on the aggregator drops records for every sink.**
fluentd's `@type copy` is not isolated per store: `@OUTPUT_LOKI` and `@OUTPUT_ES` are stores of the
same `copy`, both with `retry_forever true`. When the Loki store cannot flush, its buffer fills and
the store throws (`BufferOverflowError`, `overflow_action=:throw_exception`), so the copy fails as a
unit and **Elasticsearch loses the same records**. This happened on 2026-11-20 between 14:39Z and
14:47Z while `loki-write` was OOM-looping.

Symptom: a gap in *both* sinks while the agents keep sending, with the output queue not draining:

```bash
kubectl -n fluent logs deploy/fluentd --since=15m | grep -E 'BufferOverflow|overflow_action'

# queue and retry counters are per store — check them before blaming the inputs
curl -sG "$PROM/api/v1/query" --data-urlencode 'query=fluentd_output_status_buffer_queue_length'
curl -sG "$PROM/api/v1/query" --data-urlencode 'query=fluentd_output_status_retry_count'
```

The fix is on the output side, not the input side: set `overflow_action` on the Loki store, or give
Loki its own `<match>` with a bounded buffer, so one jammed sink cannot starve the other.

**Confirming that one host is actually shipping**

`fluentd_input_status_num_records_total` is emitted by a `prometheus` filter **after** `in_forward`
accepts the event, and is labelled with the record's `hostname`. A sender whose events are rejected has
**no series at all**, so always compare per host — several agents emit the same `host.*` tags and a
cluster-wide total hides the missing one.

```bash
# accepted records per reporting host, last 15m
curl -sG "$PROM/api/v1/query" --data-urlencode 'query=sum by (hostname) (increase(fluentd_input_status_num_records_total{tag=~"host.*"}[15m]))'

# anything being rejected right now (one line per dropped event)
kubectl -n fluent logs deploy/fluentd --since=10m | grep -c 'skip invalid event'
```

Then confirm at the destination (`host="<name>"` in Loki, or the index in Elasticsearch): the input
counter proves the aggregator accepted the batch, not that it reached a sink.


Verify:

- New logs appear in Grafana Explore.
- Query latency/error rate returns to normal.
- Retention jobs complete without errors.

Rollback:

1. Revert recent Loki config/image changes.
2. Reconcile observability manifests and revalidate ingestion.
