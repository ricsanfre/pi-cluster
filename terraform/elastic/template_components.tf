# Manage reusable Elasticsearch template components
# These components can be composed together to create complex index templates
# Component files should be stored in JSON format in the template_components/ directory

locals {
  # Load all JSON component files from the template_components directory
  component_files = fileset(path.module, "${var.template_components_directory}/*.json")

  # Parse component files into a map
  components = {
    for file in local.component_files :
    trimsuffix(basename(file), ".json") => jsondecode(file("${path.module}/${file}"))
  }
}

# Create component templates for different index patterns
# These can be used as building blocks for more complex templates
resource "elasticstack_elasticsearch_component_template" "components" {
  for_each = local.components

  name = each.key

  lifecycle {
    precondition {
      condition     = try(length(keys(each.value.template)) > 0, false)
      error_message = "Component template '${each.key}' must define a non-empty top-level 'template' object (for example: template.settings, template.mappings, or template.aliases)."
    }
  }

  # Template settings (performance tuning, refresh interval, etc.)
  template {
    # Index settings
    settings = try(jsonencode(each.value.template.settings), null)

    # Field mappings and metadata
    mappings = try(jsonencode(each.value.template.mappings), null)

    # Aliases for the index
    dynamic "alias" {
      for_each = try([each.value.template.aliases], [])
      content {
        name           = alias.key
        is_write_index = try(alias.value.is_write_index, false)
        is_hidden      = try(alias.value.is_hidden, false)

        filter  = try(jsonencode(alias.value.filter), null)
        routing = try(alias.value.routing, null)
      }
    }
  }

  # Component metadata and version for tracking
  version = try(each.value.version, 1)

  # Component description for documentation
  metadata = try(jsonencode(each.value.meta), null)
}
