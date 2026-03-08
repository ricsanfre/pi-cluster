provider "vault" {
  address         = var.vault_address
  token           = var.tofu_controller_execution ? null : var.vault_token
  skip_tls_verify = var.skip_tls_verify

  dynamic "auth_login" {
    for_each = var.tofu_controller_execution ? [1] : []
    content {
      path = var.vault_kubernetes_auth_login_path
      parameters = {
        role = var.vault_kubernetes_auth_role
        jwt  = file(var.kubernetes_token_file)
      }
    }
  }
}

data "vault_kv_secret_v2" "keycloak_admin" {
  mount = var.vault_kv2_path
  name  = var.keycloak_admin_vault_secret
}

provider "keycloak" {
  client_id                = "admin-cli"
  username                 = data.vault_kv_secret_v2.keycloak_admin.data[var.keycloak_admin_username_key]
  password                 = data.vault_kv_secret_v2.keycloak_admin.data[var.keycloak_admin_password_key]
  url                      = var.keycloak_url
  base_path                = var.keycloak_base_path
  tls_insecure_skip_verify = var.skip_tls_verify
}

locals {
  realm = jsondecode(file("${path.module}/${var.realm_file}"))
}

resource "keycloak_realm" "realm" {
  realm   = local.realm.realm
  enabled = try(local.realm.enabled, true)
}
