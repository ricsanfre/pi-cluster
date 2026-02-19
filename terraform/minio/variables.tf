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

variable "minio_ssl_verify" {
  type        = bool
  description = "Verify SSL certificate validity"
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
    name          = string
    versioning    = optional(bool, false)
    object_lock   = optional(bool, false)
    description   = optional(string, "")
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
    name       = string
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
