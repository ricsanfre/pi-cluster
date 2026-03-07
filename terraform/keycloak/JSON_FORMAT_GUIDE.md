# Terraform Keycloak JSON Format Guide

This guide documents the JSON file formats consumed by `terraform/keycloak`.

## Naming and file-loading rules

- Files are loaded from these directories:
  - `resources/realm/realm.json`
  - `resources/clients/*.json`
  - `resources/client_roles/*.json`
  - `resources/groups/*.json`
  - `resources/users/*.json`
  - `resources/scopes/*.json`
- For directory-based resources, resource key is derived from filename (without `.json`).

---

## 1) Realm (`resources/realm/realm.json`)

```json
{
  "realm": "picluster",
  "enabled": true
}
```

Fields:
- `realm` required
- `enabled` optional (default: `true`)

---

## 2) OIDC Clients (`resources/clients/*.json`)

```json
{
  "name": "Grafana",
  "description": "Grafana",
  "vault_secret_ref": "grafana/oauth2",
  "client_id_key": "client-id",
  "client_secret_key": "client-secret",
  "enabled": true,
  "access_type": "CONFIDENTIAL",
  "redirect_uris": [
    "https://monitoring.${CLUSTER_DOMAIN}/grafana/login/generic_oauth"
  ],
  "web_origins": [
    "https://monitoring.${CLUSTER_DOMAIN}/grafana"
  ],
  "root_url": "https://monitoring.${CLUSTER_DOMAIN}/grafana",
  "admin_url": "https://monitoring.${CLUSTER_DOMAIN}/grafana",
  "base_url": "https://monitoring.${CLUSTER_DOMAIN}/grafana",
  "standard_flow_enabled": true,
  "direct_access_grants_enabled": true,
  "implicit_flow_enabled": false,
  "service_accounts_enabled": false,
  "full_scope_allowed": true,
  "default_scopes": ["web-origins", "acr", "roles", "profile", "email"],
  "optional_scopes": ["address", "phone", "offline_access", "microprofile-jwt"]
}
```

Notes:
- `vault_secret_ref` must point to a Vault KV v2 secret containing client id/secret.
- `${CLUSTER_DOMAIN}` placeholders are replaced with `var.cluster_domain`.

---

## 3) Client Roles (`resources/client_roles/*.json`)

Filename must match the Terraform client resource key (for example, `grafana.json` for client defined in `resources/clients/grafana.json`).

```json
{
  "roles": [
    { "name": "admin" },
    { "name": "editor" },
    { "name": "viewer" }
  ]
}
```

---

## 4) Groups (`resources/groups/*.json`)

```json
{
  "name": "admin",
  "client_roles": {
    "grafana": ["admin"]
  }
}
```

Notes:
- `client_roles` keys are client resource keys.
- Role names must exist in matching `resources/client_roles/<client>.json`.

---

## 5) Users (`resources/users/*.json`)

```json
{
  "vault_secret_ref": "keycloak/pi-admin",
  "username_key": "username",
  "password_key": "password",
  "first_name": "Pi",
  "last_name": "Admin",
  "email": "admin@${CLUSTER_DOMAIN}",
  "enabled": true,
  "email_verified": true,
  "groups": ["admin"]
}
```

Notes:
- Username and password are sourced from Vault KV v2 via `vault_secret_ref`.
- `${CLUSTER_DOMAIN}` in `email` is replaced with `var.cluster_domain`.

---

## 6) Client Scopes (`resources/scopes/*.json`)

```json
{
  "name": "roles-id-token",
  "description": "OpenID Connect scope for add user roles to the ID token",
  "include_in_token_scope": true,
  "user_client_role_mappers": {
    "client-roles": {
      "name": "client roles",
      "claim_name": "resource_access.${client_id}.roles",
      "add_to_id_token": true,
      "add_to_access_token": true,
      "add_to_userinfo": true,
      "multivalued": true
    }
  }
}
```
