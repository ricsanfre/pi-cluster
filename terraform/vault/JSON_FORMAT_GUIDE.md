# Terraform Vault Configuration - JSON File Format Guide

This guide explains the JSON file formats for defining secrets, policies, and Kubernetes roles.

---

## 🎛️ Feature Control & JSON Files

Before working with JSON files, understand the feature control flags:

| Flag | Purpose | JSON Directory Affected |
|------|---------|------------------------|
| `enable_secrets` | Control secret creation | `resources/secrets/` |
| `enable_policies` | Control policy creation | `resources/policies/` |
| `enable_roles` | Control K8s role creation | `resources/roles/` |
| `enable_kubernetes_auth` | Control K8s auth setup | Affects role dependencies |

**Important:** When a feature is disabled, JSON files are not processed:
```bash
# With enable_secrets=false, all JSON files in resources/secrets/ are ignored
terraform apply -var="enable_secrets=false"

# Your JSON files remain untouched, but resources won't be created
# Re-enable the flag to deploy them
terraform apply -var="enable_secrets=true"
```

---

## 📁 Directory Structure

```
terraform/vault/
├── resources/
│   ├── secrets/                    # Secret definitions
│   │   ├── postgresql.json
│   │   ├── minio.json
│   │   └── config.json
│   │
│   ├── policies/                   # Policy definitions
│   │   ├── readonly.json
│   │   ├── readwrite.json
│   │   ├── admin.json
│   │   ├── create-child-token.json
│   │   ├── external-secrets.json
│   │   ├── terraform-runner.json
│   │   └── backup.json
│   │
│   └── roles/                      # Kubernetes role definitions
│       ├── external-secrets.json
│       └── tf-runner.json
│
├── main.tf                         # Root module - loads and processes JSON files
├── variables.tf                    # Configuration variables (paths default to resources/*)
├── outputs.tf                      # Output definitions
└── terraform.tfvars                # Runtime configuration
```

---

## 🔑 Secrets JSON Format

**Location:** `resources/secrets/`

**Purpose:** Define secrets to be stored in Vault's KV v2 secrets engine

### Structure

```json
{
  "secret-name": {
    "secret_name": "field-to-generate-password",
    "content": {
      "key1": "value1",
      "key2": "will-be-generated",
      "key3": "value3"
    }
  }
}
```

Secret paths include the JSON filename as a prefix: `<file_name>/<secret-name>` (file name without `.json`).

### Fields

- **secret-name** (key) - Name used as the secret path suffix in Vault
  - Stored at: `secret/data/<file_name>/<secret-name>`
  - Can contain forward slashes for nested paths: `db/admin`, `api/keys/app1`
  
- **secret_name** (optional) - Field name to auto-generate password for
  - If specified, Terraform generates a random password for this field
  - If omitted, all values are used as-is
  
- **content** - Dictionary of key-value pairs
  - All key-value pairs become the secret content
  - Referenced field gets replaced with generated password if `secret_name` is set

### Examples

#### Database Credentials (with password generation)
```json
{
  "database-prod": {
    "secret_name": "password",
    "content": {
      "username": "db_admin",
      "password": "placeholder",
      "host": "postgres.prod.svc.cluster.local",
      "port": 5432
    }
  }
}
```

**Result in Vault:**
```
Path: secret/data/postgresql/database-prod (if file is `postgresql.json`)
{
  "username": "db_admin",
  "password": "KgB7xQ9mM2jL5pN",  # Generated
  "host": "postgres.prod.svc.cluster.local",
  "port": 5432
}
```

#### API Keys (with multiple auto-generated fields)
```json
{
  "api-keys": {
    "secret_name": "secret_key",
    "content": {
      "api_key": "sk_live_placeholder",
      "secret_key": "placeholder"
    }
  }
}
```

#### Static Configuration (no generation)
```json
{
  "cluster-config": {
    "content": {
      "api_endpoint": "https://10.0.0.80:6443",
      "region": "us-east-1",
      "environment": "production"
    }
  }
}
```

#### Multiple Secrets in One File
```json
{
  "admin-credentials": {
    "secret_name": "password",
    "content": {
      "username": "admin",
      "service": "postgresql"
    }
  },
  "app-credentials": {
    "secret_name": "password",
    "content": {
      "username": "app_user",
      "service": "postgresql"
    }
  }
}
```

---

## 🔐 Policies JSON Format

**Location:** `resources/policies/`

**Purpose:** Define Vault access control policies using HCL syntax

### Structure

```json
{
  "policy-name": {
    "description": "Human-readable description",
    "policy": "HCL policy rules with PLACEHOLDER for engine path"
  }
}
```

### Fields

- **policy-name** (key) - Name of the policy in Vault
  
- **description** (optional) - Human-readable description
  
- **policy** - Vault HCL policy rules
  - Use `PLACEHOLDER` as placeholder for KV engine path
  - Terraform will replace with actual path (default: `secret`)
  - Supports newline escape sequences: `\n` for line breaks

### Placeholder Replacement

The `PLACEHOLDER` string gets replaced with the KV engine path:

```json
{
  "readonly": {
    "policy": "path \"PLACEHOLDER/data/*\" { ... }"
  }
}
```

With `kv_secrets_engine_path = "secret"`, becomes:
```
path "secret/data/*" { ... }
```

### Examples

#### Read-Only Policy
```json
{
  "readonly": {
    "description": "Read-only access to all secrets",
    "policy": "path \"PLACEHOLDER/data/*\" {\n  capabilities = [\"read\", \"list\"]\n}\npath \"PLACEHOLDER/metadata/*\" {\n  capabilities = [\"list\", \"read\"]\n}\n"
  }
}
```

#### Read-Write Policy
```json
{
  "readwrite": {
    "description": "Full CRUD on all secrets",
    "policy": "path \"PLACEHOLDER/data/*\" {\n  capabilities = [\"create\", \"read\", \"update\", \"delete\", \"list\", \"patch\"]\n}\npath \"PLACEHOLDER/metadata/*\" {\n  capabilities = [\"list\", \"read\", \"delete\"]\n}\n"
  }
}
```

#### Token Management Policy
```json
{
  "create-child-token": {
    "description": "Create and manage child tokens",
    "policy": "path \"auth/token/create\" {\n  capabilities = [\"update\"]\n}\npath \"auth/token/lookup-self\" {\n  capabilities = [\"read\"]\n}\npath \"auth/token/renew-self\" {\n  capabilities = [\"update\"]\n}\n"
  }
}
```

#### Admin Policy
```json
{
  "admin": {
    "description": "Full administrative access",
    "policy": "path \"PLACEHOLDER/*\" {\n  capabilities = [\"create\", \"read\", \"update\", \"delete\", \"list\", \"patch\", \"sudo\"]\n}\npath \"sys/mounts/*\" {\n  capabilities = [\"read\", \"list\"]\n}\n"
  }
}
```

#### Specific Path Access
```json
{
  "app-secrets-only": {
    "description": "Access only app/* secrets",
    "policy": "path \"PLACEHOLDER/data/app/*\" {\n  capabilities = [\"read\", \"list\"]\n}\npath \"PLACEHOLDER/metadata/app/*\" {\n  capabilities = [\"read\", \"list\"]\n}\n"
  }
}
```

### Policy Capabilities Reference

```
read        - Read a secret or list entries
create      - Create a new secret
update      - Update an existing secret
delete      - Delete a secret
list        - List entries in a path
patch       - Patch (partial update) a secret
sudo        - Access with sudo capability
```

---

## 🛡️ Policies YAML Format (Recommended)

**Location:** `resources/policies/`

**Extensions:** `.yaml` or `.yml`

**Recommended Format:** YAML provides better readability for multiline policy definitions compared to JSON.

### Structure

```yaml
policy-name:
  description: "Human-readable policy description"
  policy: |
    path "PLACEHOLDER/data/*" {
      capabilities = ["read", "list"]
    }
    path "PLACEHOLDER/metadata/*" {
      capabilities = ["list", "read"]
    }
```

### Why YAML Over JSON for Policies?

**JSON Challenges:**
- Newlines must be escaped as `\n`
- Hard to read multiline policies
- Error-prone when editing
- Unclear where policy rules start/end

```json
{
  "policy": "path \"PLACEHOLDER/data/*\" {\n  capabilities = [\"read\", \"list\"]\n}\n"
}
```

**YAML Advantages:**
- Multiline strings using `|` (literal block)
- Natural, readable policy formatting
- Easier to maintain and debug
- Clearer structure

```yaml
policy: |
  path "PLACEHOLDER/data/*" {
    capabilities = ["read", "list"]
  }
```

### YAML Examples

#### Read-Only Policy
```yaml
readonly:
  description: "Read-only access to all secrets"
  policy: |
    path "PLACEHOLDER/data/*" {
      capabilities = ["read", "list"]
    }
    path "PLACEHOLDER/metadata/*" {
      capabilities = ["list", "read"]
    }
```

#### Read-Write Policy
```yaml
readwrite:
  description: "Read-write access to all secrets"
  policy: |
    path "PLACEHOLDER/data/*" {
      capabilities = ["create", "read", "update", "delete", "list", "patch"]
    }
    path "PLACEHOLDER/metadata/*" {
      capabilities = ["list", "read", "delete"]
    }
```

#### Token Management Policy
```yaml
create-child-token:
  description: "Create and manage child tokens"
  policy: |
    path "auth/token/create" {
      capabilities = ["update"]
    }
    path "auth/token/create-orphan" {
      capabilities = ["update"]
    }
    path "auth/token/lookup-self" {
      capabilities = ["read"]
    }
    path "auth/token/renew-self" {
      capabilities = ["update"]
    }
```

#### Admin Policy
```yaml
admin:
  description: "Full administrative access"
  policy: |
    path "PLACEHOLDER/*" {
      capabilities = ["create", "read", "update", "delete", "list", "patch", "sudo"]
    }
    path "sys/mounts/*" {
      capabilities = ["read", "list"]
    }
```

#### Specific Path Access with Multiple Rules
```yaml
app-secrets-only:
  description: "Access only app/* secrets with extended rules"
  policy: |
    # Read and list app secrets
    path "PLACEHOLDER/data/app/*" {
      capabilities = ["read", "list"]
    }
    path "PLACEHOLDER/metadata/app/*" {
      capabilities = ["read", "list"]
    }
    
    # Allow token self-renewal
    path "auth/token/renew-self" {
      capabilities = ["update"]
    }
```

### YAML Multiline String Formats

Terraform accepts three YAML multiline formats:

**Literal Block** (`|`) - Preserves newlines:
```yaml
policy: |
  path "secret/data/*" {
    capabilities = ["read"]
  }
  path "secret/metadata/*" {
    capabilities = ["read"]
  }
```

**Folded Block** (`>`) - Folds newlines into spaces (use for flow text):
```yaml
description: >
  This is a long description that spans
  multiple lines but will be folded into
  a single line in the result.
```

**Literal with Stripped Chomping** (`|-`) - Removes trailing newline:
```yaml
policy: |-
  path "secret/data/*" {
    capabilities = ["read"]
  }
```

### Mixing JSON and YAML Policies

Both formats are supported simultaneously. Terraform will load and merge both:

```bash
resources/policies/
├── readonly.yaml          # New YAML format
├── readwrite.yaml         # New YAML format
├── admin.json             # Old JSON format
└── custom.yaml            # New YAML format
```

Result: All 4 policies merged into a single configuration

### Migration from JSON to YAML

**Step 1:** Keep existing JSON files as backup
```bash
# No action needed - JSON files still work
```

**Step 2:** Create YAML equivalents
```bash
cd resources/policies/

# Create YAML version (copy and convert)
cat > readonly.yaml << 'EOF'
readonly:
  description: "Read-only access to all secrets"
  policy: |
    path "PLACEHOLDER/data/*" {
      capabilities = ["read", "list"]
    }
EOF
```

**Step 3:** Test with Terraform plan
```bash
terraform plan
# Should show same resources whether using JSON or YAML
```

**Step 4:** (Optional) Remove old JSON files
```bash
# Once confident YAML works, can safely delete JSON files
rm resources/policies/*.json
```

**Note:** You don't need to remove JSON files if you want to keep them for reference or gradual migration.

### Validation

Validate YAML syntax before running Terraform:

```bash
# Check YAML syntax
for f in resources/policies/*.yaml; do
  echo "Checking $f..."
  yq . "$f" > /dev/null || echo "Invalid YAML: $f"
done

# Or using Python
for f in resources/policies/*.yaml; do
  python3 -c "import yaml; yaml.safe_load(open('$f'))" || echo "Invalid: $f"
done
```

---

**Location:** `resources/roles/`

**Purpose:** Define which Kubernetes service accounts can authenticate to Vault and what policies they receive

### Structure

```json
{
  "role-name": {
    "service_account_names": ["sa1", "sa2"],
    "service_account_namespaces": ["namespace1", "namespace2"],
    "policies": ["policy1", "policy2"],
    "audience": "https://kubernetes.default.svc.cluster.local",
    "token_ttl": 3600,
    "token_max_ttl": 86400
  }
}
```

### Fields

- **role-name** (key) - Name of the Kubernetes role in Vault
  - Used for authentication: `role_name=external-secrets`
  
- **service_account_names** (required) - List of K8s service account names
  - Can authenticate with this role
  - Supports multiple accounts in one role
  
- **service_account_namespaces** (required) - List of K8s namespaces
  - Only service accounts in these namespaces can authenticate
  - Supports multiple namespaces
  
- **policies** (required) - List of Vault policies to assign
  - Must exist in `policies-config/policies/`
  - Token will have all listed policy capabilities
  
- **audience** (optional) - JWT audience claim
  - Default: `https://kubernetes.default.svc.cluster.local`
  - For cluster-internal authentication
  
- **token_ttl** (optional) - Token time-to-live in seconds
  - Default: 3600 (1 hour)
  
- **token_max_ttl** (optional) - Maximum token lifetime in seconds
  - Default: 86400 (24 hours)
  - Cannot renew token beyond this time

### Examples

#### External Secrets Operator
```json
{
  "external-secrets": {
    "service_account_names": ["external-secrets"],
    "service_account_namespaces": ["external-secrets"],
    "policies": ["readonly"],
    "audience": "https://kubernetes.default.svc.cluster.local",
    "token_ttl": 3600,
    "token_max_ttl": 86400
  }
}
```

**Result:** Pods running as `external-secrets` SA in `external-secrets` namespace get readonly access for 1 hour

#### Terraform Runner
```json
{
  "tf-runner": {
    "service_account_names": ["tf-runner"],
    "service_account_namespaces": ["flux-system"],
    "policies": ["readonly", "create-child-token"],
    "token_ttl": 1800,
    "token_max_ttl": 3600
  }
}
```

**Result:** `tf-runner` SA in `flux-system` namespace gets readonly + child token creation; shorter TTL for automation

#### Multiple Service Accounts
```json
{
  "monitoring": {
    "service_account_names": ["prometheus", "grafana", "loki"],
    "service_account_namespaces": ["monitoring"],
    "policies": ["readonly"],
    "token_ttl": 7200,
    "token_max_ttl": 86400
  }
}
```

**Result:** Three different monitoring SAs all authenticate with readonly policy

#### Cross-Namespace Access
```json
{
  "app-read-write": {
    "service_account_names": ["app-sa"],
    "service_account_namespaces": ["app-prod", "app-staging"],
    "policies": ["readwrite"],
    "token_ttl": 3600,
    "token_max_ttl": 86400
  }
}
```

**Result:** `app-sa` in both `app-prod` and `app-staging` can read/write secrets

#### Read-Write with Token Management
```json
{
  "app-admin": {
    "service_account_names": ["admin-sa"],
    "service_account_namespaces": ["app-ns"],
    "policies": ["readwrite", "create-child-token"],
    "token_ttl": 3600,
    "token_max_ttl": 86400
  }
}
```

**Result:** Admin SA gets read-write access + ability to create child tokens for other services

---

## 📋 Loading Process (Root Module: main.tf)

### Root Module Workflow

The root module (`terraform/vault/main.tf`) handles all configuration loading and resource creation:

1. **Load JSON Files:** Uses `fileset()` and `jsondecode()` to find and parse all JSON files
2. **Merge Configurations:** Combines JSON from all files in each directory
3. **Create Resources:** Uses `for_each` to create Terraform resources for each entry
4. **Manage Lifecycle:** Handles password generation, policy replacement, and Kubernetes integration

### Secrets Loading

1. **Find** all `.json` files in `resources/secrets/`
2. **Parse** each file as JSON
3. **Merge** all files into single map
4. **Generate** random passwords for specified fields
5. **Create** `vault_kv_secret_v2` resources in Vault at `secret/data/<secret-name>`

### Policies Loading

1. **Find** all `.json` files in `resources/policies/`
2. **Parse** each file as JSON
3. **Merge** all files into single map
4. **Replace** `PLACEHOLDER` with actual KV engine path
5. **Create** `vault_policy` resources in Vault

### Kubernetes Roles Loading

1. **Find** all `.json` files in `resources/roles/`
2. **Parse** each file as JSON
3. **Merge** all files into single map
4. **Create** `vault_kubernetes_auth_backend_role` resources in Kubernetes auth backend

---

## ✅ Validation & Troubleshooting

### JSON Syntax Errors

```bash
# Validate JSON before running Terraform
jq . terraform/vault/resources/policies/readonly.json

# Validate all JSON files
for f in terraform/vault/resources/**/*.json; do jq . "$f" || echo "Error in $f"; done
```

### Missing PLACEHOLDER in Policies

❌ **Wrong:**
```json
{
  "policy": "path \"secret/data/*\" { ... }"
}
```

✅ **Correct:**
```json
{
  "policy": "path \"PLACEHOLDER/data/*\" { ... }"
}
```

### Missing Required Fields in Roles

✅ **Required:**
```json
{
  "role-name": {
    "service_account_names": [...],
    "service_account_namespaces": [...],
    "policies": [...]
  }
}
```

### File Naming

- **Secrets:** Files don't need specific names (loaded by content)
- **Policies:** File names can be anything; policy name comes from JSON key
- **Roles:** File names can be anything; role name comes from JSON key

Good practice: Name files after their primary content
```
✅ policies/readonly.json      # Contains "readonly" policy
✅ roles/external-secrets.json # Contains "external-secrets" role
✅ secrets/postgresql.json     # Contains postgres credentials
```

---

## 🔄 Adding New Secrets, Policies, or Roles

### Add New Secret

1. Create JSON file in `kv-secrets-engine/secrets/`:
   ```bash
   cat > terraform/vault/kv-secrets-engine/secrets/elasticsearch.json <<EOF
   {
     "elasticsearch-admin": {
       "secret_name": "password",
       "content": {
         "username": "elastic",
         "host": "elasticsearch.default.svc.cluster.local"
       }
     }
   }
   EOF
   ```

2. Plan and apply:
   ```bash
   cd terraform/vault
   terraform plan
   terraform apply
   ```

### Add New Policy

1. Create JSON file in `policies-config/policies/`:
   ```bash
   cat > terraform/vault/policies-config/policies/elastic.json <<EOF
   {
     "elasticsearch-read": {
       "description": "Elasticsearch read access",
       "policy": "path \"PLACEHOLDER/data/elasticsearch/*\" {\n  capabilities = [\"read\", \"list\"]\n}\n"
     }
   }
   EOF
   ```

2. Apply:
   ```bash
   terraform apply
   ```

### Add New Kubernetes Role

1. Create JSON file in `kubernetes-auth/roles/`:
   ```bash
   cat > terraform/vault/kubernetes-auth/roles/elasticsearch.json <<EOF
   {
     "elasticsearch": {
       "service_account_names": ["elasticsearch"],
       "service_account_namespaces": ["observability"],
       "policies": ["elasticsearch-read"],
       "token_ttl": 3600,
       "token_max_ttl": 86400
     }
   }
   EOF
   ```

2. Apply:
   ```bash
   terraform apply
   ```

---

## 📊 Tips & Best Practices

### 1. Use Multiple Files for Organization
```
✅ Group related secrets:
   secrets/postgresql.json    # All postgres creds
   secrets/minio.json         # All minio creds
   secrets/api-keys.json      # All API keys

❌ Avoid:
   secrets/all-secrets.json   # Harder to manage
```

### 2. Naming Conventions
```
Secrets:
  - db/admin, db/app              # Hierarchical
  - backup/credentials, backup/config

Policies:
  - readonly, readwrite, admin
  - external-secrets, terraform-runner
  
Roles:
  - external-secrets, tf-runner, app-production
```

### 3. Password Generation
```json
{
  "mysql-root": {
    "secret_name": "password",    # This field gets generated
    "content": {
      "username": "root",         # Static value
      "password": "placeholder",  # Will be overwritten
      "host": "mysql.svc"         # Static value
    }
  }
}
```

### 4. Token TTL Settings
```
Web services: 1-2 hours (3600-7200s)
Automation:   30 min (1800s)
Short-lived:  5-10 min (300-600s)
Long ops:     4-8 hours (14400-28800s)
```

### 5. Policy Organization
```
Core policies:
  - readonly, readwrite, admin

App-specific:
  - app1-read, app1-write
  - app2-read, app2-write

Special:
  - terraform-runner, backup, external-secrets
```

---

## 🎯 Deployment Patterns with Feature Flags

### Pattern 1: Phased Deployment

**Phase 1: Deploy policies and Kubernetes auth**
```bash
terraform apply \
  -var="enable_secrets=false" \
  -var="enable_roles=false"
```

**Phase 2: Deploy secrets after verification**
```bash
terraform apply -var="enable_secrets=true"
```

**Phase 3: Deploy Kubernetes roles**
```bash
terraform apply -var="enable_roles=true"
```

### Pattern 2: Environment-Specific Configuration

Create separate `.tfvars` files for different environments and control which features are deployed:

**dev.tfvars** - Full deployment:
```hcl
enable_kubernetes_auth = true
enable_policies        = true
enable_roles           = true
enable_secrets         = true
```

**staging.tfvars** - Skip certain features:
```hcl
enable_kubernetes_auth = true
enable_policies        = true
enable_roles           = false
enable_secrets         = true
```

**prod.tfvars** - Minimal deployment:
```hcl
enable_kubernetes_auth = false
enable_policies        = true
enable_roles           = false
enable_secrets         = false
```

Usage:
```bash
terraform apply -var-file="dev.tfvars"
terraform apply -var-file="staging.tfvars"
terraform apply -var-file="prod.tfvars"
```

### Pattern 3: Testing Specific Components

Test policy changes only:
```bash
terraform plan \
  -var="enable_policies=true" \
  -var="enable_secrets=false" \
  -var="enable_roles=false" \
  -var="enable_kubernetes_auth=false"
```

Test secrets without Kubernetes:
```bash
terraform plan \
  -var="enable_secrets=true" \
  -var="enable_kubernetes_auth=false" \
  -var="enable_policies=true" \
  -var="enable_roles=false"
```

---

## 🔍 Viewing Configuration

```bash
# View all loaded secrets
terraform output secrets_created

# View all created policies
terraform output policies_created

# View Kubernetes roles
terraform output kubernetes_auth_roles

# View detailed role information
terraform output kubernetes_auth_roles_detail

# View complete summary
terraform output vault_configuration_summary
