# Terraform Elastic Configuration

This module manages Elasticsearch and Kibana configuration from JSON files, following the same consolidated root-module pattern used by `terraform/vault`.

## Directory structure

```text
terraform/elastic/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── backend.tf
├── terraform.tfvars.example
├── .gitignore
├── roles.tf
├── users.tf
├── ilm_policies.tf
├── index_templates.tf
├── template_components.tf
├── dataviews.tf
└── resources/
    ├── roles/
    ├── users/
    ├── policies/
    ├── templates/
    ├── template_components/
    └── dataviews/
```

## What it manages

- Elasticsearch security roles from `resources/roles/*.json`
- Elasticsearch users from `resources/users/*.json` (passwords from Vault KV v2)
- Elasticsearch ILM policies from `resources/policies/*.json`
- Elasticsearch component templates from `resources/template_components/*.json`
- Elasticsearch index templates from `resources/templates/*.json`
- Kibana data views from `resources/dataviews/*.json`

JSON file formats for all resource types are documented in [JSON_FORMAT_GUIDE.md](JSON_FORMAT_GUIDE.md).

## Quick start

1. Copy vars template:

```bash
cd terraform/elastic
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

Use local kubeconfig and Vault token.

```hcl
tofu_controller_execution = false

kubernetes_config_path = "~/.kube/config"

vault_address = "https://vault.example.com:8200"
vault_token   = "s.xxxxx"
```

### 2) Tofu controller in-cluster execution (`tofu_controller_execution = true`)

Use Kubernetes provider in-cluster auto-discovery and Vault Kubernetes auth login.

```hcl
tofu_controller_execution = true

vault_address                    = "https://vault.example.com:8200"
vault_kubernetes_auth_login_path = "auth/kubernetes/login"
vault_kubernetes_auth_role       = "tofu-controller"
```

Notes:
- In direct mode, `vault_token` is required.
- In Tofu controller mode, `vault_token` is ignored and `vault_kubernetes_auth_role` is required.
- In Tofu controller mode, no Kubernetes provider-specific variables are required.

## Notes

- This module reads an existing Kubernetes secret for the bootstrap `elastic` password.
- Keep all sensitive values in `terraform.tfvars` (ignored by `.gitignore`).
- Outputs are centralized in `outputs.tf` for consistency with other Terraform modules.
