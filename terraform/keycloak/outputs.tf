output "realm" {
  description = "Created Keycloak realm"
  value = {
    id      = keycloak_realm.realm.id
    realm   = keycloak_realm.realm.realm
    enabled = keycloak_realm.realm.enabled
  }
}

output "clients" {
  description = "Created OIDC clients"
  sensitive   = true
  value = {
    for k, v in keycloak_openid_client.clients :
    k => {
      id        = v.id
      client_id = v.client_id
      name      = v.name
      enabled   = v.enabled
    }
  }
}

output "client_roles" {
  description = "Created Keycloak client roles"
  value = {
    for k, v in keycloak_role.client_roles :
    k => {
      id   = v.id
      name = v.name
    }
  }
}

output "groups" {
  description = "Created Keycloak groups"
  value = {
    for k, v in keycloak_group.groups :
    k => {
      id   = v.id
      name = v.name
    }
  }
}

output "users" {
  description = "Created Keycloak users (non-sensitive summary)"
  sensitive   = true
  value = {
    for k, v in keycloak_user.users :
    k => {
      id             = v.id
      username       = v.username
      email          = v.email
      email_verified = v.email_verified
      enabled        = v.enabled
    }
  }
}

output "scopes" {
  description = "Created custom OIDC client scopes"
  value = {
    for k, v in keycloak_openid_client_scope.scopes :
    k => {
      id   = v.id
      name = v.name
    }
  }
}
