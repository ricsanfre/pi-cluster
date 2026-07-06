# HashiCorp Vault Secrets Management — Design & Migration

**Date:** July 2026
**Objective:** Replace Ansible's built-in vault encryption with external HashiCorp Vault for secrets management
**Status:** Migration complete as of release v1.12
**Scope:** Migration from encrypted `vars/vault.yml` + `ansible-vault` password workflow to HashiCorp Vault managed by Ansible + OpenTofu.

---

## Executive Summary

The repository implements a **fully migrated HashiCorp Vault deployment/configuration pipeline** for all secrets management. The legacy Ansible Vault workflow (encrypted `vars/vault.yml` + GPG-based password script) has been completely replaced by on-demand HashiCorp Vault lookups.

- No playbook depends on `vars/vault.yml`.
- The `.vault/vault_pass.sh` script and `ansible/.vault/` directory have been removed.
- All runtime secrets are read from HashiCorp Vault.
- Secret lifecycle is managed via OpenTofu (`terraform/vault/resources/*`) for the declarative baseline and targeted Ansible tasks for runtime/host-derived credentials.

---

## Architecture

### Before migration (AS-IS)

```
┌─────────────────────────────────────────┐
│   Ansible Controller / Localhost        │
├─────────────────────────────────────────┤
│  .vault/vault_pass.sh                   │
│         ↓                               │
│  ansible.cfg: vault_password_file=...   │
│         ↓                               │
│  vars/vault.yml (AES256 encrypted)      │
│         ↓                               │
│  Playbooks include encrypted vars       │
└─────────────────────────────────────────┘
```

Secrets lived as encrypted files in the repository, decrypted at runtime via a GPG-based password script, with no centralized audit trail or lifecycle management.

### After migration (TO-BE)

```
┌─────────────────────────────────────────┐
│   HashiCorp Vault Server                │
│   (Deployed on external node1)          │
│                                         │
│   KV Secrets Engine (v2):               │
│   - secret/ansible/*                    │
│   - secret/bind9/*                      │
│   - secret/s3/*                         │
│   - secret/kubernetes/*                 │
│   ... etc                               │
└─────────────────────────────────────────┘
         ↑                   ↑
         │ VAULT_TOKEN       │ VAULT_ADDR
         │                   │
┌────────────────────────────────────────┐
│  Ansible Controller / Localhost        │
├────────────────────────────────────────┤
│  Environment Variables:                │
│  - VAULT_ADDR                          │
│  - VAULT_TOKEN                         │
│  - VAULT_CACERT (optional)             │
│                                        │
│  Playbooks use:                        │
│  - community.hashi_vault.kv_get        │
│  - community.hashi_vault.kv_put        │
│  - Jinja2 lookups                      │
└────────────────────────────────────────┘
```

All secrets are stored in HashiCorp Vault's KV Secrets Engine (v2) under structured paths. Ansible playbooks perform on-demand lookups using the `community.hashi_vault` collection, with Vault connection parameters passed directly to modules.

---

## Staged Orchestration Pipeline

`ansible/external_services.yml` orchestrates the full external services lifecycle in five stages:

| Stage | Tag | Playbook | Purpose |
|-------|-----|----------|---------|
| 1 | `vault`, `stage1` | `deploy_vault.yml` | Deploy Vault server + generate `~/.secrets/vault.env` |
| 2 | `terraform`, `stage2` | `configure_vault.yml` | Apply OpenTofu Vault configuration (secrets, policies, roles) |
| 3 | `minio`, `rustfs`, `stage3` | `deploy_rustfs.yml` | Deploy RustFS S3 server with secrets sourced from Vault |
| 4 | `minio`, `terraform`, `stage4` | `configure_minio.yml` | Configure RustFS buckets, users, policies via Terraform |
| 5 | `credentials`, `stage5` | `load_external_services_keys.yml` | Load remaining Kubernetes and service credentials into Vault |

Run specific stages via direct runner commands:

```bash
./ansible-runner/ansible-runner.sh ansible-playbook external_services.yml --tags vault
./ansible-runner/ansible-runner.sh ansible-playbook external_services.yml --tags terraform
./ansible-runner/ansible-runner.sh ansible-playbook external_services.yml --tags rustfs
./ansible-runner/ansible-runner.sh ansible-playbook external_services.yml --tags credentials
```

Or run the full pipeline:

```bash
make external-services
```

---

## Vault Environment Handoff

`ansible/deploy_vault.yml` generates a local controller file at `~/.secrets/vault.env` containing:

- `VAULT_ADDR`
- `VAULT_TOKEN`
- `VAULT_CACERT` (when custom CA is used)

Eleven playbooks source this file to obtain Vault connection parameters:

- `external_services.yml` (orchestrator)
- `deploy_vault.yml`, `configure_vault.yml`, `load_external_services_keys.yml`
- `deploy_rustfs.yml`, `configure_minio.yml`
- `k3s_install.yml`
- `backup_configuration.yml`, `deploy_monitoring_agent.yml`
- `reset_external_services.yml`
- `deploy_minio.yml` (standalone, retained for backward compatibility)

---

## OpenTofu-Based Vault Configuration

`ansible/configure_vault.yml` runs OpenTofu in `terraform/vault/` and applies consolidated resource definitions:

- `resources/secrets/*.json` — KV secrets for all services (18 secret definitions)
- `resources/policies/*.yaml` — ACL policies (readonly, readwrite, create-child-token, vault-metrics)
- `resources/roles/*.json` — Kubernetes auth roles (external-secrets, prometheus, tf-runner)

The `enable_kubernetes_auth` flag is controlled dynamically via the `vault_enable_kubernetes_auth` Ansible variable, allowing Kubernetes authentication to be configured when a live cluster is available:

```
TF_VAR_enable_kubernetes_auth={{ vault_enable_kubernetes_auth | lower }}
TF_VAR_enable_policies=true
TF_VAR_enable_roles=true
TF_VAR_enable_secrets=true
```

---

## Legacy Ansible Vault — Fully Decommissioned

- `vault_password_file=./.vault/vault_pass.sh` is commented out in `ansible/ansible.cfg`.
- `vars/vault.yml` has been removed from the repository.
- `ansible/.vault/` directory no longer exists.
- No playbook includes `vars/vault.yml` — all secrets are fetched on-demand from HashiCorp Vault.

---

## On-Demand Lookup Pattern

This is the canonical pattern for playbooks that need secrets from Vault:

1. Remove any `include_vars: "vars/vault.yml"` dependency.
2. Validate Vault environment (`VAULT_ADDR`, `VAULT_TOKEN`) in `pre_tasks`.
3. Replace secret variable usage with on-demand lookups:

```yaml
"{{ lookup('community.hashi_vault.kv_get', 'secret/kubernetes/cluster').secret.data.data.k3s_token }}"
```

4. Pass Vault connection parameters directly to modules/tasks:

```yaml
environment:
  VAULT_ADDR: "{{ lookup('env', 'VAULT_ADDR') }}"
  VAULT_TOKEN: "{{ lookup('env', 'VAULT_TOKEN') }}"
  VAULT_CACERT: "{{ lookup('env', 'VAULT_CACERT') | default('', true) }}"
```

5. Add `no_log: true` to tasks handling sensitive values.

### Why On-Demand Lookups?

The design deliberately chooses **on-demand lookups** over the alternative "fetch all secrets upfront" approach. Fetching all secrets into Ansible facts at the top of a playbook keeps them in memory for the entire run, requires upfront planning of every secret needed, and adds complexity with state management. On-demand lookups solve all three:

| Dimension | Fetch All Upfront | On-Demand Lookups |
|---|---|---|
| Secrets in memory | All, for entire playbook run | Only current task's data |
| Performance (5 secrets) | ~125ms + state management overhead | ~60ms (cached after first use) |
| State management | Complex: vault_init, register vars, set_fact | None: each task is self-contained |
| Security posture | More secrets in Ansible facts | Minimal exposure window |
| Code clarity | Boilerplate in pre_tasks | Secrets fetched where used |

Ansible caches lookups automatically per task, so repeated access to the same secret path incurs no additional Vault API calls.

### Common Lookup Patterns

**Get a single secret value:**
```yaml
"{{ lookup('community.hashi_vault.kv_get', 'secret/app/db').secret.data.data.password }}"
```

**Fetch multiple keys from the same path (one API call):**
```yaml
- name: Fetch all secrets from a path
  ansible.builtin.set_fact:
    db: "{{ lookup('community.hashi_vault.kv_get', 'secret/database/prod').secret.data.data }}"
  environment:
    VAULT_ADDR: "{{ lookup('env', 'VAULT_ADDR') }}"
    VAULT_TOKEN: "{{ lookup('env', 'VAULT_TOKEN') }}"

# Then use: {{ db.username }}, {{ db.password }}, {{ db.host }}
```

**Conditional retrieval:**
```yaml
- name: Get secrets only in production
  ansible.builtin.set_fact:
    api_credentials: "{{ lookup('community.hashi_vault.kv_get', 'secret/api/' + deployment_env).secret.data.data }}"
  environment:
    VAULT_ADDR: "{{ lookup('env', 'VAULT_ADDR') }}"
    VAULT_TOKEN: "{{ lookup('env', 'VAULT_TOKEN') }}"
  when: deployment_env in ['prod', 'staging']
```

**Optional secrets with a default fallback:**
```yaml
- name: Fetch optional secret
  ansible.builtin.set_fact:
    api_key: "{{ lookup('community.hashi_vault.kv_get', 'secret/api/keys', errors='ignore').secret.data.data.key | default('default-key') }}"
  environment:
    VAULT_ADDR: "{{ lookup('env', 'VAULT_ADDR') }}"
    VAULT_TOKEN: "{{ lookup('env', 'VAULT_TOKEN') }}"
  ignore_errors: true
```

### Security Best Practices

- **Use limited-scope tokens** instead of the root token:
  ```bash
  vault token create -policy=ansible-read -ttl=1h -renewable
  ```
- **Scope Vault policies to minimum required paths:**
  ```hcl
  path "secret/data/kubernetes/*" {
    capabilities = ["read", "list"]
  }
  ```
- **Always use `no_log: true`** on tasks that handle sensitive values to prevent secrets from appearing in Ansible output.
- **Enable Vault audit logging** to track all secret access:
  ```bash
  vault audit enable file file_path=/var/log/vault/audit.log
  ```
- **Use renewable tokens** for long-running playbooks to avoid mid-run token expiry.

### Troubleshooting

| Problem | Solution |
|---------|----------|
| `VAULT_ADDR not set` | `export VAULT_ADDR='https://vault.example.com:8200'` |
| `VAULT_TOKEN not set` | `export VAULT_TOKEN='s.xxxxx'` |
| `SSL certificate verify failed` | Set `VAULT_CACERT` or ensure the CA is trusted |
| `Secret not found` at expected path | Verify with `vault kv get secret/path` |
| `Token expired` mid-playbook | Generate a longer-lived token: `vault token create -ttl=24h` |
| `Permission denied` on lookup | Check the token's policy covers the requested secret path |

---

## Recommended Validation Flow

From repo root:

```bash
# 1) Runner bootstrap
make ansible-runner-setup

# 2) CI-parity lint
make lint-ci

# 3) Syntax-check external services orchestration
make syntax-check-external-services

# 4) OpenTofu safe checks (no apply)
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/minio && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/vault && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
```

---

## Operational Notes

- Do **not** run host `ansible-playbook` directly; use the runner wrapper.
- Do **not** run destructive targets such as `make clean` unless explicitly intended.
- Treat `~/.secrets/vault.env`, `~/.secrets/ionos-credentials.ini`, and `~/.secrets/github-pat.ini` as sensitive local files.
- There is no `make vault-migration` target — migration was performed incrementally as part of the v1.12 release cycle.
