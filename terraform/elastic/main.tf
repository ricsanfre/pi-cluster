provider "kubernetes" {
  config_path = var.tofu_controller_execution ? null : var.kubernetes_config_path
}

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

data "kubernetes_secret_v1" "elastic_user_secret" {
  metadata {
    name      = var.elastic_secret_name
    namespace = var.elastic_secret_namespace
  }
}

provider "elasticstack" {
  elasticsearch {
    endpoints = [var.elasticsearch_endpoint]
    username  = var.elasticsearch_username
    password  = data.kubernetes_secret_v1.elastic_user_secret.data[var.elastic_secret_password_key]
    insecure  = var.skip_tls_verify
  }
  kibana {
    endpoints = [var.kibana_endpoint]
    username  = var.elasticsearch_username
    password  = data.kubernetes_secret_v1.elastic_user_secret.data[var.elastic_secret_password_key]
    insecure  = var.skip_tls_verify
  }
}
