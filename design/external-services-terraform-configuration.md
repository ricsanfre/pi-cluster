# External Services Configuration — Ansible + Terraform Separation

**Date:** July 2026
**Status:** Implemented as of release v1.12
**Applies to:** HashiCorp Vault, RustFS (S3)

---

## Design Rationale

The two external services running on `node1` follow the same architectural pattern: **Ansible handles infrastructure provisioning** (install packages, generate TLS certs, initialize services) while **Terraform (OpenTofu) handles day-2 configuration** (secrets, policies, buckets, users).

### Before (all in Ansible)

```
Ansible external_services.yml
├── Install Vault Server
├── Initialize Vault
├── Create KV secrets
├── Create policies
├── Configure auth methods
├── Install MinIO
├── Create buckets
├── Create users & policies
└── Load all credentials
```

### After (Ansible install + Terraform configure)

```
Ansible                            Terraform
───────                            ─────────
Install Vault Server               Configure Vault
  (deploy_vault.yml)       ──→       (configure_vault.yml → terraform/vault/)
  • TLS certificates                  • KV secrets
  • Package install                   • ACL policies
  • Init & unseal                     • K8s auth roles

Install RustFS                     Configure RustFS
  (deploy_rustfs.yml)      ──→       (configure_minio.yml → terraform/minio/)
  • TLS certificates                  • S3 buckets
  • Package install                   • IAM users
  • Service config                    • IAM policies

Load runtime credentials
  (load_external_services_keys.yml)
  • DDNS keys, tokens, htpasswd
```

### Why split install from configure?

| Concern | Ansible (Install) | Terraform (Configure) |
|---------|-------------------|-----------------------|
| **Responsibility** | Get the service running | Declare desired state |
| **State tracking** | Ad-hoc (service health checks) | State file with drift detection |
| **Change management** | Playbook re-run | `tofu plan` → review → `tofu apply` |
| **Audit trail** | Ansible log | Full apply history in state |
| **Rollback** | Manual intervention | `tofu apply` previous state revision |
| **Collaboration** | Sequential playbook runs | PR-based reviews on `.tf` files |

The split keeps playbooks focused on infrastructure lifecycle (install, upgrade, uninstall) and delegates ongoing configuration changes to a tool purpose-built for declarative state management.

---

## Deployment Pipeline

`ansible/external_services.yml` orchestrates five stages, alternating between Ansible (install) and Terraform (configure):

```
┌──────────────────────────────────────────────────────────────────┐
│        Cluster External Services Deployment Workflow             │
└──────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────┐
│  Stage 1: Deploy Vault Server           │  ← Ansible
│  (deploy_vault.yml)                     │
│  • Generate TLS certificates            │
│  • Install Vault                        │
│  • Initialize & unseal                  │
└──────────────┬──────────────────────────┘
               │ root token + vault.env
               ▼
┌─────────────────────────────────────────┐
│  Stage 2: Configure Vault               │  ← Terraform
│  (configure_vault.yml)                  │
│  • OpenTofu init & apply                │
│  • Enable KV secrets engine             │
│  • Create access policies & roles       │
│  • Load auto-generated secrets          │
│  • Skip Kubernetes auth (deferred)      │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  Stage 3: Deploy RustFS                 │  ← Ansible
│  (deploy_rustfs.yml)                    │
│  • Generate TLS certificates            │
│  • Fetch secrets from Vault             │
│  • Install & configure RustFS           │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  Stage 4: Configure RustFS Resources    │  ← Terraform
│  (configure_minio.yml)                  │
│  • Terraform init/apply for S3          │
│  • Configure buckets/users/policies     │
└──────────────┬──────────────────────────┘
               │
               ▼
┌────────────────────────────────────────────┐
│  Stage 5: Load Remaining Credentials       │  ← Ansible
│  (load_external_services_keys.yml)         │
│  • Load DDNS key from filesystem           │
│  • Load S3 Prometheus token                │
│  • Create HTTP Basic Auth credentials      │
│  • Store general Ansible variables         │
└────────────────────────────────────────────┘
```

Run the full pipeline:

```bash
make external-services
```

Or individual stages:

```bash
./ansible-runner/ansible-runner.sh ansible-playbook external_services.yml --tags vault
./ansible-runner/ansible-runner.sh ansible-playbook external_services.yml --tags terraform
./ansible-runner/ansible-runner.sh ansible-playbook external_services.yml --tags rustfs
./ansible-runner/ansible-runner.sh ansible-playbook external_services.yml --tags credentials
```

---

## Data-Driven Resource Pattern

Both Terraform modules use the same pattern: resource definitions in structured files, thin `.tf` files with `for_each`:

```
terraform/
├── vault/resources/
│   ├── secrets/*.json        ← 18 secret definitions
│   ├── policies/*.yaml       ← 4 ACL policies
│   └── roles/*.json          ← 3 K8s auth roles
└── minio/resources/
    ├── buckets/*.json
    ├── users/*.json
    └── policies/*.json
```

Adding a new secret, bucket, user, or policy is a matter of adding a JSON/YAML file and running `tofu apply` — no `.tf` code changes needed.

---

## Related Documents

- [HashiCorp Vault Migration Design](hashicorp-vault-migration.md) — Full Vault secrets migration details
- [Ansible Dual Execution Environment](ansible-dual-execution-environment.md) — Runner refactoring
