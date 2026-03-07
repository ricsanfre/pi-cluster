variable "tofu_controller_execution" {
  type        = bool
  description = "When true, configure providers for in-cluster Tofu controller execution"
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
  description = "Skip TLS verification when connecting to all services"
  default     = true
}

variable "vault_kv2_path" {
  type        = string
  description = "Path to the KV v2 secrets engine in Vault"
  default     = "secret"
}

variable "kubernetes_config_path" {
  type        = string
  description = "Path to the Kubernetes configuration file (used when tofu_controller_execution=false)"
  default     = "~/.kube/config"
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

variable "elastic_secret_name" {
  type        = string
  description = "Name of the Kubernetes secret containing the bootstrap elastic password"
  default     = "efk-es-elastic-user"
}

variable "elastic_secret_namespace" {
  type        = string
  description = "Namespace of the Kubernetes secret containing the bootstrap elastic password"
  default     = "elastic"
}

variable "elastic_secret_password_key" {
  type        = string
  description = "Data key in the Kubernetes secret that stores the elastic password"
  default     = "elastic"
}

variable "elasticsearch_endpoint" {
  type        = string
  description = "Elasticsearch endpoints"
  default     = "https://elasticsearch.local.test"
}

variable "kibana_endpoint" {
  type        = string
  description = "Kibana endpoints"
  default     = "https://kibana.local.test"
}

variable "elasticsearch_username" {
  type        = string
  description = "Username for Elasticsearch and Kibana"
  default     = "elastic"
}

variable "roles_directory" {
  type        = string
  description = "Directory path containing Elasticsearch role JSON files (relative to root module)"
  default     = "resources/roles"
}

variable "users_directory" {
  type        = string
  description = "Directory path containing Elasticsearch user JSON files (relative to root module)"
  default     = "resources/users"
}

variable "policies_directory" {
  type        = string
  description = "Directory path containing ILM policy JSON files (relative to root module)"
  default     = "resources/policies"
}

variable "templates_directory" {
  type        = string
  description = "Directory path containing index template JSON files (relative to root module)"
  default     = "resources/templates"
}

variable "template_components_directory" {
  type        = string
  description = "Directory path containing component template JSON files (relative to root module)"
  default     = "resources/template_components"
}

variable "dataviews_directory" {
  type        = string
  description = "Directory path containing Kibana data view JSON files (relative to root module)"
  default     = "resources/dataviews"
}
