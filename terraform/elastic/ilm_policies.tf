
locals {
  policy_files = fileset(path.module, "${var.policies_directory}/*.json")

  policies = {
    for file in local.policy_files :
    trimsuffix(basename(file), ".json") => jsondecode(file("${path.module}/${file}"))
  }
}

resource "elasticstack_elasticsearch_index_lifecycle" "policies" {
  for_each = local.policies

  name = each.key

  dynamic "hot" {
    for_each = try([each.value.policy.phases.hot], [])
    content {
      min_age = hot.value.min_age
      dynamic "set_priority" {
        for_each = try([hot.value.set_priority], [])
        content {
          priority = set_priority.value.priority
        }
      }
      dynamic "rollover" {
        for_each = try([hot.value.rollover], [])
        content {
          max_age                = rollover.value.max_age
          max_primary_shard_size = rollover.value.max_primary_shard_size
        }
      }
    }
  }

  dynamic "warm" {
    for_each = try([each.value.policy.phases.warm], [])
    content {
      min_age = warm.value.min_age
      dynamic "set_priority" {
        for_each = try([warm.value.set_priority], [])
        content {
          priority = set_priority.value.priority
        }
      }
      dynamic "readonly" {
        for_each = try([warm.value.readonly], [])
        content {}
      }
      dynamic "shrink" {
        for_each = try([warm.value.shrink], [])
        content {
          number_of_shards = shrink.value.number_of_shards
        }
      }
      dynamic "forcemerge" {
        for_each = try([warm.value.forcemerge], [])
        content {
          max_num_segments = forcemerge.value.max_num_segments
        }
      }
    }
  }

  dynamic "delete" {
    for_each = try([each.value.policy.phases.delete], [])
    content {
      min_age = delete.value.min_age
      dynamic "delete" {
        for_each = try([delete.value.delete], [])
        content {}
      }
    }
  }
}