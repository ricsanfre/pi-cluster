# Terraform Elastic JSON Format Guide

This guide documents the JSON file formats consumed by `terraform/elastic`.

## Naming and file-loading rules

- Files are loaded from these directories:
  - `resources/roles/*.json`
  - `resources/users/*.json`
  - `resources/policies/*.json`
  - `resources/templates/*.json`
  - `resources/template_components/*.json`
  - `resources/dataviews/*.json`
- Resource name is derived from filename (without `.json`).
- Recommended filename pattern: lowercase alphanumeric, `.`, `_`, `-`, `@`.
  - This is validated for role, user, template, and dataview names by the module.

---

## 1) Elasticsearch Roles (`resources/roles/*.json`)

Filename = role name.

API payload alignment:
- Format is similar to Elasticsearch Security Role API payload.
- Reference: https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-security-put-role

```json
{
  "description": "Role description",
  "cluster": ["monitor", "manage_ilm"],
  "indices": [
    {
      "names": ["fluentd-*"],
      "privileges": ["create_index", "write"],
      "field_security": {
        "grant": ["*"],
        "except": []
      },
      "query": {
        "term": { "env": "prod" }
      }
    }
  ],
  "applications": [
    {
      "application": "kibana-.kibana",
      "privileges": ["read"],
      "resources": ["*"]
    }
  ],
  "run_as": ["other-user"],
  "metadata": {
    "managed_by": "terraform"
  }
}
```

Fields:
- `description` optional
- `cluster` optional, list of cluster privileges
- `indices` optional, list
- `applications` optional, list
- `run_as` optional, list
- `metadata` optional, object

---

## 2) Elasticsearch Users (`resources/users/*.json`)

Filename = username.

API payload alignment:
- Format is similar to Elasticsearch Security User API payload.
- Reference: https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-security-put-user
- Module-specific addition: `vault_secret_key` is used to resolve password from Vault KV v2.

```json
{
  "vault_secret_key": "elastic/fluentd",
  "roles": ["fluentd_role"],
  "full_name": "Fluentd User",
  "email": "fluentd@example.com",
  "password_wo_version": 1,
  "metadata": {
    "service_account": true
  }
}
```

Fields:
- `vault_secret_key` optional; if omitted, filename is used
- `roles` optional, list
- `full_name` optional
- `email` optional
- `password_wo_version` optional (default: `1`)
- `metadata` optional, object

Password source:
- Module reads Vault KV v2 secret from `vault_kv2_path` + `vault_secret_key`.
- It expects the secret field `password`.

---

## 3) ILM Policies (`resources/policies/*.json`)

Filename = ILM policy name.

API payload alignment:
- Format is similar to Elasticsearch ILM Policy API payload.
- Reference: https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-ilm-put-lifecycle
- Module caveat: phase actions are modeled directly under each phase (not nested under `actions`).

```json
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "set_priority": { "priority": 100 },
        "rollover": {
          "max_age": "7d",
          "max_primary_shard_size": "10gb"
        }
      },
      "warm": {
        "min_age": "2d",
        "set_priority": { "priority": 50 },
        "readonly": {},
        "shrink": { "number_of_shards": 1 },
        "forcemerge": { "max_num_segments": 1 }
      },
      "delete": {
        "min_age": "7d",
        "delete": {}
      }
    }
  }
}
```

Important:
- The module expects `set_priority`, `rollover`, `readonly`, `shrink`, `forcemerge`, and `delete` directly under each phase object.
- Do not nest these under `actions` for this module format.

---

## 4) Index Templates (`resources/templates/*.json`)

Filename = index template name.

API payload alignment:
- Format is similar to Elasticsearch Composable Index Template API payload.
- Reference: https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-indices-put-index-template

```json
{
  "index_patterns": ["fluentd-*"],
  "priority": 100,
  "composed_of": ["base-log", "ilm-config"],
  "template": {
    "settings": {
      "index.lifecycle.name": "7-days-retention"
    },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" }
      }
    },
    "aliases": {
      "fluentd": { "is_write_index": false }
    }
  },
  "data_stream": {},
  "version": 1,
  "_meta": {
    "description": "Fluentd index template",
    "created_by": "terraform"
  }
}
```

Fields:
- `index_patterns` required, non-empty list
- `template` recommended (`settings`, `mappings`, `aliases` are optional)
- `priority` optional
- `composed_of` optional
- `data_stream` optional
- `version` optional
- `_meta` optional

---

## 5) Component Templates (`resources/template_components/*.json`)

Filename = component template name.

Example: `logs@custom.json` creates component template `logs@custom`.

API payload alignment:
- Format is similar to Elasticsearch Component Template API payload.
- Reference: https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-cluster-put-component-template

```json
{
  "version": 1,
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0
    },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" }
      }
    },
    "aliases": {
      "logs-alias": {
        "is_write_index": false,
        "is_hidden": false
      }
    }
  },
  "meta": {
    "description": "Reusable component template",
    "created_by": "terraform"
  }
}
```

Fields:
- `template` object required (supports `settings`, `mappings`, `aliases`)
- `version` optional
- `meta` optional

---

## 6) Kibana Data Views (`resources/dataviews/*.json`)

Filename = Terraform map key (data view name defaults from `name` or filename).

API payload alignment:
- Format is similar to Kibana Data Views API payload.
- Reference: https://www.elastic.co/guide/en/kibana/current/data-views-api.html

```json
{
  "name": "fluentd-logs",
  "title": "fluentd-*",
  "time_field_name": "@timestamp",
  "namespaces": ["default"],
  "allow_no_index": true
}
```

Fields:
- `name` optional (defaults to filename)
- `title` optional (defaults to filename)
- `time_field_name` optional
- `namespaces` optional
- `allow_no_index` optional

---

## Validation checklist

- File is valid JSON.
- Filename is the intended resource name.
- Role/user/template/dataview filenames use lowercase-safe characters.
- ILM phase actions are not nested under `actions` for this module.
- User Vault secrets include `password` key in KV v2 secret data.
