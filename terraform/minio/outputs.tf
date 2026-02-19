# Minio S3 Bucket Outputs

output "buckets" {
  description = "List of created Minio S3 buckets"
  value = {
    for bucket_key, bucket_resource in minio_s3_bucket.buckets :
    bucket_key => {
      name = bucket_resource.bucket
      arn  = "arn:aws:s3:::${bucket_resource.bucket}"
    }
  }
}

# Minio IAM Policies Outputs

output "policies" {
  description = "List of created IAM policies and their statements"
  value = {
    for policy_key, policy_resource in minio_iam_policy.policies :
    policy_key => {
      name   = policy_resource.name
      policy = policy_resource.policy
    }
  }
  sensitive = true
}

# Minio IAM Users Outputs

output "users" {
  description = "List of created Minio IAM users and their assigned policies"
  value = {
    for user_key, user_resource in minio_iam_user.users :
    user_key => {
      name     = user_resource.name
      policies = try(local.minio_users[user_key].policies, [])
    }
  }
}

# User Service Mapping

output "user_service_mapping" {
  description = "Mapping of users to their services and required credentials"
  value = {
    for user_key, user_config in local.minio_users : user_config.access_key => {
      access_key = user_config.access_key
      buckets    = [for policy in user_config.policies : policy]
      policies   = user_config.policies
      description = user_config.description
    }
  }
}

# Configuration Summary

output "minio_configuration_summary" {
  description = "Summary of Minio configuration"
  value = {
    buckets_count  = length(minio_s3_bucket.buckets)
    users_count    = length(minio_iam_user.users)
    policies_count = length(minio_iam_policy.policies)
    endpoint       = var.minio_endpoint
    region         = var.minio_region
  }
}
