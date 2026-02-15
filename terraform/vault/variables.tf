# Vault Address Configuration
variable "vault_address" {
  type        = string
  description = "The address of the Vault server"
  sensitive   = false
  validation {
    condition     = can(regex("^https?://", var.vault_address))
    error_message = "vault_address must start with http:// or https://"
  }
}

# Vault Authentication Token
variable "vault_token" {
  type        = string
  description = "Vault token to be used during authentication"
  sensitive   = true
}

# TLS Configuration
variable "vault_skip_tls_verify" {
  type        = bool
  description = "Skip TLS verification when connecting to Vault (not recommended for production)"
  default     = false
}

# KV Secrets Engine Path
variable "kv_secrets_engine_path" {
  type        = string
  description = "Path where KV Version 2 secrets engine is mounted"
  default     = "secret"
}

# JSON Configuration Directories
variable "secrets_directory" {
  type        = string
  description = "Directory path containing secrets JSON files (relative to root module)"
  default     = "resources/secrets"
}

variable "policies_directory" {
  type        = string
  description = "Directory path containing policies JSON files (relative to root module)"
  default     = "resources/policies"
}

variable "roles_directory" {
  type        = string
  description = "Directory path containing Kubernetes roles JSON files (relative to root module)"
  default     = "resources/roles"
}

variable "generated_password_length" {
  type        = number
  description = "Length of the generated password for secrets"
  default     = 15
  validation {
    condition     = var.generated_password_length >= 8
    error_message = "Password length must be at least 8 characters."
  }
}

# Kubernetes Configuration
variable "kubernetes_config_path" {
  type        = string
  description = "Path to the Kubernetes configuration file"
  default     = "~/.kube/config"
}

variable "kubernetes_host" {
  type        = string
  description = "The Kubernetes API server host URL"
  default     = "https://kubernetes.default.svc.cluster.local"
}

# Kubernetes Authentication Setup
variable "vault_auth_sa_name" {
  type        = string
  description = "Name of the service account for Vault authentication"
  default     = "vault-auth-sa"
}

variable "vault_auth_sa_namespace" {
  type        = string
  description = "Namespace where the Vault auth service account will be created"
  default     = "default"
}

variable "k8s_auth_backend_path" {
  type        = string
  description = "Path where Kubernetes auth method is mounted in Vault"
  default     = "kubernetes"
}

# ============================================================================
# FEATURE CONTROL FLAGS
# ============================================================================

variable "enable_kubernetes_auth" {
  type        = bool
  description = "Enable Kubernetes authentication configuration (service account, auth backend, and role creation)"
  default     = true
}

variable "enable_policies" {
  type        = bool
  description = "Enable creation of Vault policies from JSON files"
  default     = true
}

variable "enable_roles" {
  type        = bool
  description = "Enable creation of Kubernetes authentication roles from JSON files"
  default     = true
}

variable "enable_secrets" {
  type        = bool
  description = "Enable creation of Vault secrets from JSON files"
  default     = true
}
