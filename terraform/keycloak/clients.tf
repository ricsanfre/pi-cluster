locals {
  json_client_files = fileset(path.module, "${var.clients_directory}/*.json")

  clients = {
    for f in local.json_client_files :
    trimsuffix(basename(f), ".json") => jsondecode(file("${path.module}/${f}"))
  }

  client_secret_refs = {
    for client_key, client_data in local.clients :
    client_key => client_data.vault_secret_ref
  }
}

data "vault_kv_secret_v2" "client_credentials" {
  for_each = local.client_secret_refs

  mount = var.vault_kv2_path
  name  = each.value
}

locals {
  client_rendered = {
    for client_key, client_data in local.clients :
    client_key => merge(
      client_data,
      {
        client_id     = tostring(data.vault_kv_secret_v2.client_credentials[client_key].data[try(client_data.client_id_key, "client-id")])
        client_secret = tostring(data.vault_kv_secret_v2.client_credentials[client_key].data[try(client_data.client_secret_key, "client-secret")])
        redirect_uris = [for uri in try(client_data.redirect_uris, []) : replace(uri, "$${CLUSTER_DOMAIN}", var.cluster_domain)]
        web_origins   = [for origin in try(client_data.web_origins, []) : replace(origin, "$${CLUSTER_DOMAIN}", var.cluster_domain)]
        root_url      = try(replace(client_data.root_url, "$${CLUSTER_DOMAIN}", var.cluster_domain), null)
        admin_url     = try(replace(client_data.admin_url, "$${CLUSTER_DOMAIN}", var.cluster_domain), null)
        base_url      = try(replace(client_data.base_url, "$${CLUSTER_DOMAIN}", var.cluster_domain), null)
      }
    )
  }
}

resource "keycloak_openid_client" "clients" {
  for_each = local.client_rendered

  realm_id                     = keycloak_realm.realm.id
  client_id                    = each.value.client_id
  name                         = try(each.value.name, null)
  description                  = try(each.value.description, null)
  enabled                      = try(each.value.enabled, true)
  access_type                  = try(each.value.access_type, "CONFIDENTIAL")
  client_secret                = each.value.client_secret
  valid_redirect_uris          = try(each.value.redirect_uris, [])
  web_origins                  = try(each.value.web_origins, [])
  root_url                     = try(each.value.root_url, null)
  admin_url                    = try(each.value.admin_url, null)
  base_url                     = try(each.value.base_url, null)
  standard_flow_enabled        = try(each.value.standard_flow_enabled, true)
  direct_access_grants_enabled = try(each.value.direct_access_grants_enabled, false)
  implicit_flow_enabled        = try(each.value.implicit_flow_enabled, false)
  service_accounts_enabled     = try(each.value.service_accounts_enabled, false)
  full_scope_allowed           = try(each.value.full_scope_allowed, true)
}

resource "keycloak_openid_client_default_scopes" "client_default_scopes" {
  for_each = {
    for key, client in local.client_rendered :
    key => client
    if length(try(client.default_scopes, [])) > 0
  }

  realm_id       = keycloak_realm.realm.id
  client_id      = keycloak_openid_client.clients[each.key].id
  default_scopes = each.value.default_scopes
}

resource "keycloak_openid_client_optional_scopes" "client_optional_scopes" {
  for_each = {
    for key, client in local.client_rendered :
    key => client
    if length(try(client.optional_scopes, [])) > 0
  }

  realm_id        = keycloak_realm.realm.id
  client_id       = keycloak_openid_client.clients[each.key].id
  optional_scopes = each.value.optional_scopes
}
