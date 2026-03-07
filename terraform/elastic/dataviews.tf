# Locals
# Allow defining Kibana data views via JSON files.
locals {
  json_dataview_files = fileset(path.module, "${var.dataviews_directory}/*.json")

  dataviews = {
    for f in local.json_dataview_files :
    trimsuffix(basename(f), ".json") => jsondecode(file("${path.module}/${f}"))
  }

  # Validate dataview names
  dataview_name_validation = {
    for name in keys(local.dataviews) :
    name => {
      is_valid = can(regex("^[a-z0-9._-]+$", name))
      message  = can(regex("^[a-z0-9._-]+$", name)) ? "valid" : "ERROR: Data view name contains invalid characters. Use lowercase alphanumeric, hyphens, underscores, or dots."
    }
  }
}

# Resources
resource "elasticstack_kibana_data_view" "data_views" {
  for_each = local.dataviews

  data_view = {
    name            = try(each.value.name, each.key)
    title           = try(each.value.title, each.key)
    time_field_name = try(each.value.time_field_name, null)
    namespaces      = try(each.value.namespaces, null)
    allow_no_index  = try(each.value.allow_no_index, null)
    # Provider accepts arbitrary additional fields inside data_view map depending on version.
  }
}