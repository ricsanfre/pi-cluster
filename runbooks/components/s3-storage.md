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

## MINIO-005 MinIO (RustFS) Upgrade and Rollback

<a id="runbook-minio-005"></a>
Runbook ID: `MINIO-005`
Owner: Platform Storage
Severity: `Maintenance`

Objective: Upgrade the RustFS server binary (`rustfs_server_version`) on `node1` without losing object
data, and roll back safely if the new release changes the on-disk layout.

The `MINIO-*` prefix is historical — the deployed object store is **RustFS**, installed as a binary and
a systemd unit by the `ricsanfre.rustfs` role. There is no container in production (the `image:` entry
in `dev/external-services/compose.yaml` is the k3d dev environment only).

Preconditions:
- `~/.secrets/vault.env` present (the playbook reads `secret/s3/rustfsadmin` from Vault) and Vault
  **unsealed** — the play aborts at the credential assert before touching the binary if it is not.
- No backup in flight, and the window is **outside 02:30–04:00 UTC** (CNPG base backups 02:30/02:45,
  restic timer 03:00, Velero `full` schedule 04:00).
- `ls /tmp/rustfs` is empty. The role's `unarchive` uses `creates: /tmp/rustfs`, so a leftover file from
  a failed run makes it skip extraction and reinstall the **old** binary.

**Every consumer below reads and writes this object store.** An upgrade that goes wrong does not lose
"the backups" — it loses the Velero backups, the Longhorn backup target, both CNPG PITR archives, all
restic repositories, and Loki/Tempo storage at the same time.

| Consumer | Use | Schedule (UTC) |
| --- | --- | --- |
| CNPG `postgres-keycloak` | barman WAL archiving (continuous) + base backup | daily 02:30 |
| CNPG `postgres-ecommerce` | barman WAL archiving (continuous) + base backup | daily 02:45 |
| restic (8 hosts) | node backup repositories, `s3:…/restic` | daily 03:00 |
| Velero | BSL `default` + VolumeSnapshot backups | daily 04:00 |
| Longhorn | `BackupTarget/default` → `s3://k3s-longhorn@eu-west-1/`; **polls the target every 300 s** (`defaultBackupStore.pollInterval`), so a full sync plus Velero's snapshot uploads | continuous poll + Velero runs |
| Loki | chunks + index, continuous writes | continuous |
| Tempo | trace blocks, continuous writes + flushes | continuous |

Procedure:

1. Capture the healthy state of every consumer, so a post-upgrade failure is attributable.

```bash
curl -sk -o /dev/null -w '%{http_code}\n' https://object-store.homelab.ricsanfre.com:9091   # 403
kubectl --context picluster-prod -n velero get backupstoragelocation default -o jsonpath='{.status.phase}'
kubectl --context picluster-prod -n databases get cluster -o json \
  | jq -r '.items[]|"\(.metadata.name) \([.status.conditions[]?|select(.type=="ContinuousArchiving")|.status])"'
kubectl --context picluster-prod -n longhorn-system get backuptargets.longhorn.io default \
  -o jsonpath='{.spec.backupTargetURL}{"  available="}{.status.available}{"\n"}'
kubectl --context picluster-prod -n velero get backups --no-headers | head -3
./ansible-runner/ansible-runner.sh ansible s3 -i inventory.yml -b -m shell \
  -a "systemctl is-active rustfs; /usr/local/bin/rustfs --version | grep 'git tag'; du -sh /storage/rustfs"
```

2. Take the safety copy. Bulk pass while running, then a delta with the service stopped so the copy is
   consistent and the outage lasts seconds, not minutes.

```bash
rsync -a /storage/rustfs/ /storage/rustfs.bak-<current-version>/
systemctl stop rustfs
rsync -a --delete /storage/rustfs/ /storage/rustfs.bak-<current-version>/
systemctl start rustfs
```

3. Optionally quiesce the schedules for a zero-failure run, and undo it in step 6.

```bash
kubectl --context picluster-prod -n velero patch schedule full --type merge -p '{"spec":{"paused":true}}'
kubectl --context picluster-prod -n databases patch scheduledbackup postgres-keycloak-daily \
  --type merge -p '{"spec":{"suspend":true}}'
kubectl --context picluster-prod -n databases patch scheduledbackup postgres-ecommerce-daily \
  --type merge -p '{"spec":{"suspend":true}}'
# restic has no cluster object: stop restic-backup.timer on the 8 hosts, or stay out of 03:00 UTC
```

4. Bump `rustfs_server_version` in `ansible/vars/picluster.yml` and deploy.

```bash
make deploy-rustfs
```

The role compares `rustfs --version` with `rustfs_server_version`, downloads the release zip with
SHA256SUMS verification, copies it to `/usr/local/bin/rustfs`, and notifies `Restart rustfs`. The unit
is `Type=notify`, so systemd waits for the readiness notification before the play continues.

5. Expect a short S3 outage while the unit restarts. Velero, Loki, Tempo and CNPG retry; in-flight
   **DELETE** requests may return **503** right after the switch (upstream 1.0.5 upgrade note) — retry
   them. Single node, so there is no mixed-version window.

Verify:

- `/usr/local/bin/rustfs --version` reports the new tag, and `systemctl is-active rustfs` is `active`.
- Root endpoint returns `403`; the Velero `BackupStorageLocation default` is `Available`.
- Both CNPG clusters report `ContinuousArchiving=True`; check `pg_wal` has not grown abnormally.
- Longhorn `BackupTarget/default` reports `available=true` again after the next 300 s poll, and one test
  backup completes to S3.
- `/etc/restic/restic-wrapper.sh cat config` succeeds (repository still readable).
- Loki ingestion rate is non-zero and Tempo `failed_flushes_total` stays flat across one flush cycle.
- A second `make deploy-rustfs` reports **no changes** (role idempotency).
- Unpause/resume what step 3 paused.

Rollback:

1. Reinstall the previous binary — the role detects the version mismatch and swaps it back:

```bash
./ansible-runner/ansible-runner.sh ansible-playbook deploy_rustfs.yml -e rustfs_server_version=<previous>
```

2. If a release migrated the on-disk layout (1.0.5 changed inline-layout and delete-recovery handling),
   a binary rollback alone is not sufficient — restore the copy:

```bash
systemctl stop rustfs
mv /storage/rustfs /storage/rustfs.failed-<new-version>
cp -a /storage/rustfs.bak-<current-version> /storage/rustfs
systemctl start rustfs
```

3. Re-verify every consumer before unpausing the schedules.

References:
- `ansible/deploy_rustfs.yml`, `ansible/vars/picluster.yml` (`rustfs_server_version`)
- `ansible/requirements.yml` (`ricsanfre.rustfs`)
- `kubernetes/clusters/prod/config/cluster-settings.yaml` (`S3_SERVER`)
- `kubernetes/platform/longhorn/app/components/backup/values.yaml` (backup target)
- RustFS release notes for upgrade restrictions
