terraform {
  required_version = ">= 1.0.0"
  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = ">= 4.0.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.8.0"
    }
  }
}
