# Locals
# This local variable `templates` defines Elasticsearch index templates that are created from JSON files.
# Index templates are used to automatically configure indices when they are created matching specified patterns.
# The definitions are read from JSON files in the "templates" directory.
# Each JSON file should contain the template's index_patterns, settings, and mappings.

# JSON structure is the same payload required by the Elasticsearch API for index template creation
#    ref: https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-indices-put-template

# File name indicates the template name, and the content should be a JSON object with the following structure:

# {
#   "index_patterns" : [ "logs-*", "logstash-*" ],
#   "priority" : 100,
#   "template" : {
#     "settings" : {
#       "number_of_shards" : 1,
#       "number_of_replicas" : 0,
#       "index.lifecycle.name" : "policy-name"
#     },
#     "mappings" : {
#       "properties" : {
#         "@timestamp" : { "type" : "date" },
#         "message" : { "type" : "text" }
#       }
#     },
#     "aliases" : {
#       "my-alias" : { "is_write_index" : true }
#     }
#   },
#   "composed_of" : [ "component-template-1", "component-template-2" ],
#   "version" : 1,
#   "_meta" : {
#     "description" : "Template description",
#     "created_by" : "terraform"
#   }
# }

locals {
  json_template_files = fileset(path.module, "${var.templates_directory}/*.json")

  # Extract template names from file paths using cleaner approach
  templates = {
    for f in local.json_template_files :
    trimsuffix(basename(f), ".json") => jsondecode(file("${path.module}/${f}"))
  }

  # Validate template names comply with Elasticsearch naming conventions
  template_name_validation = {
    for name in keys(local.templates) :
    name => {
      is_valid = can(regex("^[a-z0-9._-]+$", name))
      message  = can(regex("^[a-z0-9._-]+$", name)) ? "valid" : "ERROR: Template name contains invalid characters. Use lowercase alphanumeric, hyphens, underscores, or dots."
    }
  }

  # Validate index patterns are not empty
  template_pattern_validation = {
    for name, config in local.templates :
    name => {
      patterns_valid = try(length(config.index_patterns) > 0, false)
      message        = try(length(config.index_patterns) > 0, false) ? "valid" : "ERROR: index_patterns must not be empty."
    }
  }
}

# Resources
resource "elasticstack_elasticsearch_index_template" "index_templates" {
  for_each       = local.templates
  name           = each.key
  index_patterns = each.value.index_patterns

  # Template priority for resolution order when multiple templates match
  priority = try(each.value.priority, 0)

  # Compose this template from component templates
  composed_of = try(each.value.composed_of, [])

  # Main template configuration with settings, mappings, and aliases
  template {
    settings = try(jsonencode(each.value.template.settings), null)
    mappings = try(jsonencode(each.value.template.mappings), null)

    # Template-level aliases
    dynamic "alias" {
      for_each = try([each.value.template.aliases], [])
      content {
        name           = alias.key
        is_write_index = try(alias.value.is_write_index, false)
        filter         = try(jsonencode(alias.value.filter), null)
        routing        = try(alias.value.routing, null)
        is_hidden      = try(alias.value.is_hidden, false)
      }
    }
  }

  # Data stream configuration (for data streams instead of regular indices)
  dynamic "data_stream" {
    for_each = try([each.value.data_stream], [])
    content {}
  }

  # Template version for tracking and updates
  version = try(each.value.version, 1)

  # Metadata for documentation and tracking
  metadata = try(jsonencode(each.value._meta), null)
}