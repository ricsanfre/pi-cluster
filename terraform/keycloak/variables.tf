variable "tofu_controller_execution" {
  type        = bool
  description = "When true, configure Vault provider auth login for in-cluster Tofu controller execution"
  default     = false
}

variable "vault_address" {
  type        = string
  description = "The address of the Vault server"
  default     = "http://vault.com:8200"
}

variable "vault_token" {
  type        = string
  description = "Vault token for direct execution mode (ignored when tofu_controller_execution=true)"
  default     = ""
  sensitive   = true
  validation {
    condition     = var.tofu_controller_execution || length(trimspace(var.vault_token)) > 0
    error_message = "vault_token must be set when tofu_controller_execution=false."
  }
}

variable "skip_tls_verify" {
  type        = bool
  description = "Skip TLS verification when connecting to Vault and Keycloak"
  default     = true
}

variable "vault_kv2_path" {
  type        = string
  description = "Path to the KV v2 secrets engine in Vault"
  default     = "secret"
}

variable "kubernetes_token_file" {
  type        = string
  description = "Path to Kubernetes service account token file (used for Vault Kubernetes auth login when tofu_controller_execution=true)"
  default     = "/var/run/secrets/kubernetes.io/serviceaccount/token"
}

variable "vault_kubernetes_auth_login_path" {
  type        = string
  description = "Vault Kubernetes auth login path (used when tofu_controller_execution=true)"
  default     = "auth/kubernetes/login"
}

variable "vault_kubernetes_auth_role" {
  type        = string
  description = "Vault Kubernetes auth role name used for login (used when tofu_controller_execution=true)"
  default     = ""
  validation {
    condition     = !var.tofu_controller_execution || length(trimspace(var.vault_kubernetes_auth_role)) > 0
    error_message = "vault_kubernetes_auth_role must be set when tofu_controller_execution=true."
  }
}

variable "keycloak_url" {
  type        = string
  description = "Keycloak base URL"
  default     = "http://keycloak-service.keycloak.svc:8080"
}

variable "keycloak_base_path" {
  type        = string
  description = "Optional Keycloak base path (for legacy installs often /auth)"
  default     = ""
}

variable "cluster_domain" {
  type        = string
  description = "Cluster domain used to render redirect URIs and user emails"
  default     = "local.test"
}

variable "realm_file" {
  type        = string
  description = "Path to realm JSON definition file (relative to root module)"
  default     = "resources/realm/realm.json"
}

variable "clients_directory" {
  type        = string
  description = "Directory path containing client JSON files (relative to root module)"
  default     = "resources/clients"
}

variable "client_roles_directory" {
  type        = string
  description = "Directory path containing client role JSON files (relative to root module)"
  default     = "resources/client_roles"
}

variable "groups_directory" {
  type        = string
  description = "Directory path containing group JSON files (relative to root module)"
  default     = "resources/groups"
}

variable "users_directory" {
  type        = string
  description = "Directory path containing user JSON files (relative to root module)"
  default     = "resources/users"
}

variable "scopes_directory" {
  type        = string
  description = "Directory path containing client scope JSON files (relative to root module)"
  default     = "resources/scopes"
}

variable "keycloak_admin_vault_secret" {
  type        = string
  description = "Vault KV v2 secret path containing Keycloak admin credentials"
  default     = "keycloak/admin"
}

variable "keycloak_admin_username_key" {
  type        = string
  description = "Property name in keycloak_admin_vault_secret containing admin username"
  default     = "username"
}

variable "keycloak_admin_password_key" {
  type        = string
  description = "Property name in keycloak_admin_vault_secret containing admin password"
  default     = "password"
}
