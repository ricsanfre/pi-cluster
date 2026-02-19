terraform {
  required_version = ">= 1.0"

  required_providers {
    minio = {
      source  = "aminueza/minio"
      version = "~> 2.0"
    }
  }
}

provider "minio" {
  minio_server   = var.minio_endpoint
  minio_region   = var.minio_region
  minio_user = var.minio_admin_user
  minio_password = var.minio_admin_password

  # Skip TLS certificate validation if using self-signed certificates
  minio_ssl = var.minio_ssl_verify
}
