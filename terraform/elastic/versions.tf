terraform {
  required_version = ">= 1.0.0"
  required_providers {
    elasticstack = {
      source  = "elastic/elasticstack"
      version = "0.14.5"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.8.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.1"
    }
  }
}
