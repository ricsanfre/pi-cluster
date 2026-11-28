terraform {
  required_version = ">= 1.0.0"
  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "5.11.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.14.0"
    }
  }
}
