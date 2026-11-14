# ADR 0013: Migrate CloudNativePG Backups to the Barman Cloud Plugin

Date: 2026-11-01

## Status

Proposed

## Context

### Problem

CloudNativePG's in-tree Barman Cloud support is deprecated and scheduled for removal:

- Deprecated since CloudNativePG **1.26**.
- **1.31 is the last minor release that ships native Barman Cloud support.**
- Removed starting from **1.32.0**. Releases up to and including 1.31, and their patch releases, keep
  native support while they are themselves supported.

Both PostgreSQL clusters in this repository depend on that path:

| Cluster | Namespace | Size | Backup destination | Credentials | Retention |
| --- | --- | --- | --- | --- | --- |
| `postgres-keycloak` | `databases` | 5Gi | `s3://k3s-barman/postgres-keycloak` | `postgres-keycloak-s3-secret` | 30d |
| `postgres-ecommerce` | `databases` | 10Gi | `s3://k3s-barman/postgres-ecommerce` | `postgres-ecommerce-s3-secret` | 30d |

Both configure `.spec.backup.barmanObjectStore` inline in the `Cluster` resource and are archived by
the `postgres-keycloak-daily` / `postgres-ecommerce-daily` `ScheduledBackup` objects added in
`cf285699`. The restore procedure in `KEYCLOAK-003` also depends on the in-tree syntax through
`externalClusters[].barmanObjectStore`.

If the operator is upgraded to 1.32 without migrating, `barmanObjectStore` is no longer valid, WAL
archiving stops, scheduled backups fail, and both databases become unrecoverable. The failure is
silent until a restore is attempted.

### Current state

| Item | Value |
| --- | --- |
| Operator chart | `cloudnative-pg` **0.29.1** (app **1.30.1**) |
| Operator namespace | `databases` (not the upstream default `cnpg-system`) |
| Chart repository | `https://cloudnative-pg.github.io/charts` |
| Clusters | 2, both in `databases` |
| WAL archiving | `ContinuousArchiving=True` on both |
| Base backups | daily since 2026-11-01 |
| cert-manager | deployed |
| S3 backend | RustFS at `https://object-store.homelab.ricsanfre.com:9091` |

### Timeline pressure

As of 2026-11-01, 1.31 is not yet released; 1.30.x is the current supported series and reaches end of
life around Dec 2026. 1.32 is expected around Dec 2026 to Mar 2027. The migration must land before
`1.32.0` is adopted, and it is simpler to land it alongside the 1.31 upgrade than after it.

> **Note:** the operator running in this cluster warns that native support is removed in 1.31.0. That
> notice was accurate for CloudNativePG 1.30.0 but upstream has since moved the removal to 1.32.0.
> The plan below targets the stricter reading: be migrated before the 1.31 upgrade, which removes the
> deadline risk entirely.

### Decision

Adopt the **Barman Cloud Plugin** (`plugin-barman-cloud`), deployed as a Flux-managed HelmRelease in
the `databases` namespace beside the operator, and migrate both clusters from inline
`.spec.backup.barmanObjectStore` to an `ObjectStore` resource plus `spec.plugins`.

## Options Considered

### Option 1: Barman Cloud Plugin (selected)

The official CNPG-I successor. Configuration maps one-to-one from `barmanObjectStore` into an
`ObjectStore` CR, and the on-disk backup format is unchanged.

- **Pros:**
  - Only option that preserves object-store backup plus point-in-time recovery to the existing RustFS
    path, with no data migration.
  - Official CloudNativePG project with a steady release cadence (v0.15.1, 2026-09-30).
  - Ships as a Helm chart in the same repository already used for the operator (chart `0.8.1`).
  - Both images verified multi-arch `amd64`/`arm64`: `plugin-barman-cloud:v0.15.1` and
    `plugin-barman-cloud-sidecar:v0.15.1`.
  - Existing secret references carry over unchanged.
  - Backups written now are readable by the plugin, so the switch can be validated before commitment.
- **Cons:**
  - Extra deployment and a new CRD (`ObjectStore`, `barmancloud.cnpg.io/v1`) to manage.
  - Must be installed in the operator's namespace, which here is `databases`, not `cnpg-system`.
  - Injects a sidecar into every PostgreSQL instance; footprint is unmeasured in this cluster.
  - Migrating triggers a rolling restart of each cluster.
  - Backup metrics are renamed (see Consequences).

### Option 2: Volume snapshots only (`ScheduledBackup.spec.method: volumeSnapshot`)

Use CNPG's native volume-snapshot backups against Longhorn. The cluster already has
`csi-external-snapshotter-app` running and VolumeSnapshotClasses `longhorn`, `longhorn-snapshot-vsc`
and `longhorn-backup-vsc`.

- **Pros:**
  - No Barman, no sidecar, no new deployment; lowest operational and memory cost.
  - Very fast backup and restore for in-cluster recovery.
- **Cons:**
  - Not off-cluster and not portable: snapshots live in Longhorn, so a cluster-loss or ransomware
    scenario is not covered.
  - No point-in-time recovery and no database-aware consistency guarantees comparable to PITR.
  - Contradicts the standing requirement that stateful services have an S3 backup path.

Rejected as the primary mechanism. Worth revisiting as a **complement** for fast local rollback.

### Option 3: Stay pinned on 1.30/1.31 and defer

- **Pros:** zero effort now; native support keeps working through 1.31.
- **Cons:** 1.31 is the final minor release with native support, and 1.30.x reaches end of life around
  Dec 2026. Deferral converts an upgrade into a combined operator upgrade plus backup migration, with
  no room to roll back. Accepted only as a short time-box, not as a strategy.

### Option 4: Velero PVC backups as the database backup

Velero is already deployed and backs up Longhorn volumes.

- **Pros:** tooling already present; covers whole namespaces.
- **Cons:** a crash-consistent filesystem copy of a running database is not a database-aware backup.
  Restores can be inconsistent, and there is no WAL replay or PITR.

Rejected as the primary mechanism.

### Option 5: Replace CloudNativePG with another operator (PGO, StackGres)

Rejected without a proof of concept: it moves two live databases to a different control plane, loses
the CNPG fit with Flux and the existing runbooks, and costs far more than the plugin migration the
upstream project already provides.

## Scoring

Weights reflect this cluster: homelab budget, 8-16 GB nodes, GitOps-only changes, off-cluster DR
requirement. Scored 1-5; ARM64 and licensing are disqualifying, not weighted.

| Criterion | Weight | Barman Plugin | Snapshots only |
| --- | --- | --- | --- |
| Requirement fit (off-site + PITR) | 25% | 5 — only option that meets it | 2 — no off-site, no PITR |
| Maturity and activity | 15% | 4 — official, monthly cadence, still pre-1.0 | 4 — CNPG-native + Longhorn |
| ARM64 support | 10% | 5 — both images verified | 4 — Longhorn is multi-arch |
| Operational complexity | 10% | 3 — new deployment, CRD, sidecar | 4 — nothing new |
| Resource footprint | 10% | 3 — sidecar per instance, unmeasured | 5 |
| GitOps friendliness | 10% | 4 — Helm chart in existing repo | 5 |
| Security posture | 10% | 4 — reuses existing secrets and RBAC | 3 — in-cluster only |
| Integration fit | 5% | 4 — same S3, metrics renamed | 3 |
| Exit path | 5% | 4 — same barman format, reversible while 1.31 ships native | 2 — Longhorn-specific |
| **Weighted total** | | **4.15** | **3.45** |

The deciding factor is requirement fit: volume snapshots are cheaper to operate but do not deliver
off-cluster recoverability, which is the whole purpose of the backup.

"Defer" is deliberately not scored. It is a scheduling choice rather than a solution, and it fails the
requirement by definition: the removal happens regardless of when we migrate. Scoring it would average
away a hard constraint.

## Consequences

### Positive

- Backup capability is preserved across the 1.32 upgrade with no data migration.
- Cleaner model: the object store configuration and retention policy live in one `ObjectStore`
  resource shared by the cluster, its backups and its restores.
- The plugin is versioned independently of the operator, so backup fixes no longer require an operator
  upgrade.

### Negative

- One more controller to run and monitor on a power-constrained homelab.
- A sidecar is added to every PostgreSQL instance. With 2 instances per cluster and 4 in total, the
  memory cost must be measured before prod rollout.
- Each cluster takes a rolling restart when the migration is applied.

### Neutral

- Backup metrics are renamed. Nothing in this repository references the old names today (checked:
  no `cnpg_collector_*` in `kubernetes/`, `docs/` or `runbooks/`, and the bundled dashboard does not
  surface backup metrics), but any future alerting must use the new names:

  | Old | New |
  | --- | --- |
  | `cnpg_collector_last_failed_backup_timestamp` | `barman_cloud_cloudnative_pg_io_last_failed_backup_timestamp` |
  | `cnpg_collector_last_available_backup_timestamp` | `barman_cloud_cloudnative_pg_io_last_available_backup_timestamp` |
  | `cnpg_collector_first_recoverability_point` | `barman_cloud_cloudnative_pg_io_first_recoverability_point` |

## Migration Plan

Repository changes, in dependency order. Nothing is applied until the PoC below passes.

1. **Platform component** `kubernetes/platform/databases/plugin-barman-cloud/app/`
   - HelmRelease pinned to chart `0.8.1` (app `v0.15.1`) from the existing `cloudnative-pg`
     `HelmRepository`, in namespace `databases`.
   - New Flux Kustomization `plugin-barman-cloud-app` in `kubernetes/clusters/prod/infra/` with
     `dependsOn: cloudnative-pg-app`, registered in the infra `kustomization.yaml`.
2. **ObjectStore resources** in `kubernetes/platform/keycloak/database/base/` and
   `kubernetes/apps/e-commerce/config/databases/base/` — one per cluster, in namespace `databases`,
   translating each `.spec.backup.barmanObjectStore` verbatim into `.spec.configuration` and moving
   `retentionPolicy: 30d` to `.spec.retentionPolicy`.
3. **Cluster manifests** — in a single atomic change per cluster: delete `.spec.backup` entirely and
   add:

   ```yaml
   plugins:
   - name: barman-cloud.cloudnative-pg.io
     isWALArchiver: true
     parameters:
       barmanObjectName: postgres-keycloak   # or postgres-ecommerce
   ```

4. **ScheduledBackup** — switch from the in-tree default to the plugin:

   ```yaml
   method: plugin
   pluginConfiguration:
     name: barman-cloud.cloudnative-pg.io
   ```

5. **Restore path** — update `KEYCLOAK-003` (and the future `PG-001`) so recovery clusters use
   `externalClusters[].plugin` with `barmanObjectName` and `serverName`, instead of
   `externalClusters[].barmanObjectStore`.
6. **Rollout order** — `postgres-ecommerce` first (demo workload), then `postgres-keycloak` (IAM
   path). Take a fresh base backup immediately before each migration.

## Proof of Concept

Desk research only so far. The plugin must live in the operator's namespace, so it cannot be trialled
in a throwaway namespace of the production cluster without deploying a second operator. The PoC
belongs in the dev k3d cluster, in `test/cnpg-barman/`:

```bash
cd dev && make dev-up                 # cert-manager, cnpg (operator + plugin) profiles on
cd ../test/cnpg-barman
./poc.sh secrets                      # dev-only S3/CA secrets, never committed
./poc.sh phase-a                      # in-tree barmanObjectStore baseline, 2 instances
./poc.sh marker phase-a               # marker row + WAL switch + archiving check
./poc.sh backup intree                # base backup with the in-tree method
./poc.sh phase-b                      # ObjectStore + plugins switch (rolling restart)
./poc.sh marker phase-b               # WAL archived by the sidecar after the switch
./poc.sh backup plugin                # base backup with the plugin method
./poc.sh measure                      # sidecar CPU/memory per instance
./poc.sh restore                      # pg-poc-restore from the same object store
./poc.sh down                         # teardown, then `cd dev && make dev-down`
```

The operator and the plugin are deployed by the `cnpg` dev Flux profile
(`kubernetes/platform/databases/plugin-barman-cloud/app/overlays/dev`), so the PoC exercises the
same HelmRelease that the migration plan adds to production. `poc.sh` keeps the rest of the
resources imperative on purpose: they are throwaway and must not be reconciled onto `master`.

The rehearsal covers both halves of the migration: phase A archives and backs up with the in-tree
code, phase B performs the atomic switch on the same cluster and object-store prefix. The restore
cluster then reads a phase A base backup and replays WAL archived by the plugin, which is the
property that matters — the switch must not create an unrecoverable window.

Open questions the PoC must answer:

| Question | Why it matters |
| --- | --- |
| Does barman-cloud **3.20.1** (bundled in the sidecar) work against RustFS? | Native barman already does, but the sidecar ships a newer version than the operand image |
| Sidecar CPU/memory per instance | 4 instances total on 8-16 GB nodes |
| Does WAL archiving resume without a gap across the switch? | A gap means an unrecoverable window |
| Behaviour of the rolling restart on a 2-instance cluster | Temporary single-instance exposure |
| Does `endpointCA` need to be set in production? | The dev RustFS uses a private CA; the production endpoint may not |

## Risks

| Risk | Mitigation |
| --- | --- |
| Sidecar footprint degrades 8 GB nodes | Measure in the PoC; set explicit requests/limits in the chart values |
| WAL gap during migration | Take a base backup immediately before; verify `ContinuousArchiving=True` and a restore after |
| RustFS incompatibility with barman 3.20.1 | PoC gate before any prod change |
| Plugin chart supports only the latest plugin point release | Pin chart `0.8.1`; upgrade deliberately |
| Operator/plugin namespace coupling | Both stay in `databases`; document it in the service runbook |

## References

- CloudNativePG supported releases — https://cloudnative-pg.io/documentation/current/supported_releases/
- Object stores appendix (removal statement) — https://cloudnative-pg.io/docs/devel/appendixes/object_stores/
- Barman Cloud Plugin installation — https://cloudnative-pg.io/plugin-barman-cloud/docs/installation/
- Migration from built-in backup — https://cloudnative-pg.io/plugin-barman-cloud/docs/migration/
- Container images — https://cloudnative-pg.io/plugin-barman-cloud/docs/images/
- Plugin releases — https://github.com/cloudnative-pg/plugin-barman-cloud/releases
- Plugin Helm chart — https://github.com/cloudnative-pg/charts/tree/main/charts/plugin-barman-cloud
- `kubernetes/platform/databases/cloudnative-pg/app/base/helm.yaml` — operator chart pin
- `kubernetes/platform/keycloak/database/base/postgres-cluster.yaml` — Keycloak backup configuration
- `runbooks/components/keycloak.md` `KEYCLOAK-003` — restore procedure to update
