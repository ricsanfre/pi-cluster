# S3 Storage (RustFS) Runbooks

> Runbook IDs retain the historical `MINIO-*` prefix for continuity.
> The object store actually deployed in this cluster is RustFS (S3-compatible).

## MINIO-001 MinIO Service Degradation Triage

<a id="runbook-minio-001"></a>
Runbook ID: `MINIO-001`
Owner: Platform Storage
Severity: `SEV-1` or `SEV-2`

Objective: Restore MinIO availability and S3 operations.

Procedure:

1. Check MinIO pods, service endpoints, and logs.

```bash
kubectl -n minio get pods,svc,endpoints
kubectl -n minio logs deploy/minio --tail=200
```

2. Validate object store credentials and TLS configuration.
3. Check backing storage health and capacity.
4. Confirm client operations using `mc` (list buckets, put/get object).
5. Reconcile MinIO manifests if configuration drift is suspected.

Verify:

- MinIO API and console endpoints respond.
- Backup systems and S3 clients recover.

Rollback:

1. Revert recent MinIO config/image changes in Git.
2. Reconcile MinIO Kustomization.
