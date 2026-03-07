locals {
  json_scope_files = fileset(path.module, "${var.scopes_directory}/*.json")

  scopes = {
    for f in local.json_scope_files :
    trimsuffix(basename(f), ".json") => jsondecode(file("${path.module}/${f}"))
  }
}

resource "keycloak_openid_client_scope" "scopes" {
  for_each = local.scopes

  realm_id               = keycloak_realm.realm.id
  name                   = try(each.value.name, each.key)
  description            = try(each.value.description, null)
  include_in_token_scope = try(each.value.include_in_token_scope, true)
}

resource "keycloak_openid_user_client_role_protocol_mapper" "scope_role_mappers" {
  for_each = {
    for item in flatten([
      for scope_key, scope_data in local.scopes : [
        for mapper_key, mapper_data in try(scope_data.user_client_role_mappers, {}) : {
          key       = "${scope_key}/${mapper_key}"
          scope_key = scope_key
          mapper    = mapper_data
        }
      ]
    ]) : item.key => item
  }

  realm_id            = keycloak_realm.realm.id
  client_scope_id     = keycloak_openid_client_scope.scopes[each.value.scope_key].id
  name                = each.value.mapper.name
  claim_name          = each.value.mapper.claim_name
  add_to_id_token     = try(each.value.mapper.add_to_id_token, true)
  add_to_access_token = try(each.value.mapper.add_to_access_token, true)
  add_to_userinfo     = try(each.value.mapper.add_to_userinfo, true)
  multivalued         = try(each.value.mapper.multivalued, true)
}
