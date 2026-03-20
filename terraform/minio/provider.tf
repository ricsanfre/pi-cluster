terraform {
  required_version = ">= 1.0"

  required_providers {
    minio = {
      source  = "aminueza/minio"
      version = "3.28.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 4.0"
    }
  }
}

provider "minio" {
  minio_server   = var.minio_endpoint
  minio_region   = var.minio_region
  minio_user     = var.minio_admin_user
  minio_password = var.minio_admin_password
  minio_ssl      = var.minio_use_ssl
  minio_insecure = var.minio_insecure
  minio_debug    = true
}

provider "vault" {
  address         = var.vault_address
  token           = var.vault_token
  skip_tls_verify = var.vault_skip_tls_verify
}
