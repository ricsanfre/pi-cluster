locals {
  json_client_role_files = fileset(path.module, "${var.client_roles_directory}/*.json")

  client_roles_by_client = {
    for f in local.json_client_role_files :
    trimsuffix(basename(f), ".json") => jsondecode(file("${path.module}/${f}"))
  }

  client_roles = {
    for item in flatten([
      for client_key, role_data in local.client_roles_by_client : [
        for role in try(role_data.roles, []) : {
          key         = "${client_key}/${role.name}"
          client_key  = client_key
          name        = role.name
          description = try(role.description, null)
        }
      ]
    ]) : item.key => item
  }
}

resource "keycloak_role" "client_roles" {
  for_each = local.client_roles

  realm_id    = keycloak_realm.realm.id
  client_id   = keycloak_openid_client.clients[each.value.client_key].id
  name        = each.value.name
  description = each.value.description
}
