# Root module outputs for Vault configuration
# Provides outputs for KV secrets engine, policies, and Kubernetes authentication

# ============================================================================
# KV Secrets Engine Outputs
# ============================================================================

output "kv_engine_path" {
  description = "Path where KV Version 2 secrets engine is mounted"
  value       = var.enable_secrets ? vault_mount.kv_engine_v2[0].path : null
}

output "kv_engine_id" {
  description = "Identifier of the KV Version 2 secrets engine"
  value       = var.enable_secrets ? vault_mount.kv_engine_v2[0].id : null
}

output "secrets_created" {
  description = "List of secrets created in Vault"
  value       = var.enable_secrets ? keys(vault_kv_secret_v2.secrets) : []
}

output "secrets_count" {
  description = "Number of secrets created"
  value       = var.enable_secrets ? length(vault_kv_secret_v2.secrets) : 0
}

# ============================================================================
# Policies Configuration Outputs
# ============================================================================

output "policies_created" {
  description = "List of all created policies"
  value       = var.enable_policies ? keys(vault_policy.policies) : []
}

output "policies" {
  description = "All created Vault policies with names"
  value = var.enable_policies ? {
    for name, policy in vault_policy.policies :
    name => policy.name
  } : {}
}

output "policy_names_and_rules" {
  description = "Map of policy names and their rule definitions"
  value = var.enable_policies ? {
    for name, policy in vault_policy.policies :
    name => policy.policy
  } : {}
  sensitive = true
}

# ============================================================================
# Kubernetes Authentication Outputs
# ============================================================================

output "vault_auth_sa_name" {
  description = "Name of the Vault authentication service account"
  value       = var.enable_kubernetes_auth ? kubernetes_service_account_v1.vault_auth_sa[0].metadata[0].name : null
}

output "vault_auth_sa_namespace" {
  description = "Namespace of the Vault authentication service account"
  value       = var.enable_kubernetes_auth ? kubernetes_service_account_v1.vault_auth_sa[0].metadata[0].namespace : null
}

output "vault_auth_token_secret" {
  description = "Name of the secret containing the Vault authentication token"
  value       = var.enable_kubernetes_auth ? kubernetes_secret_v1.vault_auth_token[0].metadata[0].name : null
}

output "kubernetes_auth_backend_path" {
  description = "Path where Kubernetes auth method is mounted in Vault"
  value       = var.enable_kubernetes_auth ? vault_auth_backend.kubernetes[0].path : null
}

output "kubernetes_auth_roles" {
  description = "List of created Kubernetes authentication roles"
  value       = var.enable_roles && var.enable_kubernetes_auth ? keys(vault_kubernetes_auth_backend_role.roles) : []
}

output "kubernetes_auth_roles_detail" {
  description = "Detailed information about created Kubernetes authentication roles"
  value = var.enable_roles && var.enable_kubernetes_auth ? {
    for role_name, role in vault_kubernetes_auth_backend_role.roles :
    role_name => {
      service_accounts = role.bound_service_account_names
      namespaces       = role.bound_service_account_namespaces
      policies         = role.token_policies
      token_ttl        = role.token_ttl
      token_max_ttl    = role.token_max_ttl
    }
  } : {}
}

output "vault_ca_certificate" {
  description = "Kubernetes CA certificate used for Vault auth"
  value       = var.enable_kubernetes_auth ? kubernetes_secret_v1.vault_auth_token[0].data["ca.crt"] : null
  sensitive   = true
}

output "vault_token_reviewer_jwt" {
  description = "JWT token for reviewing Vault authentication tokens"
  value       = var.enable_kubernetes_auth ? kubernetes_secret_v1.vault_auth_token[0].data["token"] : null
  sensitive   = true
}

# ============================================================================
# Configuration Summary
# ============================================================================

output "vault_configuration_summary" {
  description = "Summary of Vault configuration"
  value = {
    vault_address             = var.vault_address
    kv_engine_path            = var.enable_secrets ? vault_mount.kv_engine_v2[0].path : "disabled"
    secrets_deployed          = var.enable_secrets ? length(vault_kv_secret_v2.secrets) : 0
    total_policies            = var.enable_policies ? length(vault_policy.policies) : 0
    policies                  = var.enable_policies ? keys(vault_policy.policies) : []
    kubernetes_auth_enabled   = var.enable_kubernetes_auth
    kubernetes_auth_backend   = var.enable_kubernetes_auth ? vault_auth_backend.kubernetes[0].path : "disabled"
    kubernetes_roles_deployed = (var.enable_roles && var.enable_kubernetes_auth) ? length(vault_kubernetes_auth_backend_role.roles) : 0
    kubernetes_roles          = (var.enable_roles && var.enable_kubernetes_auth) ? keys(vault_kubernetes_auth_backend_role.roles) : []
  }
}

# ============================================================================
# Loaded Configuration (for debugging)
# ============================================================================

output "secrets_loaded" {
  description = "Loaded secrets from JSON files"
  value       = local.secrets
}

output "policies_loaded" {
  description = "Loaded policies from JSON files"
  value       = local.policies
}

output "k8s_roles_loaded" {
  description = "Loaded Kubernetes roles from JSON files"
  value       = local.k8s_roles
}
