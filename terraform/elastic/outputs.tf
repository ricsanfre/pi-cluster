# Root module outputs for Elastic configuration

output "elastic_user_secret" {
  description = "Elastic bootstrap user password read from Kubernetes secret"
  value       = data.kubernetes_secret_v1.elastic_user_secret.data[var.elastic_secret_password_key]
  sensitive   = true
}

output "roles_summary" {
  description = "Summary of created Elasticsearch roles with non-sensitive attributes"
  value = {
    for k, v in elasticstack_elasticsearch_security_role.roles :
    k => {
      name        = v.name
      description = v.description
    }
  }
}

output "roles_names" {
  description = "List of created role names"
  value       = keys(elasticstack_elasticsearch_security_role.roles)
}

output "role_validation_status" {
  description = "Validation status for role naming conventions"
  value       = local.role_name_validation
}

output "users_summary" {
  description = "Summary of created Elasticsearch users (non-sensitive)"
  value = {
    for k, v in elasticstack_elasticsearch_security_user.users :
    k => {
      username  = v.username
      roles     = v.roles
      full_name = v.full_name
      email     = v.email
    }
  }
}

output "users_names" {
  description = "List of created usernames"
  value       = keys(elasticstack_elasticsearch_security_user.users)
}

output "user_validation_status" {
  description = "Validation status for usernames"
  value       = local.user_name_validation
}

output "ilm_policies" {
  description = "Created Elasticsearch ILM policies"
  value       = elasticstack_elasticsearch_index_lifecycle.policies
}

output "index_templates_summary" {
  description = "Summary of created Elasticsearch index templates with non-sensitive attributes"
  value = {
    for k, v in elasticstack_elasticsearch_index_template.index_templates :
    k => {
      name           = v.name
      index_patterns = v.index_patterns
      priority       = v.priority
      composed_of    = v.composed_of
      version        = v.version
    }
  }
}

output "index_templates_names" {
  description = "List of created index template names"
  value       = keys(elasticstack_elasticsearch_index_template.index_templates)
}

output "template_validation_status" {
  description = "Validation status for template naming conventions and index patterns"
  value = {
    names    = local.template_name_validation
    patterns = local.template_pattern_validation
  }
}

output "component_templates" {
  description = "All created Elasticsearch component templates"
  value = {
    for k, v in elasticstack_elasticsearch_component_template.components :
    k => {
      name    = v.name
      version = v.version
    }
  }
}

output "available_components" {
  description = "List of available template components"
  value       = keys(local.components)
}

output "dataviews_summary" {
  description = "Summary of created Kibana data views"
  value = {
    for k, v in elasticstack_kibana_data_view.data_views :
    k => {
      name            = v.data_view.name
      title           = v.data_view.title
      time_field_name = v.data_view.time_field_name
      namespaces      = v.data_view.namespaces
    }
  }
}

output "dataviews_names" {
  description = "List of created dataview names"
  value       = keys(elasticstack_kibana_data_view.data_views)
}

output "dataview_validation_status" {
  description = "Validation status for dataview names"
  value       = local.dataview_name_validation
}
