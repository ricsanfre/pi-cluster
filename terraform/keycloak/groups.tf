locals {
  json_group_files = fileset(path.module, "${var.groups_directory}/*.json")

  groups = {
    for f in local.json_group_files :
    trimsuffix(basename(f), ".json") => jsondecode(file("${path.module}/${f}"))
  }

  group_role_bindings = {
    for item in flatten([
      for group_key, group_data in local.groups : [
        for client_key, role_names in try(group_data.client_roles, {}) : {
          key        = "${group_key}/${client_key}"
          group_key  = group_key
          client_key = client_key
          role_ids = [
            for role_name in role_names :
            keycloak_role.client_roles["${client_key}/${role_name}"].id
          ]
        }
      ]
    ]) : item.key => item
  }
}

resource "keycloak_group" "groups" {
  for_each = local.groups

  realm_id = keycloak_realm.realm.id
  name     = try(each.value.name, each.key)
}

resource "keycloak_group_roles" "group_client_roles" {
  for_each = local.group_role_bindings

  realm_id = keycloak_realm.realm.id
  group_id = keycloak_group.groups[each.value.group_key].id
  role_ids = each.value.role_ids
}
