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
- Flux Kustomizations:
  - `keycloak-db`
  - `keycloak-app`
  - `keycloak-config`
- CNPG cluster: `keycloak-db`
- Keycloak CR: `keycloak`
- Terraform CR (tofu-controller): `config-keycloak`

2. Suspend reconciliation to avoid race conditions.

```bash
flux suspend kustomization keycloak-config -n flux-system
flux suspend kustomization keycloak-app -n flux-system
flux suspend kustomization keycloak-db -n flux-system
```

3. Stop Keycloak app object (optional but recommended).

```bash
kubectl -n keycloak delete keycloak keycloak --ignore-not-found
```

4. Delete PostgreSQL cluster object.

```bash
kubectl -n keycloak delete cluster.postgresql.cnpg.io keycloak-db --ignore-not-found
```

5. Delete PostgreSQL PVCs (actual data wipe).

```bash
kubectl -n keycloak delete pvc -l cnpg.io/cluster=keycloak-db
```

6. Verify DB resources are gone.

```bash
kubectl -n keycloak get pvc | grep keycloak-db || true
kubectl -n keycloak get cluster.postgresql.cnpg.io keycloak-db || true
```

7. Recreate database layer first.

```bash
flux resume kustomization keycloak-db -n flux-system
flux reconcile kustomization keycloak-db -n flux-system --with-source
```

Wait until the CNPG cluster is Ready:

```bash
kubectl -n keycloak get cluster.postgresql.cnpg.io keycloak-db -o wide
kubectl -n keycloak get pods
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

Objective: Restore Keycloak PostgreSQL data from object storage backup.

Preconditions:

- Confirm latest successful backup exists for `keycloak-db`.
- Confirm object storage credentials in `keycloak-db-minio-secret` are valid.
- Confirm maintenance window is active.

Procedure:

1. Suspend `keycloak-app` and `keycloak-config` reconciliation.
2. Create a recovery CNPG cluster manifest from backup metadata.
3. Validate recovered data in an isolated cluster/service.
4. Perform cutover to recovered cluster.
5. Resume app and config reconciliations.

Verify:

```bash
kubectl -n keycloak get cluster.postgresql.cnpg.io
kubectl -n keycloak get pods
kubectl -n keycloak logs -l app=keycloak --tail=100
```

Rollback:

- Repoint Keycloak DB host to previous RW service if cutover validation fails.
- Re-suspend `keycloak-config` until DB state is stable.

References:

- `kubernetes/platform/keycloak/db/base/keycloak-db.yaml`

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

Objective: Standard triage flow for `keycloak-db`, `keycloak-app`, and `keycloak-config`.

Preconditions:

- Incident bridge opened and impact assessed.

Procedure:

```bash
flux get kustomizations -n flux-system | grep keycloak
kubectl -n flux-system describe kustomization keycloak-db
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
kubectl -n keycloak get cluster.postgresql.cnpg.io keycloak-db -o wide
kubectl -n keycloak get pods -l cnpg.io/cluster=keycloak-db
kubectl -n keycloak describe cluster.postgresql.cnpg.io keycloak-db
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
3. Remove `keycloak-db` and decide whether to keep or delete backups.
4. Remove related Vault secrets and Terraform resources.

Verify:

```bash
kubectl -n keycloak get all
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
kubectl -n keycloak get cluster.postgresql.cnpg.io keycloak-db
kubectl -n keycloak get keycloak keycloak
kubectl -n flux-system get terraform config-keycloak
```

Verify:

- `keycloak-db` Kustomization Healthy.
- CNPG cluster `keycloak-db` Ready.
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
