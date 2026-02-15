# Terraform root module for Vault configuration
# This module orchestrates all Vault setup:
# 1. Mounts KV v2 secrets engine
# 2. Creates policies from JSON/YAML files
# 3. Creates Kubernetes authentication roles from JSON files
# 4. Configures Kubernetes auth integration
# 5. Loads and creates secrets from JSON files
# 
# Provider configuration and versions managed in versions.tf

provider "vault" {
  address         = var.vault_address
  token           = var.vault_token
  skip_tls_verify = var.vault_skip_tls_verify
}

provider "kubernetes" {
  config_path = var.kubernetes_config_path
}

provider "random" {
  # Configuration options
}

# ============================================================================
# LOAD CONFIGURATION FROM JSON AND YAML FILES
# ============================================================================

# Load and parse secret definition files
locals {
  # Get all JSON files from secrets directory (only if enabled)
  secret_files = var.enable_secrets ? fileset(path.module, "${var.secrets_directory}/*.json") : []

  # Parse JSON files and merge with filename prefixes
  secrets_raw = merge(
    {},
    [
      for f in local.secret_files : {
        for secret_key, secret_value in jsondecode(file("${path.module}/${f}")) :
        "${trimsuffix(basename(f), ".json")}/${secret_key}" => secret_value
      }
    ]...
  )

  # Flatten secrets with path-based keys
  secrets = {
    for secret_key, secret_value in local.secrets_raw :
    secret_key => secret_value
  }
}

# Load and parse policy definition files (JSON and YAML)
locals {
  # Get all JSON files from policies directory (only if enabled)
  policy_files_json = var.enable_policies ? fileset(path.module, "${var.policies_directory}/*.json") : []

  # Get all YAML files from policies directory (only if enabled)
  policy_files_yaml = var.enable_policies ? fileset(path.module, "${var.policies_directory}/*.{yaml,yml}") : []

  # Parse JSON files and merge
  policies_json_raw = merge(
    {},
    [
      for f in local.policy_files_json :
      jsondecode(file("${path.module}/${f}"))
    ]...
  )

  # Parse YAML files and merge
  policies_yaml_raw = merge(
    {},
    [
      for f in local.policy_files_yaml :
      yamldecode(file("${path.module}/${f}"))
    ]...
  )

  # Merge JSON and YAML policies
  policies_raw = merge(local.policies_json_raw, local.policies_yaml_raw)

  # Flatten policies
  policies = {
    for policy_name, policy_data in local.policies_raw :
    policy_name => policy_data
  }
}

# Load and parse Kubernetes role definition files
locals {
  # Get all JSON files from roles directory (only if enabled)
  k8s_role_files = var.enable_roles ? fileset(path.module, "${var.roles_directory}/*.json") : []

  # Parse JSON files and merge
  k8s_roles_raw = merge(
    {},
    [
      for f in local.k8s_role_files :
      jsondecode(file("${path.module}/${f}"))
    ]...
  )

  # Flatten roles
  k8s_roles = {
    for role_name, role_data in local.k8s_roles_raw :
    role_name => role_data
  }
}

# ============================================================================
# MOUNT KV SECRETS ENGINE
# ============================================================================

resource "vault_mount" "kv_engine_v2" {
  count = var.enable_secrets ? 1 : 0

  path = "secret"
  type = "kv-v2"
  options = {
    version = "2"
    type    = "kv-v2"
  }
  description = "KV Version 2 secret engine mount"
}

# ============================================================================
# CREATE VAULT POLICIES FROM JSON
# ============================================================================

resource "vault_policy" "policies" {
  for_each = local.policies

  name   = each.key
  policy = replace(each.value.policy, "PLACEHOLDER", var.kv_secrets_engine_path)
}

# ============================================================================
# SETUP KUBERNETES AUTHENTICATION
# ============================================================================

# Create service account for Vault authentication
resource "kubernetes_service_account_v1" "vault_auth_sa" {
  count = var.enable_kubernetes_auth ? 1 : 0

  metadata {
    name      = var.vault_auth_sa_name
    namespace = var.vault_auth_sa_namespace
    labels = {
      app = "vault-auth"
    }
  }
}

# Create cluster role binding for TokenReview API access
resource "kubernetes_cluster_role_binding_v1" "vault_auth_crb" {
  count = var.enable_kubernetes_auth ? 1 : 0

  metadata {
    name = "vault-auth-tokenreview"
    labels = {
      app = "vault-auth"
    }
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.vault_auth_sa[0].metadata[0].name
    namespace = kubernetes_service_account_v1.vault_auth_sa[0].metadata[0].namespace
  }
}

# Create long-lived token for vault-auth service account
resource "kubernetes_secret_v1" "vault_auth_token" {
  count = var.enable_kubernetes_auth ? 1 : 0

  metadata {
    name      = "vault-auth-token"
    namespace = var.vault_auth_sa_namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.vault_auth_sa[0].metadata[0].name
    }
  }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

# Enable Kubernetes auth method in Vault
resource "vault_auth_backend" "kubernetes" {
  count = var.enable_kubernetes_auth ? 1 : 0

  type = var.k8s_auth_backend_path
}

# Configure the Kubernetes authentication method in Vault
resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  count = var.enable_kubernetes_auth ? 1 : 0

  backend            = vault_auth_backend.kubernetes[0].path
  kubernetes_host    = var.kubernetes_host
  kubernetes_ca_cert = kubernetes_secret_v1.vault_auth_token[0].data["ca.crt"]
  token_reviewer_jwt = kubernetes_secret_v1.vault_auth_token[0].data["token"]
}

# ============================================================================
# CREATE KUBERNETES AUTHENTICATION ROLES FROM JSON
# ============================================================================

resource "vault_kubernetes_auth_backend_role" "roles" {
  for_each = var.enable_roles && var.enable_kubernetes_auth ? local.k8s_roles : {}

  backend                          = vault_auth_backend.kubernetes[0].path
  role_name                        = each.key
  bound_service_account_names      = each.value.service_account_names
  bound_service_account_namespaces = each.value.service_account_namespaces
  token_policies                   = each.value.policies
  audience                         = lookup(each.value, "audience", "https://kubernetes.default.svc.cluster.local")
  token_ttl                        = lookup(each.value, "token_ttl", 3600)
  token_max_ttl                    = lookup(each.value, "token_max_ttl", 86400)

  depends_on = [vault_policy.policies, vault_auth_backend.kubernetes]
}

# ============================================================================
# GENERATE PASSWORDS FOR SECRETS
# ============================================================================

# Generate first character (letter) to ensure password starts with a letter
resource "random_string" "password_first_char" {
  for_each = local.secrets

  length  = 1
  special = false
  upper   = true
  lower   = true
}

# Generate random password with remaining characters
resource "random_password" "password_remaining" {
  for_each = local.secrets

  length  = var.generated_password_length - 1
  special = false
}

# ============================================================================
# MERGE SECRETS WITH GENERATED PASSWORDS
# ============================================================================

locals {
  secrets_data = {
    for key, secret in local.secrets :
    key => {
      content = merge(
        secret.content,
        {
          "${secret.secret_name}" = "${random_string.password_first_char[key].result}${random_password.password_remaining[key].result}"
        }
      )
    }
  }
}

# ============================================================================
# CREATE VAULT SECRETS FROM JSON
# ============================================================================

resource "vault_kv_secret_v2" "secrets" {
  for_each = local.secrets_data

  mount               = vault_mount.kv_engine_v2[0].path
  name                = each.key
  cas                 = 1
  delete_all_versions = true
  data_json           = jsonencode(each.value.content)

  depends_on = [vault_mount.kv_engine_v2]
}
