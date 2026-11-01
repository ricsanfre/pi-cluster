# Keycloak Runbooks

## Wipe and Recreate Keycloak Database from Scratch

<a id="runbook-keycloak-001"></a>
Runbook ID: `KEYCLOAK-001`
Owner: IAM Platform
Severity: `SEV-2` or `Maintenance`

Objective: Wipe Keycloak PostgreSQL data and recreate Keycloak state from Flux and tofu-controller.

Preconditions:

- Maintenance window approved.
- Backup/restore point validated.
- Cluster admin access available.

Warning: This is destructive. All Keycloak data in PostgreSQL is permanently deleted unless restored from backups.

Procedure:

1. Confirm target scope and object names.

- Flux namespace: `flux-system`
- Keycloak namespace: `keycloak`
- Database namespace: `databases`
- Flux Kustomizations:
  - `keycloak-database`
  - `keycloak-app`
  - `keycloak-config`
- CNPG cluster: `postgres-keycloak`
- CNPG database CR: `keycloak-db` (owned by the cluster; unrelated to the Kustomization name)
- Keycloak CR: `keycloak`
- Terraform CR (tofu-controller): `config-keycloak`

2. Suspend reconciliation to avoid race conditions.

```bash
flux suspend kustomization keycloak-config -n flux-system
flux suspend kustomization keycloak-app -n flux-system
flux suspend kustomization keycloak-database -n flux-system
```

3. Stop Keycloak app object (optional but recommended).

```bash
kubectl -n keycloak delete keycloak keycloak --ignore-not-found
```

4. Delete PostgreSQL cluster object.

```bash
kubectl -n databases delete cluster.postgresql.cnpg.io postgres-keycloak --ignore-not-found
```

5. Delete PostgreSQL PVCs (actual data wipe).

```bash
kubectl -n databases delete pvc -l cnpg.io/cluster=postgres-keycloak
```

6. Verify DB resources are gone.

```bash
kubectl -n databases get pvc -l cnpg.io/cluster=postgres-keycloak || true
kubectl -n databases get cluster.postgresql.cnpg.io postgres-keycloak || true
```

7. Recreate database layer first.

```bash
flux resume kustomization keycloak-database -n flux-system
flux reconcile kustomization keycloak-database -n flux-system --with-source
```

Wait until the CNPG cluster is Ready:

```bash
kubectl -n databases get cluster.postgresql.cnpg.io postgres-keycloak -o wide
kubectl -n databases get pods -l cnpg.io/cluster=postgres-keycloak
```

8. Recreate Keycloak application.

```bash
flux resume kustomization keycloak-app -n flux-system
flux reconcile kustomization keycloak-app -n flux-system --with-source
```

9. Re-apply Keycloak configuration through tofu-controller.

```bash
flux resume kustomization keycloak-config -n flux-system
flux reconcile kustomization keycloak-config -n flux-system --with-source
flux reconcile terraform config-keycloak -n flux-system
```

Verify:

```bash
kubectl -n keycloak get pods
kubectl -n databases get cluster.postgresql.cnpg.io
kubectl -n flux-system get terraform config-keycloak
kubectl -n flux-system describe terraform config-keycloak
```

Rollback:

1. Revert Keycloak-related Git changes if reconciliation fails repeatedly.
2. Restore DB from backup if wipe was accidental.

References:

- If a reconcile is still using an older Git revision, reconcile the source first.

```bash
flux reconcile source git flux-system -n flux-system
```

- If needed, inspect revisions for the Terraform object.

```bash
kubectl -n flux-system get terraform config-keycloak -o yaml | grep -E "lastAppliedRevision|lastAttemptedRevision|revision"
```

## Keycloak Config Reconcile and Drift Recovery

<a id="runbook-keycloak-002"></a>
Runbook ID: `KEYCLOAK-002`
Owner: IAM Platform
Severity: `SEV-2`

Objective: Recover `keycloak-config` when tofu-controller reconciliation fails or drifts from expected state.

Preconditions:

- Confirm latest Git revision is available in Flux source.
- Confirm `keycloak-app` is healthy before reconciling config.
- Confirm Keycloak API endpoint is reachable from `flux-system` runner context.

Procedure:

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization keycloak-config -n flux-system --with-source
flux reconcile terraform config-keycloak -n flux-system
```

Verify:

```bash
kubectl -n flux-system get terraform config-keycloak
kubectl -n flux-system describe terraform config-keycloak
kubectl -n flux-system get terraform config-keycloak -o yaml | grep -E "lastAppliedRevision|lastAttemptedRevision|Ready|reason|message"
```

Failure signature: `error running Init: Failed to get existing workspaces: Unauthorized`

Interpretation:

- This failure happens during OpenTofu backend initialization, before Vault provider login or Keycloak API calls.
- In this repository, tofu-controller uses the default Kubernetes backend, so workspace discovery means listing `tfstate-*` Secrets in `flux-system`.
- Treat this as runner access to the Terraform state backend failing, not as a Keycloak credential problem.

Targeted checks:

```bash
kubectl -n flux-system get secret tfstate-default-config-keycloak
kubectl -n flux-system get pods -l app.kubernetes.io/name=tofu-controller
kubectl -n flux-system get pod config-keycloak-tf-runner -o yaml | grep serviceAccountName -n
kubectl -n flux-system describe pod config-keycloak-tf-runner
```

Notes:

- The expected state Secret name is `tfstate-default-config-keycloak` when `.spec.workspace` is `default` and no custom backend suffix is set.
- If the runner Pod cannot list or get Secrets in `flux-system`, inspect tofu-controller chart RBAC/service account configuration before changing Vault or Keycloak settings.
- If this started after switching Flux back from a feature branch, verify the `GitRepository` branch and the applied revision are aligned before retrying reconciliation.

Rollback:

1. Revert last config commit and reconcile.
2. Suspend only `keycloak-config` if failures are noisy.

References:

- If revision is stale, reconcile Git source first.
- If provider auth fails, verify Vault role and secret values.
- If Keycloak API calls fail, verify `keycloak_url` FQDN and namespace routing.

## Restore Keycloak DB from CNPG Backup

<a id="runbook-keycloak-003"></a>
Runbook ID: `KEYCLOAK-003`
Owner: IAM Platform
Severity: `SEV-1` or `Maintenance`

Objective: Restore Keycloak PostgreSQL data from the object store into a recovery cluster, validate it,
and cut over.

Preconditions:

- Maintenance window is active.
- `postgres-keycloak-s3-secret` exists in `databases` and its credentials are valid.
- **A base backup exists.** Archived WAL alone cannot be recovered from. Confirm there is a restore
  point:

  ```bash
  kubectl -n databases get cluster postgres-keycloak \
    -o jsonpath='first={.status.firstRecoverabilityPoint}{"\n"}last={.status.lastSuccessfulBackup}{"\n"}'
  kubectl -n databases get backups.postgresql.cnpg.io
  ```

  Both values must be non-empty and at least one `Backup` must exist. **If they are empty, stop** —
  see the backup prerequisites at the end of this runbook.
- Note the S3 endpoint. The manifests use `${S3_SERVER}`, which only Flux substitutes:

  ```bash
  kubectl -n flux-system get configmap cluster-settings -o jsonpath='{.data.S3_SERVER}{"\n"}'
  ```

Procedure:

1. Suspend every Kustomization that owns or consumes the database. Suspending `keycloak-database` is
   mandatory: without it Flux re-applies the `Cluster` CR while you are restoring.

```bash
flux suspend kustomization keycloak-config -n flux-system
flux suspend kustomization keycloak-app -n flux-system
flux suspend kustomization keycloak-database -n flux-system
```

2. Create the recovery cluster. Use a distinct name so the original is untouched during validation.
   `serverName` is required: it tells barman which server's backups to read, and it defaults to the
   cluster name, which is no longer `postgres-keycloak` for the recovery cluster.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-keycloak-recovery
  namespace: databases
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:18.6
  storage:
    size: 5Gi
    storageClass: longhorn
  externalClusters:
  - name: origin
    barmanObjectStore:
      destinationPath: s3://k3s-barman/postgres-keycloak
      endpointURL: https://<S3_SERVER>:9091
      serverName: postgres-keycloak
      s3Credentials:
        accessKeyId:
          name: postgres-keycloak-s3-secret
          key: AWS_ACCESS_KEY_ID
        secretAccessKey:
          name: postgres-keycloak-s3-secret
          key: AWS_SECRET_ACCESS_KEY
  bootstrap:
    recovery:
      source: origin
```

Replace `<S3_SERVER>` with the value from the precondition. Omitting `recoveryTarget` restores to the
latest point; add one for point-in-time recovery.

3. Apply the manifest and wait for the recovery cluster to become ready.

```bash
kubectl apply -f postgres-keycloak-recovery.yaml
kubectl -n databases get cluster postgres-keycloak-recovery -o wide -w
```

4. Validate the recovered data before touching the original.

```bash
kubectl -n databases exec postgres-keycloak-recovery-1 -- \
  psql -U postgres -d keycloak -c '\dt'
kubectl -n databases exec postgres-keycloak-recovery-1 -- \
  psql -U postgres -d keycloak -Atc 'select count(*) from realm;'
```

A missing or implausibly small `realm` count means the wrong restore point. Delete the recovery
cluster and retry with an explicit `recoveryTarget`.

5. Cut over. Choose one option and record which was used.

Option A — preserve the `postgres-keycloak` name (recommended). Keycloak's host is hardcoded to
`postgres-keycloak-rw.databases.svc.cluster.local`, so keeping the name avoids any application change.

```bash
kubectl -n databases delete cluster postgres-keycloak-recovery
kubectl -n databases delete pvc -l cnpg.io/cluster=postgres-keycloak-recovery
kubectl -n databases delete cluster.postgresql.cnpg.io postgres-keycloak --ignore-not-found
kubectl -n databases delete pvc -l cnpg.io/cluster=postgres-keycloak
```

Then re-apply the manifest from step 2 with `metadata.name: postgres-keycloak`, keeping the
`externalClusters` entry but dropping its `serverName` (it then defaults to the cluster name). Wait for
`Ready=True` before resuming anything.

Option B — keep the recovery cluster and repoint Keycloak. Faster, but leaves `keycloak-database`
suspended until the names are reconciled.

- Change `db.host` in `kubernetes/platform/keycloak/app/base/keycloak.yaml` to
  `postgres-keycloak-recovery-rw.databases.svc.cluster.local`, commit, then
  `flux reconcile kustomization keycloak-app -n flux-system --with-source`.
- `database/base/postgres-cluster.yaml` still declares `postgres-keycloak`, so either rename the
  cluster in Git or keep `keycloak-database` suspended. Decide before closing the incident.

6. Resume the application layer.

```bash
flux reconcile kustomization keycloak-app -n flux-system --with-source
flux resume kustomization keycloak-config -n flux-system
flux reconcile kustomization keycloak-config -n flux-system --with-source
```

For Option A, also resume `keycloak-database` once the cluster exists and matches Git.

Verify:

```bash
kubectl -n databases get cluster.postgresql.cnpg.io
kubectl -n databases get pods -l app.kubernetes.io/name=postgresql
kubectl -n keycloak get pods
kubectl -n keycloak logs -l app=keycloak --tail=100
kubectl -n flux-system get terraform config-keycloak
```

- CNPG cluster `Ready=True` with `ContinuousArchiving=True`.
- Keycloak pods `Running` and the admin console reachable.
- `keycloak-app` and `keycloak-config` Kustomizations `Ready=True`.

Rollback:

1. Before cutover, delete the recovery cluster; the original is untouched.
2. After cutover, repoint `db.host` to the previous RW service and reconcile `keycloak-app`.
3. If the restored data is wrong, repeat from step 2 with an explicit `recoveryTarget.targetTime`.
   Never delete object-store paths to force a fresh start.

References:

- `kubernetes/platform/keycloak/database/base/postgres-cluster.yaml` — CNPG cluster and backup config.
- `kubernetes/platform/keycloak/app/base/keycloak.yaml` — `db.host`, needed for Option B.

**Backup prerequisites (2026-11-01).** `postgres-keycloak` is covered by the `postgres-keycloak-daily`
ScheduledBackup (02:30 daily, destination `s3://k3s-barman/postgres-keycloak`,
`retentionPolicy: 30d`); the first base backup completed on 2026-11-01. If `firstRecoverabilityPoint`
and `lastSuccessfulBackup` are ever empty again, the schedule has stopped working — investigate before
attempting a restore. Separately, native Barman support is removed in CloudNativePG 1.31 — migrate to
the Barman Cloud Plugin and update this runbook before upgrading the operator.

## Rotate Keycloak Admin Credentials (Vault + Keycloak)

<a id="runbook-keycloak-004"></a>
Runbook ID: `KEYCLOAK-004`
Owner: IAM Platform
Severity: `SEV-2` or `Maintenance`

Objective: Rotate admin credentials used by tofu-controller Keycloak provider.

Preconditions:

- Identify current Vault secret path (`keycloak/admin`).
- Ensure a fallback admin login exists.

Procedure:

1. Update `keycloak/admin` secret in Vault.
2. Reconcile `keycloak-config` Kustomization and Terraform CR.
3. Validate admin login and provider operations.

Verify:

```bash
kubectl -n flux-system get terraform config-keycloak
kubectl -n flux-system describe terraform config-keycloak
```

Rollback:

1. Restore previous admin secret values.
2. Reconcile `keycloak-config` again.

References:

- If auth fails, verify secret keys match module variables (`username`, `password`).

## Rotate OIDC Client Secrets (Grafana, Kiali, OAuth2-Proxy)

<a id="runbook-keycloak-005"></a>
Runbook ID: `KEYCLOAK-005`
Owner: IAM Platform
Severity: `SEV-2` or `Maintenance`

Objective: Rotate client credentials across Vault, Keycloak clients, and relying apps.

Preconditions:

- Inventory impacted clients and consuming apps.
- Communicate expected user session impact.

Procedure:

1. Update Vault secrets:
   - `grafana/oauth2`
   - `kiali/oauth2`
   - `oauth2-proxy/oauth2`
2. Reconcile `keycloak-config` Terraform.
3. Restart/reconcile consumers if they do not hot-reload secrets.

Verify:

```bash
kubectl -n flux-system get terraform config-keycloak
kubectl -n keycloak get keycloak keycloak
```

Rollback:

1. Restore previous client secrets in Vault.
2. Reconcile affected apps and `keycloak-config`.

References:

- `terraform/keycloak/resources/clients/*.json`

## Flux Kustomization Incident Triage

<a id="runbook-keycloak-006"></a>
Runbook ID: `KEYCLOAK-006`
Owner: IAM Platform
Severity: `SEV-2`

Objective: Standard triage flow for `keycloak-database`, `keycloak-app`, and `keycloak-config`.

Preconditions:

- Incident bridge opened and impact assessed.

Procedure:

```bash
flux get kustomizations -n flux-system | grep keycloak
kubectl -n flux-system describe kustomization keycloak-database
kubectl -n flux-system describe kustomization keycloak-app
kubectl -n flux-system describe kustomization keycloak-config
```

```bash
flux suspend kustomization <name> -n flux-system
flux resume kustomization <name> -n flux-system
flux reconcile kustomization <name> -n flux-system --with-source
```

Verify:

- All three Kustomizations converge to `Ready=True`.

Rollback:

1. Revert recent change and reconcile again.
2. Keep unstable leaf Kustomization suspended.

References:

- `kubernetes/clusters/prod/infra/keycloak-app.yaml`

## Tofu Controller Failure Modes

<a id="runbook-keycloak-007"></a>
Runbook ID: `KEYCLOAK-007`
Owner: IAM Platform
Severity: `SEV-2`

Objective: Fast diagnosis and recovery for Keycloak tofu-controller issues.

Preconditions:

- Access to `flux-system` controller logs.

Procedure:

```bash
kubectl -n flux-system get terraform config-keycloak
kubectl -n flux-system describe terraform config-keycloak
kubectl -n flux-system logs deploy/tofu-controller -c manager --tail=200
```

Verify:

- Terraform CR status shows `Ready=True`.

Rollback:

1. Revert module/config commit and reconcile.
2. Suspend `keycloak-config` until fixed.

References:

- Fix module output sensitivity and commit.
- Verify `keycloak_url` points to `keycloak` namespace service FQDN.
- Force reconcile source, kustomization, then terraform.

## CNPG Cluster Health and Failover Checks

<a id="runbook-keycloak-008"></a>
Runbook ID: `KEYCLOAK-008`
Owner: IAM Platform
Severity: `SEV-2`

Objective: Validate Keycloak DB health and failover readiness.

Preconditions:

- CNPG operator healthy.

Procedure:

```bash
kubectl -n databases get cluster.postgresql.cnpg.io postgres-keycloak -o wide
kubectl -n databases get pods -l cnpg.io/cluster=postgres-keycloak
kubectl -n databases describe cluster.postgresql.cnpg.io postgres-keycloak
```

Verify:

- Cluster `Ready=True`.
- Primary and replicas are running.
- Backup/WAL archiving status is healthy.
- PVC capacity and node placement are healthy.

Rollback:

1. Pause app/config reconciliation if DB unstable.
2. Execute restore/cutover runbook if failover does not recover service.

References:

- `KEYCLOAK-003`

## Namespace and Service DNS Debugging

<a id="runbook-keycloak-009"></a>
Runbook ID: `KEYCLOAK-009`
Owner: IAM Platform
Severity: `SEV-3`

Objective: Diagnose service resolution failures across namespaces.

Preconditions:

- Ability to inspect services in `keycloak` and resources in `flux-system`.

Procedure:

```bash
kubectl get svc -n keycloak | grep keycloak-service
kubectl -n flux-system get terraform config-keycloak -o yaml | grep keycloak_url -n
```

Verify:

- Controller in `flux-system` should use namespace-qualified service names, for example:
  - `http://keycloak-service.keycloak.svc:8080`

Rollback:

1. Revert DNS/url config changes.
2. Reconcile `keycloak-config`.

References:

- `kubernetes/platform/keycloak/config/base/terraform.yaml`

## Planned Upgrade Runbook (Keycloak, Operator, DB)

<a id="runbook-keycloak-010"></a>
Runbook ID: `KEYCLOAK-010`
Owner: IAM Platform
Severity: `Maintenance`

Objective: Perform controlled upgrades with rollback gates.

Preconditions:

- Backup verified.
- Compatibility matrix reviewed.

Procedure:

1. Backup validation.
2. Database/operator compatibility check.
3. Keycloak operator upgrade.
4. Keycloak app upgrade.
5. `keycloak-config` reconcile validation.

Verify:

- Proceed only when previous layer is `Ready=True`.
- Record revision before each stage.

Rollback:

1. Revert component version bumps in reverse order.
2. Reconcile each reverted component.

References:

- `kubernetes/clusters/prod/infra/keycloak-app.yaml`

## Emergency Disable of Keycloak SSO Dependencies

<a id="runbook-keycloak-011"></a>
Runbook ID: `KEYCLOAK-011`
Owner: IAM Platform
Severity: `SEV-1`

Objective: Maintain platform access when Keycloak is degraded.

Preconditions:

- Admin access path that does not depend on Keycloak is available.

Procedure:

1. Suspend `keycloak-config` to avoid churn.
2. Apply temporary fallback auth settings per dependent app.
3. Validate operator access paths.
4. Restore normal OIDC settings after recovery.

Verify:

- Operators can access critical dashboards/admin panels.
- OIDC clients are restored after Keycloak recovery.

Rollback:

1. Re-enable normal SSO configs immediately after recovery.
2. Reconcile dependent applications.

References:

- `terraform/keycloak/resources/clients/*.json`

## Safe Decommission Runbook (Keycloak Stack)

<a id="runbook-keycloak-012"></a>
Runbook ID: `KEYCLOAK-012`
Owner: IAM Platform
Severity: `Maintenance`

Objective: Remove Keycloak stack without leaving orphaned resources.

Preconditions:

- Decommission approval and dependency impact assessment complete.

Procedure:

1. Suspend and remove `keycloak-config`.
2. Remove `keycloak-app` and verify CR cleanup.
3. Remove `postgres-keycloak` (namespace `databases`) and decide whether to keep or delete backups.
4. Remove related Vault secrets and Terraform resources.

Verify:

```bash
kubectl -n keycloak get all
kubectl -n databases get clusters.postgresql.cnpg.io || true
kubectl -n flux-system get kustomizations | grep keycloak || true
kubectl -n flux-system get terraform config-keycloak || true
```

Rollback:

1. Re-apply Keycloak infra manifests from Git.
2. Restore DB from backup if required.

References:

- `KEYCLOAK-003`

## Post-Incident Validation Checklist

<a id="runbook-keycloak-013"></a>
Runbook ID: `KEYCLOAK-013`
Owner: IAM Platform
Severity: `SEV-2`

Objective: Standard verification after any key operation.

Preconditions:

- Recovery action completed and reconciliations resumed.

Procedure:

```bash
flux get kustomizations -n flux-system | grep keycloak
kubectl -n databases get cluster.postgresql.cnpg.io postgres-keycloak
kubectl -n keycloak get keycloak keycloak
kubectl -n flux-system get terraform config-keycloak
```

Verify:

- `keycloak-database` Kustomization Healthy.
- CNPG cluster `postgres-keycloak` Ready.
- `keycloak-app` Kustomization Healthy.
- Keycloak CR Ready.
- `keycloak-config` Kustomization Healthy.
- Terraform CR `config-keycloak` Ready.

Rollback:

1. If any validation fails, return to relevant recovery runbook.

References:

- `KEYCLOAK-001`
- `KEYCLOAK-002`
- `KEYCLOAK-003`
