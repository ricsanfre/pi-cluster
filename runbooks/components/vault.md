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

## VAULT-006 Vault Server Upgrade and Unseal

<a id="runbook-vault-006"></a>
Runbook ID: `VAULT-006`
Owner: Security and Platform
Severity: `Maintenance`

Objective: Upgrade the Vault **server binary** on `node1` (`vault_version`) and bring it back to an
unsealed state without manual key entry.

The `ricsanfre.vault` role supports this directly: it compares `vault -version` with `vault_version`,
reinstalls the binary when they differ, and notifies `Restart vault`. Two details decide whether the
upgrade succeeds:

- `initialize_vault` is skipped unless `/v1/sys/health` returns **501**, so an upgrade restart (503,
  sealed but initialised) never re-initialises the cluster.
- The in-playbook unseal in `unseal_vault.yml` is gated on `vault_keys is defined`, which is only set
  during initial creation — so on an upgrade it **silently skips**. The unseal is actually performed by
  **`vault-unseal.service`** (`vault_unseal_service: true`), which is enabled, marked `PartOf=vault.service`,
  and unseals from `/etc/vault/unseal.json`.

Preconditions:
- `~/.secrets/vault.env` present with a token that can read the S3 and other bootstrap secrets.
- `/etc/vault/unseal.json` exists on `node1` and `systemctl is-enabled vault-unseal` is `enabled`. **If the
  unseal service is disabled, the upgrade leaves Vault sealed with no automatic recovery** — enable it
  first or plan a manual unseal with the keys.
- Maintenance window: every ExternalSecret, the Vault agent injector and the two Terraform CRs read Vault.

Procedure:

1. Record the current state.

```bash
./ansible-runner/ansible-runner.sh ansible vault -i inventory.yml -b -m shell \
  -a "vault -version; systemctl is-enabled vault-unseal"
curl -sk -o /dev/null -w '%{http_code}\n' https://vault.homelab.ricsanfre.com:8200/v1/sys/health   # 200
kubectl --context picluster-prod get externalsecrets -A -o json \
  | jq -r '[.items[]|select([.status.conditions[]?|select(.type=="Ready")|.status]|join(""))=="True"]|"\(length)/\(.items|length) synced"'
```

2. Take a Vault snapshot (see `VAULT-003`) and keep the unseal keys accessible outside the host.

3. Bump `vault_version` in `ansible/vars/picluster.yml` and deploy.

```bash
make deploy-vault
```

The role detects the version mismatch, downloads the zip from `releases.hashicorp.com` with
SHA256SUMS verification, copies the binary, restarts the unit, then (same play) the Terraform stage
re-applies Vault configuration.

4. Watch the unseal happen. The service waits for the API, then unseals from `/etc/vault/unseal.json`:

```bash
./ansible-runner/ansible-runner.sh ansible vault -i inventory.yml -b -m shell \
  -a "journalctl -u vault-unseal -n 40 --no-pager"
```

Verify:

- `/v1/sys/health` returns **200** (initialised, unsealed, active) and `vault status` shows the new version.
- The `vault-unseal` journal shows `Vault unsealed`. It is a `oneshot` unit (`RemainAfterExit=false`), so
  `systemctl is-active vault-unseal` reading `inactive` afterwards is expected — check `is-enabled`, which
  must stay `enabled`, not `is-active`.
- All ExternalSecrets are `SecretSynced` again (54/54 at the time of writing).
- `kubectl --context picluster-prod -n flux-system get terraforms` — `config-elastic` and
  `config-keycloak` return to `Ready` and plan without drift.
- Grafana SSO and the five OIDC consoles still answer `302` (the gateway resolves the issuer from Vault).

Rollback:

1. Reinstall the previous binary: `./ansible-runner/ansible-runner.sh ansible-playbook deploy_vault.yml -e vault_version=<previous>`
   — the role detects the mismatch and reinstalls, then restarts.
2. If Vault does not unseal, unseal manually with the keys and investigate `vault-unseal.service`:

```bash
vault operator unseal <key>
```
3. If data is damaged, restore the snapshot taken in step 2 (see `VAULT-003`).

References:
- `ansible/deploy_vault.yml`, `ansible/vars/picluster.yml` (`vault_version`, `vault_unseal*`)
- `ansible/requirements.yml` (`ricsanfre.vault`)
- `runbooks/components/vault.md#runbook-vault-003` (backup and restore)
