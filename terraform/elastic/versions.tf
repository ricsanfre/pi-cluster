terraform {
  required_version = ">= 1.0.0"
  required_providers {
    elasticstack = {
      source  = "elastic/elasticstack"
      version = "0.17.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.14.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.5.0"
    }
  }
}
