# Terraform Vault Configuration - Consolidated Architecture

This Terraform configuration manages comprehensive Vault setup with **JSON and YAML-based configuration**:

- **KV Secrets Engine** - Secrets defined in `resources/secrets/*.json` files; paths are `<file_name>/<secret>`
- **Policies Configuration** - Policies defined in `resources/policies/*.{yaml,yml,json}` files (YAML recommended)
- **Kubernetes Auth** - Roles defined in `resources/roles/*.json` files

All configuration is consolidated in the root module using JSON/YAML files, following the same pattern as `terraform/vault/bootstrap` for consistency and simplicity.

## 📦 Directory Structure

```
terraform/vault/
├── main.tf                      # Root module - consolidated Vault resources
├── variables.tf                 # Configuration variables
├── outputs.tf                   # Aggregated outputs
├── versions.tf                  # Provider configuration
├── backend.tf                   # State management
│
├── resources/                   # Consolidated JSON/YAML configuration directory
│   ├── secrets/                 # JSON files for KV secrets
│   │   ├── postgresql.json
│   │   ├── minio.json
│   │   └── config.json
│   │
│   ├── policies/                # YAML/JSON files for access control policies (YAML recommended)
│   │   ├── readonly.yaml
│   │   ├── readwrite.yaml
│   │   ├── admin.yaml
│   │   └── ...
│   │
│   └── roles/                   # JSON files for Kubernetes auth roles
│       ├── external-secrets.json
│       ├── tf-runner.json
│       └── ...
│
├── terraform.tfvars            # Configuration (Git-ignored)
├── terraform.tfvars.example    # Template
├── .gitignore
│
└── (legacy subdirectories below - can be archived/removed)
    ├── bootstrap/              # Bootstrap configuration
    ├── kv-secrets-engine/      # Legacy module
    ├── policies-config/        # Legacy module
    ├── kubernetes-auth/        # Legacy module
    ├── k8s-auth-config/        # Legacy configuration
    └── ...
```

---

## 📖 Configuration Format

See [JSON_FORMAT_GUIDE.md](JSON_FORMAT_GUIDE.md) for detailed documentation on:
- **Secrets JSON format** - Define KV secrets with auto-password generation
- **Policies YAML/JSON format** - Define Vault access control policies (YAML recommended for readability)
- **Kubernetes Roles JSON format** - Define K8s service account authentication

The JSON format guide includes examples for all configuration types, with special emphasis on YAML policies for better multiline readability.

### 1. **kv-secrets-engine** - Secrets Management
- **Enables** KV Version 2 secrets engine at `secret/` path
- **Loads** secrets from JSON files in `secrets/` directory and prefixes paths with the JSON filename
- **Generates** random passwords for fields marked with `secret_name`
- **Supports** per-secret password length override using optional `password_length`
- **Manages** secret lifecycle (create, update, delete)

**Key Features:**
- Loads all JSON files from `secrets/` directory with `<file_name>/<secret>` paths
- Supports password auto-generation
- Uses `for_each` for dynamic secret creation

### 2. **policies-config** - Access Control
- **Defines** 7 pre-configured policies:
  - `readonly` - Read-only access to secrets
  - `readwrite` - Full CRUD on secrets
  - `admin` - Administrative access
  - `create-child-token` - Token management
  - `external-secrets` - External Secrets Operator
  - `terraform-runner` - Terraform automation
  - `backup` - Backup operations

**Key Features:**
- All policies are parametrized with KV engine path
- Easy to add new policies
- Follows principle of least privilege

### 3. **kubernetes-auth** - Kubernetes Integration
- **Creates** service account for Vault authentication
- **Configures** Kubernetes auth method in Vault
- **Manages** Kubernetes roles for pod authentication

**Key Features:**
- Auto-creates long-lived API tokens (K8s v1.24+)
- Creates cluster role bindings for TokenReview API
- Supports multiple K8s roles with different policies

---

## 🎛️ Feature Control Flags

You can now selectively enable or disable specific Vault configurations. This is useful for:
- **Gradual Deployments** - Deploy policies first, then secrets later
- **Testing** - Test only specific components
- **Maintenance** - Disable features temporarily without destroying infrastructure
- **Multi-Environment** - Different flags for dev/staging/production

### Available Flags

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `enable_kubernetes_auth` | bool | true | Enable Kubernetes service account, auth backend, and token setup |
| `enable_policies` | bool | true | Enable creation of Access Control Policies from JSON files |
| `enable_roles` | bool | true | Enable creation of Kubernetes Auth Roles (requires `enable_kubernetes_auth=true`) |
| `enable_secrets` | bool | true | Enable creation of KV Secrets from JSON files |

### Usage Examples

**In terraform.tfvars:**
```hcl
# Only deploy policies and secrets, skip Kubernetes auth
enable_kubernetes_auth = false
enable_policies        = true
enable_roles           = false
enable_secrets         = true
```

**Via command line:**
```bash
# Deploy only Kubernetes authentication infrastructure
tofu apply \
  -var="enable_policies=false" \
  -var="enable_roles=false" \
  -var="enable_secrets=false"

# Deploy only policies (common for initial setup)
tofu apply \
  -var="enable_secrets=false" \
  -var="enable_roles=false" \
  -var="enable_kubernetes_auth=false"
```

### Output Behavior with Disabled Features

When a feature is disabled, outputs return:
- **null** for single resource outputs (e.g., `vault_auth_sa_name`)
- **Empty array** `[]` for lists (e.g., `kubernetes_auth_roles`)
- **0** for counts (e.g., `secrets_count`)
- **"disabled"** in summary (e.g., `vault_configuration_summary`)

---

## 🚀 Quick Start

### 1. Prepare JSON Configuration Files

JSON files are already provided as examples. Customize as needed:

**Secrets:** Edit files in `resources/secrets/`
```bash
# Example: /home/ricardo/GIT/pi-cluster/terraform/vault/resources/secrets/postgresql.json
# Add, edit, or remove JSON files as needed
```

**Policies:** Edit files in `resources/policies/`
```bash
# Example: /home/ricardo/GIT/pi-cluster/terraform/vault/resources/policies/readonly.json
# Add, edit, or remove JSON files as needed
```

**Kubernetes Roles:** Edit files in `resources/roles/`
```bash
# Example: /home/ricardo/GIT/pi-cluster/terraform/vault/resources/roles/external-secrets.json
# Add, edit, or remove JSON files as needed
```

See [JSON_FORMAT_GUIDE.md](JSON_FORMAT_GUIDE.md) for format details.

### 2. Create terraform.tfvars

```bash
cd terraform/vault/
cp terraform.tfvars.example terraform.tfvars
```

**Edit `terraform.tfvars`:**
```hcl
vault_address          = "https://vault.example.com:8200"
vault_token            = "s.xxxxxxxxxxxxxxxxxxxxxxxx"
vault_skip_tls_verify  = false
kubernetes_config_path = "~/.kube/config"
kubernetes_host        = "https://10.0.0.80:6443"

# JSON file directories (relative to root module)
secrets_directory    = "resources/secrets"
policies_directory   = "resources/policies"
roles_directory      = "resources/roles"

# Feature Control Flags (optional, default: all true)
enable_kubernetes_auth = true  # Enable Kubernetes authentication setup
enable_policies        = true  # Enable policy creation from JSON files
enable_roles           = true  # Enable Kubernetes auth role creation
enable_secrets         = true  # Enable secrets creation from JSON files
```

### 3. Initialize Terraform

```bash
tofu init
```

### 4. Plan Changes

```bash
tofu plan -out=tfplan
```

**Optional: Use feature control flags to deploy specific components:**

```bash
# Deploy only policies and Kubernetes auth (no secrets or roles)
tofu plan -var="enable_secrets=false" -var="enable_roles=false" -out=tfplan

# Deploy only secrets (no policies or Kubernetes auth)
tofu plan -var="enable_policies=false" -var="enable_kubernetes_auth=false" -out=tfplan

# Disable Kubernetes authentication entirely
tofu plan -var="enable_kubernetes_auth=false" -out=tfplan
```

### 5. Apply Configuration

```bash
tofu apply tfplan
```

### 6. Verify Deployment

```bash
# View all outputs
tofu output

# View specific output
tofu output vault_configuration_summary
```

---

## � Configuration Flow

The consolidated root module manages all Vault configuration in this sequence:

1. **KV Secrets Engine** - Mounts KV v2 at `secret/` path
2. **Policies** - Defines access control policies
3. **Kubernetes Auth** - Configures Kubernetes authentication
4. **Kubernetes Roles** - Creates roles using defined policies
5. **Secrets** - Creates secrets in the KV engine

**Benefits of Consolidated Architecture:**
- Single Terraform apply for entire Vault setup
- Simplified dependency management
- Easier to maintain and debug
- All resources in one place with clear relationships

---

## 📝 Secrets JSON Format

**See [JSON_FORMAT_GUIDE.md](JSON_FORMAT_GUIDE.md) for complete documentation**

Quick example structure:
```json
{
  "secret-name": {
    "password_length": 32,
    "content": {
      "field1": "value1",
      "field2": "will-be-generated"
    },
    "secret_name": "field2"
  }
}
```

**Fields:**
- `content` - Dictionary of secret key-value pairs
- `secret_name` - Field name to auto-generate password for (optional)
- `password_length` - Optional password length override for this secret (defaults to `generated_password_length`)

**Examples:**

**Database Credentials:**
```json
{
  "database-prod": {
    "content": {
      "username": "dbuser",
      "password": "generated-password",
      "host": "10.0.0.50",
      "port": 5432
    },
    "secret_name": "password"
  }
}
```

If this entry is in `postgresql.json`, the secret path is `secret/data/postgresql/database-prod`.

**API Keys:**
```json
{
  "api-keys": {
    "content": {
      "api_key": "sk_live_1234567890",
      "secret_key": "generated-key"
    },
    "secret_name": "secret_key"
  }
}
```

**OAuth2 Proxy Cookie (32-byte key):**
```json
{
  "cookie": {
    "secret_name": "cookie-secret",
    "password_length": 32,
    "content": {
      "type": "cookie_encryption",
      "service": "oauth2-proxy"
    }
  }
}
```

**Static Secrets (no generation):**
```json
{
  "config": {
    "content": {
      "environment": "production",
      "log_level": "info"
    }
  }
}
```

---

## 🛡️ Policy Examples

### Using Read-Only Policy

```bash
# Create token with readonly policy
vault token create -policy=readonly

# Authenticate with this token
export VAULT_TOKEN=<token>

# Can read secrets
vault kv get secret/postgresql/database-prod

# Cannot modify secrets
vault kv put secret/postgresql/database-prod password=xxx  # ✗ Permission Denied
```

### Using Read-Write Policy

```bash
# Create token with readwrite policy
vault token create -policy=readwrite

# Can read and modify secrets
vault kv put secret/postgresql/new-secret key=value       # ✓ Allowed
vault kv get secret/postgresql/database-prod              # ✓ Allowed
vault kv delete secret/postgresql/old-secret              # ✓ Allowed
```

### Using Kubernetes Role

```bash
# Pod running as external-secrets service account gets readonly access
# Pod runs tf-runner with readonly + create-child-token

# Benefits:
# - No tokens stored in pod
# - Automatic token rotation
# - Automatic token revocation if pod deleted
```

---

## 📊 Outputs

After `terraform apply`, view outputs:

```bash
# All outputs
tofu output

# Configuration summary
tofu output vault_configuration_summary

# KV engine info
tofu output -json | jq '.kv_engine_path'

# Policies created
tofu output policies_created

# Kubernetes roles
tofu output kubernetes_auth_roles
```

---

## 🔧 Modifying Configuration

### Adding a New Policy

Edit `policies-config/policies.tf`:

```hcl
resource "vault_policy" "my_custom_policy" {
  name   = "my-custom-policy"
  policy = <<-EOT
  path "${var.kv_secrets_engine_path}/data/custom/*" {
    capabilities = ["read", "list"]
  }
  EOT
}
```

Then add to outputs in `policies-config/outputs.tf`:

```hcl
output "policy_my_custom_policy_name" {
  value = vault_policy.my_custom_policy.name
}
```

Apply changes:
```bash
tofu apply
```

### Adding a New Kubernetes Role

Edit `kubernetes-auth/variables.tf` default kubernetes_roles:

```hcl
variable "kubernetes_roles" {
  default = {
    existing_role = { ... }
    new_role = {
      service_account_names      = ["my-sa"]
      service_account_namespaces = ["my-namespace"]
      policies                   = ["readonly"]
    }
  }
}
```

Or in `terraform.tfvars`:

```hcl
kubernetes_roles = {
  external-secrets = { ... }
  tf-runner = { ... }
  my-role = {
    service_account_names      = ["my-sa"]
    service_account_namespaces = ["my-namespace"]
    policies                   = ["readwrite"]
  }
}
```

Apply changes:
```bash
tofu apply
```

### Adding New Secrets

1. Create JSON file in `secrets/` directory
2. Run `tofu plan`
3. Review changes
4. Run `tofu apply`

### Modifying Existing Secrets

Edit the JSON file in `secrets/` and run:

```bash
tofu apply
```

Terraform will detect changes and update the secret.

---

## 🧪 Testing Setup

### Verify KV Engine

```bash
vault secrets list
# Should show "secret/" with type "kv"

vault kv list secret/
# Should list all deployed secrets
```

### Verify Policies

```bash
vault policy list
# Should show all created policies

vault policy read readonly
# Should display policy rules
```

### Verify Kubernetes Auth

```bash
vault auth list
# Should show "kubernetes/" auth method

vault read auth/kubernetes/config
# Should show K8s API host details
```

### Test K8s Authentication

From a pod with the correct service account:

```bash
# Get JWT from service account token
JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# Authenticate to Vault
vault write -method=post auth/kubernetes/login \
  role=external-secrets \
  jwt=$JWT

# Should return a valid token with readonly policy
```

---

## ⚠️ Important Notes

1. **State Management**: Each module maintains its own state file. Consider using remote state backend for collaboration.

2. **Token Rotation**: The Vault token in `terraform.tfvars` should be rotated regularly. Consider using temporary tokens.

3. **TLS Verification**: Set `vault_skip_tls_verify = false` in production for secure communication.

4. **Service Account**: Manually verify that `vault-auth-sa` has access to Kubernetes TokenReview API.

5. **Secret Ordering**: JSON files process alphabetically. No dependencies between secrets.

---

## 🔍 Troubleshooting

### KV Secrets Not Creating

```bash
# Check Kubernetes auth is working
terraform -chdir=kubernetes-auth apply

# Check policies exist
vault policy list | grep readonly

# Check KV engine mounted
vault secrets list
```

### Kubernetes Auth Failed

```bash
# Verify service account exists
kubectl get sa vault-auth-sa

# Verify secret exists
kubectl get secret vault-auth-token

# Check cluster role binding
kubectl get clusterrolebinding vault-auth-tokenreview
```

### Token Reviewer JWT Missing

```bash
# Manually verify secret content
kubectl describe secret vault-auth-token -n default

# If missing, the secret wasn't created (common in some K8s versions)
# May need manual token creation
```

---

## 📚 Additional Resources

- [Vault KV Secrets Engine](https://www.vaultproject.io/docs/secrets/kv)
- [Vault Policies](https://www.vaultproject.io/docs/concepts/policies)
- [Vault Kubernetes Auth](https://www.vaultproject.io/docs/auth/kubernetes)
- [Terraform Vault Provider](https://registry.terraform.io/providers/hashicorp/vault/latest/docs)
