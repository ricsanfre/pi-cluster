# ADR 0011: Migrate from MinIO to RustFS for S3 Object Storage

Date: 2026-06-19

## Status

Proposed

## Context

### Problem

MinIO has undergone significant licensing changes (AGPLv3 + commercial license), and its recent moves toward a more restrictive governance model raise concerns for homelab and self-hosted environments. Additionally, MinIO's resource footprint on ARM64 (Raspberry Pi) nodes can be high, and the project's direction increasingly targets enterprise deployments rather than small-scale self-hosted use cases.

RustFS is an emerging S3-compatible object storage server written in Rust. It is fully open-source, designed for performance and low resource consumption, and provides a clean migration path from MinIO with minimal changes to the surrounding infrastructure.

### Decision

Replace MinIO with RustFS as the cluster's S3 object storage backend, deployed as an external service on `node1` (bare-metal, outside Kubernetes). Use the `ricsanfre.rustfs` Ansible role for deployment and continue using the existing `aminueza/minio` Terraform provider for bucket, user, and policy management — validated to work against RustFS's S3-compatible API.

**Key migration design choices:**

| Concern | Decision | Rationale |
|---------|----------|-----------|
| S3 API port | Keep 9091 (override `rustfs_server_port`) | Avoids changes to all Kubernetes consumers |
| Hostname | Keep `object-store.homelab.ricsanfre.com` | Same DNS record, same `S3_SERVER` ConfigMap |
| Vault paths | Keep `secret/minio/*` | Avoids changes to 8 ExternalSecret resources |
| Data directory | Keep `/storage/minio` | Transparent to backup/restic tooling |
| TLS | Same certbot/self-signed flow | Reuse existing certificate generation |
| Terraform | Keep `terraform/minio/` unchanged | `aminueza/minio` provider works against RustFS |
| Monitoring | Remove direct Prometheus scrape configs | RustFS uses OTLP push, not direct scrape endpoints |

## Options Considered

### Option 1: Replace MinIO role with RustFS role, keep Terraform (selected)

Use `ricsanfre.rustfs` Ansible role for deployment, keep `terraform/minio/` for resource management.

- **Pros:**
  - Minimal code changes — Terraform module unchanged, Kubernetes consumers unchanged
  - S3 API compatibility confirmed (IAM users, policies, buckets work via `aminueza/minio` provider)
  - Simple rollback: swap role back to `ricsanfre.minio`, redeploy
  - RustFS CLI (`rc`) provides full admin operations as a fallback
  - Lower resource footprint (Rust, static musl builds, native ARM64 support)
- **Cons:**
  - RustFS is younger than MinIO (beta software at v1.0.0-beta.7)
  - Monitoring approach differs significantly (OTLP vs direct Prometheus scrape)
  - No MinIO-compatible admin API for advanced operations (relies on Terraform provider compatibility)
  - Fewer community resources and operational runbooks

### Option 2: Replace MinIO role and rewrite Terraform to use `rc` CLI

Replace both the Ansible role and Terraform module, managing all S3 resources via `rc` CLI in Ansible tasks.

- **Pros:**
  - Fully native RustFS tooling — no dependency on MinIO provider compatibility
  - Ansible-based resource management fits the existing operational model
- **Cons:**
  - Larger code change — entire Terraform module rewritten as Ansible tasks
  - Loss of Terraform state tracking for S3 resources
  - More Ansible code to maintain (policy JSON handling, idempotency, etc.)
  - Higher risk of configuration drift without state management

### Option 3: Deploy RustFS inside Kubernetes via Helm/operator

Run RustFS as a Kubernetes workload instead of a bare-metal external service.

- **Pros:**
  - GitOps-native (FluxCD manages the HelmRelease)
  - Kubernetes scheduling and self-healing
  - No Ansible playbook needed
- **Cons:**
  - S3 storage is a cluster dependency — running it inside the cluster creates a circular dependency for backup/restore (Velero, Longhorn)
  - Storage performance depends on CSI/network layers
  - Adds complexity to cluster bootstrap (need S3 before FluxCD can start)
  - Contradicts the existing architecture where external services run outside the cluster

### Option 4: Stay on MinIO

Continue using MinIO with the existing setup.

- **Pros:**
  - No migration work needed
  - Mature, battle-tested software
  - Existing monitoring dashboards and runbooks
- **Cons:**
  - Licensing uncertainty (AGPLv3 + recent commercial moves)
  - Higher memory footprint on ARM64 nodes
  - Increasing divergence from self-hosted/homelab use cases
  - Misses opportunity to adopt Rust-based tooling with better ARM64 performance

## Consequences

### Positive

- **Reduced resource footprint:** RustFS (Rust, musl static binary) is expected to use less CPU and memory than MinIO (Go) on ARM64 Raspberry Pi nodes
- **License clarity:** RustFS is fully open-source without the commercial licensing concerns that surround MinIO
- **Minimal code changes:** Only 2 new files (playbook + task), 8 modified; Terraform module, Kubernetes consumers, Vault paths, and DNS all unchanged
- **Clean rollback path:** The old `deploy_minio.yml` playbook and `ricsanfre.minio` role are preserved; switching back requires only a redeploy
- **S3 API compatibility validated:** The existing `aminueza/minio` Terraform provider creates IAM users, policies, and buckets against RustFS without modification

### Negative

- **Monitoring gap:** RustFS does not expose direct Prometheus HTTP scrape endpoints. It uses OpenTelemetry (OTLP) push to a collector. The MinIO-specific Prometheus scrape configs, bearer token ExternalSecret, and Grafana dashboards (IDs 13502, 19237, 15305) have been removed. Monitoring RustFS requires deploying an OpenTelemetry Collector and configuring `RUSTFS_OBS_ENDPOINT` — a separate project tracked outside this ADR.
- **Software maturity:** RustFS is at beta stage (v1.0.0-beta.7). Production usage carries higher risk of bugs or missing features compared to mature MinIO releases.
- **Console differences:** The RustFS web console runs on port 9092 (vs MinIO's 9092 — same port kept). The console UI and feature set differ from MinIO's.
- **No `mc` compatibility:** RustFS uses `rc` CLI instead of `mc`. Operational scripts and muscle memory need updating for CLI operations (alias management, bucket operations, admin commands).

### Neutral

- **Hostname and ports unchanged:** `object-store.homelab.ricsanfre.com:9091` — all Kubernetes consumers (Velero, Loki, Tempo, Longhorn, CNPG) connect identically
- **Vault integration unchanged:** Credentials stored at the same paths (`secret/minio/root`, `secret/minio/<user>`, `secret/minio/prometheus`)
- **TLS certificate flow unchanged:** Same certbot/self-signed generation, same cert files deployed
- **Terraform module fully preserved:** The `terraform/minio/` directory is untouched; `configure_minio.yml` still runs it
- **Downstream impact:** Zero changes to Kubernetes manifests, ExternalSecrets, HelmRelease values, or FluxCD Kustomizations
- **Backup compatibility:** Restic continues using the same S3 endpoint and credentials

## References

- [RustFS GitHub](https://github.com/rustfs/rustfs)
- [RustFS CLI (`rc`) GitHub](https://github.com/rustfs/cli)
- [ricsanfre.rustfs Ansible Role](https://galaxy.ansible.com/ui/standalone/roles/ricsanfre/rustfs/)
- [ricsanfre.rustfs Role Source](https://github.com/ricsanfre/ansible-role-rustfs)
- [RustFS Observability Docs](https://docs.rustfs.com/features/logging/)
- [PR #1347 — Prometheus metrics endpoints (rejected)](https://github.com/rustfs/rustfs/pull/1347)
- [MinIO Terraform Provider (`aminueza/minio`)](https://registry.terraform.io/providers/aminueza/minio/latest)
- [MinIO Licensing FAQ](https://min.io/pricing)
- Existing ADRs: [0010-descheduler-for-pod-distribution.md](0010-descheduler-for-pod-distribution.md)
