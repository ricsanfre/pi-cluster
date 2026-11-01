# Vault Runbooks

## VAULT-001 Vault Outage Triage and Unseal Workflow

<a id="runbook-vault-001"></a>
Runbook ID: `VAULT-001`
Owner: Security and Platform
Severity: `SEV-1`

Objective: Restore Vault availability and dependent secret consumers.

Preconditions:

- Access to Vault host(s).
- Unseal keys and root/admin recovery method available.

Procedure:

1. Check Vault service and seal status.

```bash
vault status
systemctl status vault
```

2. If sealed, unseal Vault.

```bash
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>
```

3. Validate auth and secret read path from operator context.

```bash
vault token lookup
vault kv get secret/keycloak/admin
```

4. Reconcile dependent components (for example, external-secrets and tofu-backed config).

```bash
flux reconcile kustomization external-secrets-config -n flux-system --with-source
flux reconcile kustomization keycloak-config -n flux-system --with-source
```

Verify:

- Vault unsealed and responding.
- Secret consumers recover without auth errors.

Rollback:

1. If unseal fails, escalate to recovery key holders and DR process.
2. Keep dependent kustomizations suspended to avoid noisy failure loops until Vault is stable.

## VAULT-002 Vault Token, Policy, and Role Rotation

<a id="runbook-vault-002"></a>
Runbook ID: `VAULT-002`
Owner: Security and Platform
Severity: `Maintenance` or `SEV-2`

Objective: Rotate Vault tokens, policies, and auth roles without breaking dependent workloads.

Preconditions:

- Root/admin capability available for Vault.
- Inventory of consumers for each token/role is documented.

Procedure:

1. Export current policy and role definitions for backup.
2. Create new policy/role versions (or update existing definitions) in Terraform/Git.
3. Generate replacement credentials and distribute to consumers.
4. Reconcile dependent components and monitor auth failures.
5. Revoke old tokens/secret IDs after successful cutover.

Suggested commands:

```bash
vault policy list
vault token lookup
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization keycloak-config -n flux-system --with-source
```

Verify:

- New credentials authenticate successfully.
- No persistent auth errors in dependent controllers/apps.

Rollback:

1. Temporarily restore previous policy/role definitions.
2. Re-enable old credential only if business impact is critical and approved.

## VAULT-003 Vault Backup and Restore

<a id="runbook-vault-003"></a>
Runbook ID: `VAULT-003`
Owner: Security and Platform
Severity: `SEV-1` or `Maintenance`

Objective: Safely back up Vault state and restore in recovery scenarios.

Preconditions:

- Backup destination and encryption controls validated.
- Access to unseal/recovery keys documented.

Procedure:

1. Execute backup according to Vault storage backend guidance.
2. Validate backup artifact integrity and metadata.
3. Perform periodic restore drill in isolated environment.
4. On real recovery, restore backend data and unseal Vault.
5. Validate auth methods, policies, and critical secrets.

Suggested validation checks:

```bash
vault status
vault auth list
vault policy list
vault kv get secret/keycloak/admin
```

Verify:

- Vault returns to operational state.
- Critical secrets and auth paths are functional.
- Dependent systems recover after reconcile.

Rollback:

1. If restore point is invalid, move to previous backup generation.
2. Keep dependent reconciliations suspended until Vault is stable.

## VAULT-004 Vault Auth Backend Troubleshooting (Kubernetes, AppRole)

<a id="runbook-vault-004"></a>
Runbook ID: `VAULT-004`
Owner: Security and Platform
Severity: `SEV-2` or `Maintenance`

Objective: Diagnose and recover Vault authentication failures for Kubernetes and AppRole backends.

Preconditions:
- Access to Vault admin/root token.
- Access to affected cluster and Vault logs.
- Knowledge of expected auth backend configuration (Kubernetes service account, AppRole role/ID).

Procedure:
1. Identify affected auth backend and error symptoms.
   - Review Vault logs for auth errors (`vault server logs`, `kubectl logs deploy/vault`).
   - Check error messages in consumer pods (external-secrets, tofu-controller, etc).
2. Validate backend configuration:
   - For Kubernetes: Check service account token, Vault role mapping, and API address.
     ```bash
     vault read auth/kubernetes/config
     vault read auth/kubernetes/role/<role-name>
     kubectl get serviceaccount -n <ns> <sa>
     kubectl get secret -n <ns> | grep <sa>
     ```
   - For AppRole: Check role, secret ID, and policy mapping.
     ```bash
     vault read auth/approle/role/<role-name>
     vault read auth/approle/role/<role-name>/role-id
     vault read auth/approle/role/<role-name>/secret-id
     ```
3. Test authentication manually:
   - For Kubernetes:
     ```bash
     vault write auth/kubernetes/login role=<role-name> jwt=<service-account-token>
     ```
   - For AppRole:
     ```bash
     vault write auth/approle/login role_id=<role-id> secret_id=<secret-id>
     ```
4. Reconcile backend configuration in Git/Terraform if drift is detected.
5. Restart/reconcile affected consumers after backend fix.

Verify:
- Vault auth backend returns valid token for test login.
- Consumers recover and authenticate successfully.
- No persistent auth errors in Vault logs or consumer pods.

Rollback:
1. Restore previous backend configuration from Git/Terraform.
2. Revert consumer configuration to last known working state.

References:
- `terraform/vault/resources/auth_backends/*.yaml`
- `terraform/vault/resources/roles/*.yaml`

## VAULT-005 Vault Seal Migration and Key Rotation

<a id="runbook-vault-005"></a>
Runbook ID: `VAULT-005`
Owner: Security and Platform
Severity: `SEV-1` or `Maintenance`

Objective: Safely migrate Vault seal mechanism (e.g., from Shamir to auto-unseal) and rotate unseal keys with minimal disruption.

Preconditions:
- Access to Vault admin/root token and unseal keys.
- Backup of Vault data and configuration.
- Maintenance window approved.

Procedure:
1. Validate current seal configuration and backup status.
  ```bash
  vault status
  vault operator key-status
  vault operator unseal <key>
  ```
2. If migrating seal type (e.g., to auto-unseal):
  - Update Vault config file with new seal stanza (e.g., KMS, HSM, etc).
  - Restart Vault and verify new seal mechanism is active.
  - Unseal Vault if required.
3. If rotating unseal keys (Shamir):
  - Initiate key rotation:
    ```bash
    vault operator rotate
    ```
  - Distribute new unseal keys securely to key holders.
  - Validate old keys are invalidated.
4. Test unseal and recovery with new keys/mechanism.
5. Reconcile dependent consumers and monitor for auth/seal errors.

Verify:
- Vault operates with new seal mechanism or rotated keys.
- Unseal process works as expected.
- No disruption to secret consumers.

Rollback:
1. Restore previous Vault config and restart service if migration fails.
2. Use backup to recover Vault state if key rotation causes lockout.

References:
- `terraform/vault/resources/seal_config.yaml`
- Vault official docs: https://developer.hashicorp.com/vault/docs/seal
