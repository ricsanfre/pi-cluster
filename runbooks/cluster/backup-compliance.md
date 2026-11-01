# Backup and Compliance Runbooks

## BACKUP-001 Velero Namespace Restore Drill

<a id="runbook-backup-001"></a>
Runbook ID: `BACKUP-001`
Owner: Platform
Severity: `Maintenance`

Objective: Periodically validate namespace restore from Velero backups.

Preconditions:

- Valid recent backup exists.
- Target namespace for restore test agreed.

Procedure:

1. List backups and choose restore point.

## BACKUP-002 Velero Full-Cluster Restore Drill

<a id="runbook-backup-002"></a>
Runbook ID: `BACKUP-002`
Owner: Platform
Severity: `Maintenance`

Objective: Validate end-to-end disaster recovery readiness using full-cluster restore simulation.

Preconditions:

- Isolated test environment or dedicated recovery cluster.
- Recent backup and object store access validated.

Procedure:

1. Select backup snapshot and capture baseline metadata.

```bash
velero backup get
velero backup describe <backup-name> --details
```

2. Trigger full restore in test environment.

```bash
velero restore create restore-full-<test-id> --from-backup <backup-name>
```

3. Track restore progress and inspect warnings/errors.

```bash
velero restore get
velero restore describe restore-full-<test-id> --details
```

4. Validate core services (Flux, DNS, ingress, storage, observability).
5. Record RTO/RPO metrics and gaps.

Verify:

- Restore completed successfully.
- Core platform functionality passes smoke tests.
- Targeted stateful apps recover expected data.

Rollback:

1. Tear down test restore environment.
2. Keep logs/reports and open remediation tasks for failures.

## BACKUP-003 Backup Retention and Cleanup Execution

<a id="runbook-backup-003"></a>
Runbook ID: `BACKUP-003`
Owner: Platform
Severity: `Maintenance`

Objective: Enforce retention policy and prevent backup storage exhaustion.

Procedure:

1. Inventory current backup objects and sizes.

```bash
velero backup get
```

2. Compare current state against retention policy.
3. Delete expired backup objects in controlled batches.

```bash
velero backup delete <backup-name> --confirm
```

4. Verify backup storage health and free capacity.
5. Update policy docs if retention requirements changed.

Verify:

- Retention targets met.
- New backup jobs continue to succeed.

Rollback:

1. If accidental deletion occurs, escalate to object-storage versioning recovery (if enabled).
2. Temporarily pause cleanup automation until root cause is addressed.
