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

## BACKUP-004 restic Agent Upgrade

<a id="runbook-backup-004"></a>
Runbook ID: `BACKUP-004`
Owner: Platform
Severity: `Maintenance`

Objective: Upgrade the restic binary on the eight backup hosts (`restic_version`) and confirm the
repositories are still usable — without silently leaving the old binary in place.

**A `restic_version` bump alone does nothing.** `ricsanfre.backup` gates the install task on
`not restic_binary.stat.exists or restic_force_install`, `restic_force_install` defaults to `false`, and
the role never compares `restic --version` with `restic_version` (unlike `ricsanfre.vault` and
`ricsanfre.rustfs`). The upgrade therefore requires an explicit extra var.

The repository is **format version 2** and restic's migration (`restic migrate upgrade_repo_v2`) is
opt-in, never automatic — so no migration step is needed for an in-place upgrade, and none can be
triggered accidentally by bumping the binary.

Preconditions:
- RustFS healthy (the repository is `s3:{{ rustfs_url }}/restic`) — do `MINIO-005` first if both change.
- Outside the 03:00 UTC backup window; no `restic-backup.service` running.
- Shell access to the hosts through the runner (`ansible-runner.sh`).

Procedure:

1. Record the installed version on every host.

```bash
./ansible-runner/ansible-runner.sh ansible picluster -i inventory.yml -b -m command \
  -a "/usr/local/bin/restic version"
```

2. Confirm the repository is readable and note its format before changing anything.

```bash
./ansible-runner/ansible-runner.sh ansible s3 -i inventory.yml -b -m shell \
  -a "/etc/restic/restic-wrapper.sh cat config | jq -r .version"
```

3. Bump `restic_version` in `ansible/vars/picluster.yml` and run the playbook **with the force flag**:

```bash
./ansible-runner/ansible-runner.sh ansible-playbook backup_configuration.yml -e restic_force_install=true
```

`make configure-os-backup` runs the same playbook on `hosts: picluster` but passes no extra vars, so on
its own it reports success and installs nothing — that is the trap this runbook exists for.

4. The repo-init script is guarded (`restic cat config` first) so it will not re-initialise. If restic is
   upgraded on a subset of hosts, finish the rest before the next backup window.

Verify:

- `restic version` on all eight hosts reports the new version (the previous step's command, re-run).
- `/etc/restic/restic-wrapper.sh cat config` still returns version 2 and the same repository id.
- `/etc/restic/restic-wrapper.sh check --read-data-subset=1%` succeeds.
- The next scheduled `restic-backup.service` run completes (`systemctl list-timers restic-backup.timer`,
  then inspect `journalctl -u restic-backup`).

Rollback:

1. Re-run the playbook pinning the previous version and forcing the reinstall:

```bash
./ansible-runner/ansible-runner.sh ansible-playbook backup_configuration.yml \
  -e restic_version=<previous> -e restic_force_install=true
```

2. A repository already migrated to format 2 cannot be read by clients older than 0.17 — check
   `cat config` before downgrading further than that.

References:
- `ansible/backup_configuration.yml`, `ansible/vars/picluster.yml` (`restic_version`, `restic_repository`)
- `ansible/requirements.yml` (`ricsanfre.backup`)
- `runbooks/components/s3-storage.md#runbook-minio-005` (object store upgrade)
- restic migration docs: https://restic.readthedocs.io/en/stable/045_working_with_repos.html
