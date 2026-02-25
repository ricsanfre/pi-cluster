# Minio Provider Configuration Variables

variable "minio_endpoint" {
  type        = string
  description = "Minio server endpoint (hostname:port)"
  default     = "minio.picluster.ricsanfre.com:9000"
}

variable "minio_region" {
  type        = string
  description = "Minio region"
  default     = "eu-west-1"
}

variable "minio_use_ssl" {
  type        = bool
  description = "Use SSL/TLS to connect to Minio"
  default     = true
}

variable "minio_insecure" {
  type        = bool
  description = "Allow insecure SSL/TLS connections"
  default     = false
}

variable "minio_admin_user" {
  type        = string
  description = "Minio root access key"
  sensitive   = true
}

variable "minio_admin_password" {
  type        = string
  description = "Minio root secret key"
  sensitive   = true
}

# Vault integration variables for user secrets

variable "enable_vault_user_secrets" {
  type        = bool
  description = "Read Minio IAM user secrets from Vault"
  default     = true
}

variable "vault_address" {
  type        = string
  description = "The address of the Vault server"
  default     = "http://127.0.0.1:8200"
}

variable "vault_token" {
  type        = string
  description = "Vault token used to read Minio user secrets"
  sensitive   = true
  default     = ""
}

variable "vault_skip_tls_verify" {
  type        = bool
  description = "Skip TLS verification when connecting to Vault"
  default     = false
}

variable "vault_kv_mount" {
  type        = string
  description = "Vault KV v2 mount containing Minio user secrets"
  default     = "secret"
}

variable "vault_minio_users_path_prefix" {
  type        = string
  description = "Vault path prefix where Minio user secrets are stored"
  default     = "minio"
}

variable "vault_minio_user_secret_field" {
  type        = string
  description = "Field name in each Vault secret used as Minio IAM user secret"
  default     = "key"
}

variable "minio_user_default_secret" {
  type        = string
  description = "Fallback Minio IAM user secret when Vault is disabled or field is missing"
  sensitive   = true
  default     = "mySuperSecretKey"
}

# Resource Directory Paths

variable "buckets_dir" {
  type        = string
  description = "Directory path containing bucket configuration JSON files"
  default     = "./resources/buckets"
}

variable "users_dir" {
  type        = string
  description = "Directory path containing user configuration JSON files"
  default     = "./resources/users"
}

variable "policies_dir" {
  type        = string
  description = "Directory path containing policy configuration JSON files"
  default     = "./resources/policies"
}

# Optional Override Variables (for terraform.tfvars customization)

variable "minio_buckets_override" {
  type = map(object({
    name        = string
    versioning  = optional(bool, false)
    object_lock = optional(bool, false)
    description = optional(string, "")
  }))
  description = "Override bucket configurations from files"
  default     = {}
}

variable "minio_users_override" {
  type = map(object({
    access_key  = string
    policies    = optional(list(string), [])
    description = optional(string, "")
  }))
  description = "Override user configurations from files"
  default     = {}
}

variable "minio_policies_override" {
  type = map(object({
    name = string
    statements = list(object({
      effect    = optional(string, "Allow")
      actions   = list(string)
      resources = list(string)
    }))
    description = optional(string, "")
  }))
  description = "Override policy configurations from files"
  default     = {}
}

# Local values that load from individual JSON files in directories

locals {
  # Load all bucket JSON files from buckets directory
  minio_buckets = merge(
    {
      for file in try(fileset(var.buckets_dir, "*.json"), []) :
      regex("^([^.]+)\\.json$", file)[0] =>
      try(jsondecode(file("${var.buckets_dir}/${file}")), {})
    },
    var.minio_buckets_override
  )

  # Load all user JSON files from users directory
  minio_users = merge(
    {
      for file in try(fileset(var.users_dir, "*.json"), []) :
      regex("^([^.]+)\\.json$", file)[0] =>
      try(jsondecode(file("${var.users_dir}/${file}")), {})
    },
    var.minio_users_override
  )

  # Load all policy JSON files from policies directory
  minio_policies = merge(
    {
      for file in try(fileset(var.policies_dir, "*.json"), []) :
      regex("^([^.]+)\\.json$", file)[0] =>
      try(jsondecode(file("${var.policies_dir}/${file}")), {})
    },
    var.minio_policies_override
  )
}
