# Terraform Keycloak Configuration

This module manages Keycloak realm configuration from JSON files, following the consolidated root-module pattern used by `terraform/elastic` and `terraform/vault`.

## Directory structure

```text
terraform/keycloak/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── backend.tf
├── terraform.tfvars.example
├── .gitignore
├── clients.tf
├── client_roles.tf
├── groups.tf
├── users.tf
├── scopes.tf
└── resources/
    ├── realm/
    ├── clients/
    ├── client_roles/
    ├── groups/
    ├── users/
    └── scopes/
```

## What it manages

- Keycloak realm from `resources/realm/realm.json`
- OIDC clients from `resources/clients/*.json`
- Client roles from `resources/client_roles/*.json`
- Groups and group role assignments from `resources/groups/*.json`
- Users and user group memberships from `resources/users/*.json`
- Custom OIDC client scopes and protocol mappers from `resources/scopes/*.json`

JSON file formats are documented in [JSON_FORMAT_GUIDE.md](JSON_FORMAT_GUIDE.md).

## Quick start

1. Copy vars template:

```bash
cd terraform/keycloak
cp terraform.tfvars.example terraform.tfvars
```

2. Fill values in `terraform.tfvars`.

3. Initialize and validate:

```bash
tofu init
tofu plan -out=tfplan
```

4. Apply:

```bash
tofu apply tfplan
```

## Execution modes

This module supports two provider configuration modes via `tofu_controller_execution`.

### 1) Direct/local execution (`tofu_controller_execution = false`)

Use a Vault token directly.

```hcl
tofu_controller_execution = false

vault_address = "https://vault.example.com:8200"
vault_token   = "s.xxxxx"
```

### 2) Tofu controller in-cluster execution (`tofu_controller_execution = true`)

Use Vault Kubernetes auth login.

```hcl
tofu_controller_execution = true

vault_address                    = "https://vault.example.com:8200"
vault_kubernetes_auth_login_path = "auth/kubernetes/login"
vault_kubernetes_auth_role       = "tf-runner"
```

Notes:
- In direct mode, `vault_token` is required.
- In Tofu controller mode, `vault_token` is ignored and `vault_kubernetes_auth_role` is required.
- Admin and application credentials are read from Vault KV v2.

## Migration source

Initial JSON resources were derived from:
- `kubernetes/platform/keycloak/config/base/config/01-realm.json`
- `kubernetes/platform/keycloak/config/base/config/02-clients.json`
- `kubernetes/platform/keycloak/config/base/config/03-groups.json`
- `kubernetes/platform/keycloak/config/base/config/04-users.json`
