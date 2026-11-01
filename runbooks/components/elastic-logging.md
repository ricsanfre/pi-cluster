# Elastic and Logging Runbooks

## ELASTIC-001 Elasticsearch Red or Yellow Cluster Recovery

<a id="runbook-elastic-001"></a>
Runbook ID: `ELASTIC-001`
Owner: Observability Platform
Severity: `SEV-1` or `SEV-2`

Objective: Recover Elasticsearch cluster health and restore ingestion/query functionality.

Preconditions:

- Access to Elasticsearch API endpoint and admin credentials.

Procedure:

1. Check cluster health and shard allocation issues.

```bash
curl -s http://efk-es-http.elastic.svc:9200/_cluster/health?pretty
curl -s http://efk-es-http.elastic.svc:9200/_cat/shards?v
curl -s http://efk-es-http.elastic.svc:9200/_cluster/allocation/explain?pretty -H 'Content-Type: application/json' -d '{}'
```

2. Validate node availability, disk watermarks, and PVC capacity.
3. Resolve root cause:
  - Missing node or pod not ready.
  - Disk pressure/watermark exceeded.
  - Unassigned replica due to single-node constraints.
4. Reconcile Elastic stack config if template/policy drift is suspected.

```bash
flux reconcile kustomization elastic-stack-config -n flux-system --with-source
```

Verify:

- Cluster health returns to expected state for environment.
- Ingestion resumes (Fluent Bit/Fluentd pipelines healthy).
- Kibana queries return expected data.

Rollback:

1. Revert recent index template/ILM/config changes.
2. Temporarily reduce replica requirements in low-capacity incidents.
