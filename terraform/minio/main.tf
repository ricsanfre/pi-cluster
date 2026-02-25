# Minio S3 Buckets

resource "minio_s3_bucket" "buckets" {
  for_each = local.minio_buckets

  bucket         = each.value.name
  object_locking = each.value.object_lock
  force_destroy  = true

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

# NOTE: This uses the deprecated `data.vault_kv_secret_v2` on purpose because
# the current `aminueza/minio` provider cannot consume ephemeral values in
# `minio_iam_user.secret`.
# Expected warning:
# "Deprecated. Please use new Ephemeral KVV2 Secret resource `vault_kv_secret_v2` instead"
data "vault_kv_secret_v2" "minio_user_secrets" {
  for_each = var.enable_vault_user_secrets ? local.minio_users : {}

  mount = var.vault_kv_mount
  name  = "${var.vault_minio_users_path_prefix}/${each.value.access_key}"
}

resource "minio_iam_user" "users" {
  for_each = local.minio_users
  name     = each.value.access_key
  secret = var.enable_vault_user_secrets ? lookup(
    data.vault_kv_secret_v2.minio_user_secrets[each.key].data,
    var.vault_minio_user_secret_field,
    var.minio_user_default_secret
  ) : var.minio_user_default_secret

  depends_on = [minio_iam_policy.policies]
}

# Attach Policies to Users

resource "minio_iam_user_policy_attachment" "user_policies" {
  for_each = {
    for pair in flatten([
      for user_key, user_config in local.minio_users : [
        for policy in user_config.policies : {
          user_key    = user_key
          user_name   = user_config.access_key
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

