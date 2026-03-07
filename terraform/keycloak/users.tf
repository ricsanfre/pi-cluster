locals {
  json_user_files = fileset(path.module, "${var.users_directory}/*.json")

  users = {
    for f in local.json_user_files :
    trimsuffix(basename(f), ".json") => jsondecode(file("${path.module}/${f}"))
  }

  user_secret_refs = {
    for user_key, user_data in local.users :
    user_key => user_data.vault_secret_ref
  }
}

data "vault_kv_secret_v2" "user_credentials" {
  for_each = local.user_secret_refs

  mount = var.vault_kv2_path
  name  = each.value
}

locals {
  users_rendered = {
    for user_key, user_data in local.users :
    user_key => merge(
      user_data,
      {
        username = tostring(data.vault_kv_secret_v2.user_credentials[user_key].data[try(user_data.username_key, "username")])
        password = tostring(data.vault_kv_secret_v2.user_credentials[user_key].data[try(user_data.password_key, "password")])
        email    = replace(try(user_data.email, ""), "$${CLUSTER_DOMAIN}", var.cluster_domain)
      }
    )
  }

  user_group_bindings = {
    for user_key, user_data in local.users_rendered :
    user_key => try(user_data.groups, [])
    if length(try(user_data.groups, [])) > 0
  }
}

resource "keycloak_user" "users" {
  for_each = local.users_rendered

  realm_id       = keycloak_realm.realm.id
  username       = each.value.username
  enabled        = try(each.value.enabled, true)
  email_verified = try(each.value.email_verified, true)
  email          = try(each.value.email, null)
  first_name     = try(each.value.first_name, null)
  last_name      = try(each.value.last_name, null)

  initial_password {
    value     = each.value.password
    temporary = false
  }
}

resource "keycloak_user_groups" "user_groups" {
  for_each = local.user_group_bindings

  realm_id = keycloak_realm.realm.id
  user_id  = keycloak_user.users[each.key].id
  group_ids = [
    for group_name in each.value :
    keycloak_group.groups[group_name].id
  ]
}
