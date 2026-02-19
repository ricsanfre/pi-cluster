# Minio S3 Buckets

resource "minio_s3_bucket" "buckets" {
  for_each = local.minio_buckets

  bucket        = each.value.name
  object_locking   = each.value.object_lock
  force_destroy = true

  depends_on = [minio_iam_policy.policies]
}

# Minio S3 Bucket Versioning

resource "minio_s3_bucket_versioning" "bucket_versioning" {
  for_each = {
    for key, bucket in local.minio_buckets : key => bucket
    if bucket.versioning == true
  }

  bucket = minio_s3_bucket.buckets[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Minio IAM Policies

resource "minio_iam_policy" "policies" {
  for_each = local.minio_policies

  name = each.value.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for stmt in each.value.statements : {
        Effect   = stmt.effect
        Action   = stmt.actions
        Resource = stmt.resources
      }
    ]
  })
}

# Minio IAM Users

resource "minio_iam_user" "users" {
  for_each = local.minio_users

  name = each.value.access_key

  depends_on = [minio_iam_policy.policies]
}

# Attach Policies to Users

resource "minio_iam_user_policy_attachment" "user_policies" {
  for_each = {
    for pair in flatten([
      for user_key, user_config in local.minio_users : [
        for policy in user_config.policies : {
          user_key   = user_key
          user_name  = user_config.access_key
          policy_name = policy
        }
      ]
    ]) : "${pair.user_key}-${pair.policy_name}" => pair
  }

  user_name   = minio_iam_user.users[each.value.user_key].name
  policy_name = each.value.policy_name

  depends_on = [
    minio_iam_user.users,
    minio_iam_policy.policies
  ]
}
