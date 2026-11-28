terraform {
  required_version = ">= 1.0.0"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.14.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}
