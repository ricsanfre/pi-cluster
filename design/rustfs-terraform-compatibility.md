# RustFS Compatibility with the MinIO Terraform Provider

This document outlines why and how the **MinIO Terraform Provider (`aminueza/minio`)** successfully manages infrastructure resources—specifically **buckets, IAM users, and IAM policies**—when targeted against a **RustFS** object storage deployment.

---

## Executive Summary

While RustFS is a ground-up rewrite of object storage infrastructure in Rust and **does not** share MinIO's cluster topology, internal server variables, or hardware architecture, it remains fully compatible with the MinIO Terraform provider for core identity and storage resources. 

This compatibility exists because RustFS explicitly emulates two critical API standards: the universal **AWS S3 API Schema** and a highly robust subset of the **MinIO Admin IAM API Schema**.

---

## Deep Dive: How Resources Are Managed

The MinIO Terraform provider splits its internal logic into separate API communication paths based on the resource type being provisioned. RustFS intercepts and processes these requests flawlessly.

### 1. Bucket Resources (`minio_s3_bucket`)
* **Underlying Protocol:** Universal AWS S3 API.
* **Why it works:** RustFS is natively designed as an S3-compatible object store. When Terraform attempts to create a bucket, configure versioning, or set lifecycle rules, the provider sends standard S3 REST commands (e.g., `PUT /bucket-name`). Because RustFS adheres strictly to the global S3 standard, these operations succeed out of the box.

### 2. IAM User Resources (`minio_iam_user`)
* **Underlying Protocol:** MinIO Admin REST API (IAM Subset).
* **Why it works:** Under the hood, the Terraform provider uses the Go Admin Client SDK (`madmin-go`) to manage identity. When deploying a user, the provider targets the endpoint route: `/minio/admin/v3/add-user`. 
* RustFS features a dedicated compatibility layer that listens to this specific endpoint, parses the MinIO-formatted identity payload, and writes the credentials directly into its own internal RustFS identity database.

### 3. IAM Policy & Attachment Resources (`minio_iam_policy` / `_attachment`)
* **Underlying Protocol:** MinIO Admin REST API (IAM Subset).
* **Why it works:** Similar to user management, policy creation routes through `/minio/admin/v3/add-canned-policy`. 
* RustFS fully implements this administrative API layer. It can accept MinIO/AWS-formatted JSON policy documents, evaluate the permission blocks, and bind them to users via `minio_iam_user_policy_attachment` without throwing routing errors.

---

## Operational Summary: What Works vs. What Fails

To ensure predictable infrastructure-as-code deployments, use the following matrix to guide your Terraform designs when targeting RustFS.

| Terraform Resource Type | Compatibility | Technical Reason |
| :--- | :--- | :--- |
| `minio_s3_bucket` | **Fully Supported** | Handled via universal S3 API layer. |
| `minio_iam_user` | **Fully Supported** | RustFS emulates `/minio/admin/v3/add-user`. |
| `minio_iam_policy` | **Fully Supported** | RustFS emulates `/minio/admin/v3/add-canned-policy`. |
| `minio_iam_user_policy_attachment` | **Fully Supported** | Supported by the RustFS identity engine mapping. |
| `minio_server_config_*` | ❌ **Unsupported** | Fails because it tries to alter proprietary MinIO system configurations (`minio.sys`) that do not exist in RustFS. |

---

## Best Practices for RustFS Terraform Deployments

1. **Isolate State:** Use the MinIO provider exclusively for storage topologies (buckets) and access management (users, groups, policies). 
2. **Avoid Server Configurations:** Do not include any Terraform resources that attempt to tweak hardware settings, drive formatting, encryption keys, or server logging at the MinIO engine level.
3. **Toggle S3 Compatibility (Optional):** If you experience any edge-case timeouts during bucket creation, enforce `s3_compat_mode = true` in your provider block to force the provider to drop administrative handshakes and stick strictly to standard S3 loops for data storage.
