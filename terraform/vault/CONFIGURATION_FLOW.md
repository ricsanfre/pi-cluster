# Terraform Vault Configuration Flow - Consolidated Architecture

## 🔄 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│           JSON and YAML Configuration Files (resources/)         │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  resources/secrets/*.json               ─┐                       │
│  • postgresql.json                        │                       │
│  • minio.json                             │ fileset() +           │
│  • config.json                            │ jsondecode()/          │
│                                           │ yamldecode()           │
│  resources/policies/*.{yaml,yml,json}   ─┤ Root Module (main.tf)  │
│  • readonly.yaml (recommended)            │ ────────────────       │
│  • readwrite.yaml (recommended)           │ Create all resources   │
│  • admin.yaml (recommended)               │ with for_each loops    │
│  • create-child-token.yaml                │                        │
│  • ... or use .json format                │                        │
│                                           │                        │
│  resources/roles/*.json                 ─┤                        │
│  • external-secrets.json                  │                        │
│  • tf-runner.json                        ─┘                        │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ Variables from terraform.tfvars:
                            │ • secrets_directory = "resources/secrets"
                            │ • policies_directory = "resources/policies"
                            │ • roles_directory = "resources/roles"
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│        Root Module: terraform/vault/main.tf                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Step 1: Load JSON and YAML Files                                │
│  locals {                                                        │
│    secret_files = fileset(path.module, "${var.secrets_...       │
│    policy_files_json = fileset(...)  # Load .json files         │
│    policy_files_yaml = fileset(...)  # Load .yaml/.yml files    │
│    policies = merge(json_policies, yaml_policies)               │
│    k8s_roles_raw = merge([for f in local.k8s_role_files: ...    │
│  }                                                               │
│                                                                   │
│  Step 2: Generate Passwords & Process Data                       │
│  resource "random_string/random_password"                        │
│  locals { secrets_with_passwords = ... }                        │
│  uses secret.password_length or generated_password_length        │
│                                                                   │
│  Step 3: Create Vault Resources (for_each)                       │
│  resource "vault_mount" "kv_engine_v2"                           │
│  resource "vault_policy" "policies"[*]                           │
│  resource "vault_kv_secret_v2" "secrets"[*]                      │
│  resource "vault_kubernetes_auth_backend_role" "roles"[*]        │
│                                                                   │
│  Step 4: Create Kubernetes Resources (for_each)                  │
│  resource "kubernetes_service_account_v1" "vault_auth_sa"        │
│  resource "kubernetes_secret_v1" "vault_auth_token"              │
│  resource "vault_auth_backend" "kubernetes"                      │
│  resource "vault_kubernetes_auth_backend_config"                 │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ terraform apply
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              HashiCorp Vault (Deployed State)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  KV Secrets Engine (secret/path)                                 │
│  ├─ secret/data/postgresql/postgresql-admin                      │
│  ├─ secret/data/minio/minio-admin                                │
│  └─ secret/data/config/cluster-config                            │
│                                                                   │
│  Policies                                                        │
│  ├─ readonly, readwrite, admin                                   │
│  ├─ create-child-token, external-secrets                         │
│  ├─ terraform-runner, backup                                     │
│  └─ ... (all from resources/policies/*.json)                    │
│                                                                   │
│  Kubernetes Auth (/auth/kubernetes/)                             │
│  ├─ Role: external-secrets                                       │
│  ├─ Role: tf-runner                                              │
│  └─ ... (all from resources/roles/*.json)                        │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ K8s pod requests token
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              Pod Authentication Flow                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  1. Pod with SA=external-secrets in external-secrets namespace   │
│  2. Pod reads JWT from /var/run/secrets/.../token               │
│  3. Sends: POST /auth/kubernetes/login                          │
│     - role=external-secrets                                      │
│     - jwt=<service-account-jwt>                                  │
│  4. Vault validates using TokenReview API                       │
│  5. Returns Vault token with "readonly" policy                  │
│  6. Pod uses token to read secrets: GET /v1/secret/data/*       │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📝 JSON File Processing in Root Module

### Step 1: File Discovery (Root Module)
```bash
fileset(path.module, "${var.policies_directory}/*.json")
# Result: ["resources/policies/readonly.json", "resources/policies/readwrite.json", ...]
```

### Step 2: File Reading & Decoding (Root Module)
```hcl
for f in local.policy_files :
  jsondecode(file("${path.module}/${f}"))
# Each file becomes a map: {"readonly": {...}, "admin": {...}}
```

### Step 3: Merging Multiple Files (Root Module)
```hcl
merge([
  {"readonly": {...}},
  {"readwrite": {...}},
  {"admin": {...}},
  ...
]...)
# Result: One combined map with all policies
```

### Step 4: Flattening Structure (Root Module)
```hcl
for policy_name, policy_data in local.policies_raw :
  policy_name => policy_data
# Result: {"readonly": {...}, "readwrite": {...}, ...}
```

### Step 5: Creating Resources with for_each (Root Module)
```hcl
resource "vault_policy" "policies" {
  for_each = local.policies  # One resource per key
  
  name   = each.key          # "readonly", "readwrite", etc.
  policy = each.value.policy # The HCL policy text
}
```

---

## 🎛️ Feature Control & Conditional Logic

### Conditional Resource Creation

All resources now support feature control flags:

```hcl
# Kubernetes resources (count = number OR 0)
resource "kubernetes_service_account_v1" "vault_auth_sa" {
  count = var.enable_kubernetes_auth ? 1 : 0
  # ...
}

# Vault policies (for_each = map OR empty_map)
resource "vault_policy" "policies" {
  for_each = var.enable_policies ? local.policies : {}
  # ...
}

# Kubernetes roles (requires both flags to be true)
resource "vault_kubernetes_auth_backend_role" "roles" {
  for_each = var.enable_roles && var.enable_kubernetes_auth ? local.k8s_roles : {}
  # ...
}

# Secrets (for_each = map OR empty_map)
resource "vault_kv_secret_v2" "secrets" {
  for_each = var.enable_secrets ? local.secrets_data : {}
  # ...
}
```

### Path Dependencies

When features are disabled:

```
enable_kubernetes_auth=false
  ├─ kubernetes_service_account_v1 (not created)
  ├─ kubernetes_cluster_role_binding_v1 (not created)
  ├─ kubernetes_secret_v1 (not created)
  ├─ vault_auth_backend (not created)
  └─ vault_kubernetes_auth_backend_role (blocked by dependency)

enable_roles=false but enable_kubernetes_auth=true
  ├─ vault_kubernetes_auth_backend_role (not created)
  └─ Other resources created normally

enable_policies=false
  ├─ vault_policy (not created)
  └─ kubernetes roles policy references become empty

enable_secrets=false
  ├─ vault_mount.kv_engine_v2 (not created - count = 0)
  ├─ vault_kv_secret_v2 (not created - empty for_each)
  └─ random password generators (not created - empty for_each)
```

### Updated Configuration Flow with Feature Flags

```
┌─────────────────────────────────────────────────────────────────┐
│         JSON Configuration Files + Feature Flags                │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  resources/secrets/*.json     ─┐                                │
│  enable_secrets = true/false   ├─► Conditional Loading         │
│      ↓                          │                                │
│  IF enabled:                   │                                │
│    - Load files                ├─► Only load/process if        │
│    - Parse JSON                │    feature is enabled          │
│    - Generate passwords        ┤                                │
│      ELSE:                      │                                │
│    - Load empty map {}          │                                │
│                                ─┘                                │
│  resources/policies/*.json                                      │
│  enable_policies = true/false                                   │
│                                                                  │
│  resources/roles/*.json                                         │
│  enable_roles = true/false                                      │
│  enable_kubernetes_auth = true/false                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  Root Module: Conditional Resource Creation                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  IF enable_secrets:                                              │
│    ├─ count = 1                                                  │
│  ELSE:                                                           │
│    ├─ count = 0 (not created)                                   │
│                                                                   │
│  vault_mount "kv_engine_v2" ─┐                                  │
│  vault_kv_secret_v2 "secrets" ┼─ Conditional on enable_secrets│
│  random_string/password ──────┘                                │
│                                                                   │
│  IF enable_policies:                                             │
│    ├─ for_each = local.policies                                 │
│  ELSE:                                                           │
│    ├─ for_each = {}  (not created)                              │
│                                                                   │
│  vault_policy "policies" ──── Conditional on enable_policies   │
│                                                                   │
│  IF enable_kubernetes_auth:                                      │
│    ├─ count = 1                                                  │
│  ELSE:                                                           │
│    ├─ count = 0 (not created)                                   │
│                                                                   │
│  kubernetes_service_account_v1 ──┐                              │
│  kubernetes_secret_v1 ────────────┼─ Conditional on            │
│  vault_auth_backend ───────────────┤ enable_kubernetes_auth    │
│  vault_kubernetes_auth_backend_config ─┘                        │
│                                                                   │
│  IF enable_roles AND enable_kubernetes_auth:                    │
│    ├─ for_each = local.k8s_roles                                │
│  ELSE:                                                           │
│    ├─ for_each = {}  (not created)                              │
│                                                                   │
│  vault_kubernetes_auth_backend_role── Conditional on both      │
│                                        flags                     │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│         Vault State (Deployed Resources)                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Example 1: enable_secrets=false, others=true                  │
│  ├─ KV Engine: NOT mounted                                      │
│  ├─ Policies: Created                                           │
│  ├─ K8s Auth: Configured                                        │
│  └─ K8s Roles: Created                                          │
│                                                                   │
│  Example 2: enable_kubernetes_auth=false                       │
│  ├─ KV Engine: Mounted (if enabled)                            │
│  ├─ Secrets: Created (if enabled)                              │
│  ├─ Policies: Created (if enabled)                             │
│  ├─ K8s Service Account: NOT created                           │
│  ├─ K8s Auth Backend: NOT configured                           │
│  └─ K8s Roles: NOT created (blocked by dependency)             │
│                                                                   │
│  Example 3: All flags false                                     │
│  ├─ Policies: NOT created                                       │
│  ├─ Secrets: NOT created                                        │
│  ├─ K8s Auth: NOT configured                                    │
│  └─ Result: No resources deployed                              │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---



### JSON File (Source)
```json
{
  "readonly": {
    "policy": "path \"PLACEHOLDER/data/*\" {\n  capabilities = [\"read\"]\n}\n"
  }
}
```

### Terraform Processing (Root Module)
```hcl
replace(
  each.value.policy,                    # Source: "path \"PLACEHOLDER/data/*\""
  "PLACEHOLDER",                         # From: "PLACEHOLDER"
  var.kv_secrets_engine_path            # To: "secret"
)
```

### Result in Vault
```
path "secret/data/*" {
  capabilities = ["read"]
}
```

---

## 📂 Consolidated Root Module Architecture

### Single Root Module: terraform/vault/main.tf

The root module (`terraform/vault/main.tf`) is now responsible for:

1. **Loading all JSON files:**
   - `resources/secrets/*.json` - Secret definitions
   - `resources/policies/*.json` - Policy definitions
   - `resources/roles/*.json` - Kubernetes role definitions

2. **Processing data:**
   - Generating random passwords for secrets
   - Replacing PLACEHOLDER in policies
   - Validating policy references in roles

3. **Creating all resources:**
   - `vault_mount` - KV v2 secrets engine
   - `vault_policy` - All policies
   - `vault_kv_secret_v2` - All secrets
   - `vault_kubernetes_auth_backend_role` - All Kubernetes roles
   - `kubernetes_service_account_v1` - Vault auth service account
   - `kubernetes_cluster_role_binding_v1` - Token review access
   - `kubernetes_secret_v1` - Vault auth token
   - `vault_auth_backend` - Kubernetes auth method
   - `vault_kubernetes_auth_backend_config` - Kubernetes auth config

4. **Managing dependencies:**
   - Automatic ordering through resource references
   - Terraform handles all dependency resolution

### Legacy Modules (Deprecated)

The following modules are now deprecated and serve as reference only:
- `kv-secrets-engine/` - Legacy (all functionality in root module)
- `policies-config/` - Legacy (all functionality in root module)
- `kubernetes-auth/` - Legacy (all functionality in root module)

---

## 💾 Data Structure Examples (Root Module Processing)

### Loaded Secrets Map (Local Value)
  "postgresql/postgresql-app" = {
    secret_name = "password"
    content = {
      username = "app_user"
      service  = "postgresql"
    }
  }
}
```

### After Password Generation
```hcl
local.secrets_data = {
  "postgresql/postgresql-admin" = {
    content = {
      username = "admin"
      password = "KgB7xQ9mM2jL5pN"  # Generated
      service  = "postgresql"
    }
  },
  "postgresql/postgresql-app" = {
    content = {
      username  = "app_user"
      password = "xM9pL5QwR2tB8kD" # Generated
      service   = "postgresql"
    }
  }
}
```

### Loaded Policies Map
```hcl
local.policies = {
  "readonly" = {
    description = "Read-only access..."
    policy      = "path \"PLACEHOLDER/data/*\" ..."
  },
  "readwrite" = {
    description = "Read-write access..."
    policy      = "path \"PLACEHOLDER/data/*\" ..."
  }
}
```

### Loaded Kubernetes Roles Map
```hcl
local.k8s_roles = {
  "external-secrets" = {
    service_account_names      = ["external-secrets"]
    service_account_namespaces = ["external-secrets"]
    policies                   = ["readonly"]
    ...
  },
  "tf-runner" = {
    service_account_names      = ["tf-runner"]
    service_account_namespaces = ["flux-system"]
    policies                   = ["readonly", "create-child-token"]
    ...
  }
}
```

---

## � Data Structure Examples (Root Module Processing)

### Loaded Secrets Map (Local Value)
```hcl
local.secrets = {
  "postgresql/postgresql-admin" = {
    secret_name = "password"
    content = {
      username = "admin"
      password = "placeholder"
    }
  },
  "minio/minio-admin" = {
    secret_name = "password"
    content = {
      username = "minioadmin"
      password = "placeholder"
    }
  },
  "oauth2-proxy/cookie" = {
    secret_name     = "cookie-secret"
    password_length = 32
    content = {
      type    = "cookie_encryption"
      service = "oauth2-proxy"
    }
  }
}
```

### After Password Generation
```hcl
local.secrets_data = {
  "postgresql" = {
    content = {
      username = "admin"
      password = "KgB7xQ9mM2jL5pN"  # Generated
    }
  },
  "minio" = {
    content = {
      username = "minioadmin"
      password = "xM9pL5QwR2tB8kD" # Generated
    }
  },
  "oauth2-proxy/cookie" = {
    content = {
      type          = "cookie_encryption"
      service       = "oauth2-proxy"
      cookie-secret = "A1b2C3d4E5f6G7h8J9k0L1m2N3p4Q5r6" # Generated (length 32)
    }
  }
}
```

### Loaded Policies Map
```hcl
local.policies = {
  "readonly" = {
    description = "Read-only access..."
    policy      = "path \"PLACEHOLDER/data/*\" ..."
  },
  "readwrite" = {
    description = "Read-write access..."
    policy      = "path \"PLACEHOLDER/data/*\" ..."
  }
}
```

### Loaded Kubernetes Roles Map
```hcl
local.k8s_roles = {
  "external-secrets" = {
    service_account_names      = ["external-secrets"]
    service_account_namespaces = ["external-secrets"]
    policies                   = ["readonly"]
  },
  "tf-runner" = {
    service_account_names      = ["tf-runner"]
    service_account_namespaces = ["flux-system"]
    policies                   = ["readonly", "create-child-token"]
  }
}
```

---

## 🔍 Debugging & Troubleshooting

### View Root Module Outputs
```bash
terraform output -json | jq '.'
```

### Validate JSON Files
```bash
# Check for syntax errors
for f in resources/**/*.json; do jq . "$f" || echo "Error in $f"; done
```

### Check Root Module Plan
```bash
cd terraform/vault/
tofu plan -out=tfplan
```

### Review Loaded Resources
```bash
# View policy count
tofu plan | grep "vault_policy"

# View secret count
tofu plan | grep "vault_kv_secret_v2"

# View K8s role count
tofu plan | grep "vault_kubernetes_auth_backend_role"
```

### Inspect Resource Definitions
```bash
# See what resources will be created
tofu state show vault_policy.policies[\"readonly\"]

# Check secret contents
tofu state show vault_kv_secret_v2.secrets[\"postgresql\"]
```
terraform output -json | jq '.k8s_roles_loaded.value'
```

### Validate JSON Before Apply
```bash
jq . terraform/vault/policies-config/policies/readonly.json
jq . terraform/vault/kubernetes-auth/roles/external-secrets.json
```

### Check What Resources Will Be Created
```bash
terraform plan | grep 'vault_policy\|vault_kubernetes_auth_backend_role\|vault_kv_secret_v2'
```

### View Actual Vault Configuration
```bash
# List all policies
vault policy list

# View specific policy
vault policy read readonly

# List Kubernetes roles
vault read auth/kubernetes/role/external-secrets
```

---

## ✅ Benefits Summary

✨ **Automatic** - Add JSON file → terraform apply → Resource created  
✨ **Scalable** - 100 secrets = 100 JSON lines, not hundreds of Terraform lines  
✨ **Maintainable** - Clear separation between code and configuration  
✨ **Reusable** - Same pattern across all modules  
✨ **Auditable** - All configuration in version control  
✨ **User-Friendly** - JSON is simpler than HCL for non-engineers  
✨ **Flexible** - Feature control flags allow selective deployment

---

## 🎛️ Feature Flag Decision Tree

```
Want to deploy everything?
  ├─ YES → All flags = true (default) → Single terraform apply
  └─ NO
      │
      ├─> Want Kubernetes auth? 
      │    ├─ YES → enable_kubernetes_auth = true
      │    └─ NO → enable_kubernetes_auth = false
      │
      ├─> Want policies?
      │    ├─ YES → enable_policies = true
      │    └─ NO → enable_policies = false
      │
      ├─> Want secrets?
      │    ├─ YES → enable_secrets = true
      │    └─ NO → enable_secrets = false
      │
      └─> Want K8s roles? (requires kubernetes_auth = true)
           ├─ YES → enable_roles = true
           └─ NO → enable_roles = false
```
