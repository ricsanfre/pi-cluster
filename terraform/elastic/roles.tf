# Locals
# This local variable `roles` defines the roles to be created in Elasticsearch. 
# The user definitions are read from JSON files in the "roles" directory.
# Each JSON file should contain the role's description, cluster privileges, index privileges and application privileges.

# JSON structure is the same payload required by the Elasticsearch API for role creation
#    ref: https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-security-put-role

# File name indicates the role name, and the content of the file should be a JSON object with the following structure:

# {
#   "description" : "Role description",
#   "cluster" : [ "cluster_privilege1", "cluster_privilege2" ],
#   "indices" : [
#     {
#       "names" : [ "index1", "index2" ],
#       "privileges" : [ "index_privilege1", "index_privilege2" ],
#       "field_security" : {
#         "grant" : [ "field1", "field2" ]
#       },
#       "query" : {
#         "match" : {
#           "field" : "value"
#         }
#       }
#     }
#   ],
#   "applications" : [
#     {
#       "application" : "myapp",
#       "privileges" : [ "admin", "read" ],
#       "resources" : [ "*" ]
#     }
#   ],
#   "run_as" : [ "user1", "user2" ],
#   "metadata" : {
#     "key1" : "value1",
#     "key2" : "value2"
#   }
# }

# `roles` local variable is a map of objects, where the key is the name of the file (role name) and the value is an object containing the json content of the file

locals {
  json_role_files = fileset(path.module, "${var.roles_directory}/*.json")

  # Extract role names from file paths using trimsuffix
  roles = {
    for f in local.json_role_files :
    trimsuffix(basename(f), ".json") => jsondecode(file("${path.module}/${f}"))
  }

  # Validate role names comply with Elasticsearch naming conventions
  role_name_validation = {
    for name in keys(local.roles) :
    name => {
      is_valid = can(regex("^[a-z0-9._-]+$", name))
      message  = can(regex("^[a-z0-9._-]+$", name)) ? "valid" : "ERROR: Role name contains invalid characters. Use lowercase alphanumeric, hyphens, underscores, or dots."
    }
  }
}

# Resources
resource "elasticstack_elasticsearch_security_role" "roles" {
  for_each = local.roles

  name        = each.key
  description = try(each.value.description, "Managed by Terraform")
  cluster     = try(each.value.cluster, [])

  # Index-level permissions with optional field and document-level security
  dynamic "indices" {
    for_each = try(each.value.indices, [])
    content {
      names      = indices.value.names
      privileges = indices.value.privileges

      # Optional field-level security (grant/deny specific fields)
      dynamic "field_security" {
        for_each = try([indices.value.field_security], [])
        content {
          grant  = try(field_security.value.grant, [])
          except = try(field_security.value.except, [])
        }
      }
      query = try(jsonencode(indices.value.query), null)
    }

  }

  # Application privileges (optional)
  dynamic "applications" {
    for_each = try(each.value.applications, [])
    content {
      application = applications.value.application
      privileges  = applications.value.privileges
      resources   = applications.value.resources
    }
  }

  # Run-as privilege (optional) - allows this role to impersonate other users
  run_as = try(each.value.run_as, [])

  # Metadata for documentation and tracking (optional)
  metadata = try(
    each.value.metadata != null ? jsonencode(each.value.metadata) : null,
    null
  )
}