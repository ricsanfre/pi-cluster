# Vault Policies YAML Migration Guide

## Overview

Vault policies now support **YAML format** in addition to JSON. YAML provides better readability for multiline policy definitions, making it easier to maintain and debug Vault policies.

## Why Migrate to YAML?

### Before (JSON)
```json
{
  "readonly": {
    "description": "Read-only access to all secrets",
    "policy": "path \"PLACEHOLDER/data/*\" {\n  capabilities = [\"read\", \"list\"]\n}\npath \"PLACEHOLDER/metadata/*\" {\n  capabilities = [\"list\", \"read\"]\n}\n"
  }
}
```

**Issues:**
- Newlines are escaped as `\n` - hard to read
- Policy rules are unclear
- Error-prone when editing
- Difficult to understand rule intent

### After (YAML)
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

**Benefits:**
- ✅ Natural multiline format
- ✅ Easy to read and understand
- ✅ Easier to maintain
- ✅ Clear policy structure
- ✅ Supports comments in policy files

## Migration Steps

### Option 1: Gradual Migration (Recommended)

Keep both JSON and YAML files running simultaneously until confident.

**Step 1:** Create YAML versions of your policies

```bash
cd terraform/vault/resources/policies/

# Create readonly.yaml
cat > readonly.yaml << 'EOF'
readonly:
  description: "Read-only access to all secrets"
  policy: |
    path "PLACEHOLDER/data/*" {
      capabilities = ["read", "list"]
    }
    path "PLACEHOLDER/metadata/*" {
      capabilities = ["list", "read"]
    }
EOF
```

**Step 2:** Test with Terraform plan

```bash
cd ../..
terraform plan
```

All policies should still be created (just loading from YAML instead of JSON)

**Step 3:** Apply the changes

```bash
terraform apply
```

Vault should show the same policies - the migration is transparent!

**Step 4:** (Optional) Remove JSON files once confident

```bash
rm resources/policies/*.json
```

### Option 2: Complete Cutover

Migrate all policies at once by creating all YAML versions.

**Files to create:**
- `readonly.yaml`
- `readwrite.yaml`
- `admin.yaml`
- `create-child-token.yaml`
- `external-secrets.yaml`
- `terraform-runner.yaml`
- `backup.yaml`

YAML examples are provided in the same directory as starter templates.

## Conversion Reference

### Basic Structure

**JSON:**
```json
{
  "policy-name": {
    "description": "Description",
    "policy": "path \"...\" { ... }"
  }
}
```

**YAML:**
```yaml
policy-name:
  description: "Description"
  policy: |
    path "..." {
      ...
    }
```

### Multiline String in YAML

Use the pipe (`|`) character for multiline strings:

```yaml
policy: |
  path "PLACEHOLDER/data/*" {
    capabilities = ["read", "list"]
  }
  path "PLACEHOLDER/metadata/*" {
    capabilities = ["read", "list"]
  }
```

The `|` character preserves all newlines in the string.

### Special Characters

In YAML, quotes are usually unnecessary:

**JSON:**
```json
"description": "Read-write access to \"PLACEHOLDER\""
```

**YAML:**
```yaml
description: "Read-write access to PLACEHOLDER"
```

### Arrays

**JSON:**
```json
"capabilities": ["read", "update", "delete"]
```

**YAML:**
```yaml
capabilities:
  - read
  - update
  - delete
```

OR (on one line):
```yaml
capabilities: ["read", "update", "delete"]
```

## Real-World Examples

### Read-Write Policy with Multiple Paths

**YAML:**
```yaml
readwrite:
  description: "Full CRUD on all secrets"
  policy: |
    # Data operations
    path "PLACEHOLDER/data/*" {
      capabilities = ["create", "read", "update", "delete", "list", "patch"]
    }
    
    # Metadata operations
    path "PLACEHOLDER/metadata/*" {
      capabilities = ["list", "read", "delete"]
    }
    
    # Token management
    path "auth/token/renew-self" {
      capabilities = ["update"]
    }
```

### Environmental Separation

```yaml
app-prod-secrets:
  description: "Production app secrets only"
  policy: |
    path "PLACEHOLDER/data/prod/app-config/*" {
      capabilities = ["read", "list"]
    }
    
    # Audit logging
    path "sys/audit" {
      capabilities = ["read"]
    }

app-dev-secrets:
  description: "Development app secrets"
  policy: |
    path "PLACEHOLDER/data/dev/app-config/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
```

### Role-Based Access

```yaml
database-admin:
  description: "Database administrator access"
  policy: |
    # Database passwords
    path "PLACEHOLDER/data/database/admin/*" {
      capabilities = ["read", "list"]
    }
    
    # Database audit logs
    path "sys/audit" {
      capabilities = ["read", "list"]
    }

database-readonly:
  description: "Database read-only access"
  policy: |
    path "PLACEHOLDER/data/database/readonly/*" {
      capabilities = ["read"]
    }
```

## Validation

### Check YAML Syntax

Before deploying, validate your YAML files:

```bash
# Using yq (YAML processor)
for f in resources/policies/*.yaml; do
  echo "Checking $f..."
  yq . "$f" > /dev/null || echo "ERROR: Invalid YAML in $f"
done

# Using Python
for f in resources/policies/*.yaml; do
  python3 -c "import yaml; yaml.safe_load(open('$f'))" \
    && echo "✓ $f" || echo "✗ $f"
done
```

### Validate Terraform

```bash
terraform validate
terraform plan
```

If the plan shows the same number of resources as before, the migration is complete!

## Troubleshooting

### "yamldecode" function not found

Ensure you're using OpenTofu/Terraform with YAML support:

```bash
terraform version
# Should be Terraform >= 1.3.0 or OpenTofu >= 1.6.0
```

### Policy file not being loaded

Check that the file has the correct extension (`.yaml` or `.yml`):

```bash
ls -la resources/policies/
# Should show .yaml or .json files
```

### Policies not matching after migration

Ensure the YAML indentation is correct - YAML is indentation-sensitive:

```yaml
# CORRECT
policy: |
  path "..." {
    capabilities = [...]
  }

# INCORRECT (will fail)
policy: |
path "..." {
capabilities = [...]
}
```

## Reverting

If you need to revert to JSON, simply delete the YAML files:

```bash
rm resources/policies/*.yaml

terraform plan  # Will now use JSON files
```

All JSON files are still valid and will be used.

## Summary of Changes

- ✅ Main.tf updated to support both JSON and YAML policies
- ✅ YAML policy examples provided in resources/policies/
- ✅ Documentation updated to explain YAML format
- ✅ Both formats work simultaneously (no migration required)
- ✅ Backward compatible (all existing JSON policies continue to work)

## Next Steps

1. Review the YAML policy examples
2. Test with `terraform plan`
3. Remove JSON files when confident (optional)
4. Continue using YAML for new policies

## References

- [YAML Format Guide](JSON_FORMAT_GUIDE.md#-policies-yaml-format-recommended)
- [Configuration Flow](CONFIGURATION_FLOW.md)
- [Vault Policy Documentation](https://www.vaultproject.io/docs/concepts/policies)
