# Cluster Operation Runbooks

Operational runbooks for the Pi Kubernetes Cluster, grouped by scope so cluster-wide and
component-specific procedures coexist.

Runbooks are **not** design documents. Design notes and ADRs live in [`design/`](../design/),
architecture and how-to documentation is published from [`docs/_docs/`](../docs/_docs/).

## How to use

1. Match the symptom to an entry in the [Runbook Catalog](#runbook-catalog).
2. Follow the linked runbook in one of the domain files below.
3. After an incident, update the runbook with what actually happened. See
   [Adding a runbook](#adding-a-runbook).

If no runbook covers the situation, start from a triage runbook (`GITOPS-002`, `GITOPS-003`,
`OPS-001`) and record the gap.

## Domains

### Cluster-wide

| Domain | File | Runbook IDs |
| --- | --- | --- |
| Bootstrap and Recovery | [`cluster/bootstrap-recovery.md`](cluster/bootstrap-recovery.md) | `CLUSTER-001`, `CLUSTER-002` (backlog: `CLUSTER-003`) |
| Nodes and Capacity | [`cluster/nodes-capacity.md`](cluster/nodes-capacity.md) | `CLUSTER-010` … `CLUSTER-012`, `CLUSTER-014` (backlog: `CLUSTER-013`) |
| GitOps and Release Operations | [`cluster/gitops-release.md`](cluster/gitops-release.md) | `GITOPS-001` … `GITOPS-006` |
| Security and Access | [`cluster/security-access.md`](cluster/security-access.md) | `SEC-001` … `SEC-003` (backlog: `SEC-004`, `SEC-005`) |
| Upgrades and Change Management | [`cluster/change-management.md`](cluster/change-management.md) | `CHANGE-001`, `CHANGE-002` (backlog: `CHANGE-003`, `CHANGE-004`) |
| Backup and Compliance | [`cluster/backup-compliance.md`](cluster/backup-compliance.md) | `BACKUP-001` … `BACKUP-003` (backlog: `AUDIT-001`) |
| Operations and Governance | [`cluster/operations-governance.md`](cluster/operations-governance.md) | `OPS-001`, `OPS-002` (backlog: `OPS-003`, `OPS-004`) |

### Components

| Domain | File | Runbook IDs |
| --- | --- | --- |
| Keycloak | [`components/keycloak.md`](components/keycloak.md) | `KEYCLOAK-001` … `KEYCLOAK-013` |
| Vault | [`components/vault.md`](components/vault.md) | `VAULT-001` … `VAULT-005` |
| S3 Storage (RustFS) | [`components/s3-storage.md`](components/s3-storage.md) | `MINIO-001` (backlog: `MINIO-002` … `MINIO-005`) |
| Elastic and Logging | [`components/elastic-logging.md`](components/elastic-logging.md) | `ELASTIC-001` (backlog: `ELASTIC-002` … `ELASTIC-005`) |
| Monitoring and Tracing | [`components/observability.md`](components/observability.md) | `OBS-001`, `OBS-004` (backlog: `OBS-002`, `OBS-003`, `OBS-005`) |
| Service Mesh and Ingress | [`components/networking-ingress.md`](components/networking-ingress.md) | `NET-004` … `NET-008` (backlog: `NET-001` … `NET-003`) |
| Kafka and Data Services | — | backlog only: `KAFKA-001`, `KAFKA-002`, `MONGO-001`, `PG-001` |

## Runbook Template

Use this template for every new runbook section.

```markdown
## <ID> <Runbook Title>

<a id="runbook-<lowercase-id>"></a>
Runbook ID: <DOMAIN-###>
Owner: <team-or-person>
Severity: <SEV-1|SEV-2|SEV-3|Maintenance>

Objective: <what this runbook solves>

Preconditions:
- <state/permissions/tools required>

Procedure:
1. <step>
2. <step>
3. <step>

Verify:
- <health signal>
- <health signal>

Rollback:
1. <rollback step>
2. <rollback step>

References:
- <path-or-url>
```

## Adding a runbook

1. Pick the domain file under `cluster/` or `components/`, or create a new domain file and add it
   to the [Domains](#domains) table.
2. Add the runbook at the end of that file using the template above. Keep the
   `<a id="runbook-<id>"></a>` anchor immediately after the heading — the catalog links to it.
3. Move the entry in the catalog below from plain text (backlog) to a link pointing at
   `<file>#runbook-<id>`.
4. Keep runbook IDs stable. Retire a runbook by marking it superseded; never renumber.

## Runbook Catalog

### Cluster-Wide Backlog Catalog

#### Bootstrap and Recovery

- [`CLUSTER-001` Full Cluster Bootstrap from Zero](cluster/bootstrap-recovery.md#runbook-cluster-001)
- [`CLUSTER-002` Disaster Recovery from Git and Backups](cluster/bootstrap-recovery.md#runbook-cluster-002)
- `CLUSTER-003` Full Restore Validation Drill

#### Nodes and Capacity

- [`CLUSTER-010` Node Replacement Workflow](cluster/nodes-capacity.md#runbook-cluster-010)
- [`CLUSTER-011` Planned Node Drain and Maintenance](cluster/nodes-capacity.md#runbook-cluster-011)
- [`CLUSTER-012` Node Disk Pressure Response](cluster/nodes-capacity.md#runbook-cluster-012)
- [`CLUSTER-014` Hung Node and etcd Quorum Loss Recovery](cluster/nodes-capacity.md#runbook-cluster-014)
- `CLUSTER-013` Cluster Capacity Expansion Checklist

#### GitOps and Release Operations

- [`GITOPS-001` Flux Source Outage Triage](cluster/gitops-release.md#runbook-gitops-001)
- [`GITOPS-002` Kustomization Stuck or Not-Ready Triage](cluster/gitops-release.md#runbook-gitops-002)
- [`GITOPS-003` HelmRelease Stuck or Not-Ready Triage](cluster/gitops-release.md#runbook-gitops-003)
- [`GITOPS-004` Safe Suspend and Resume Strategy](cluster/gitops-release.md#runbook-gitops-004)
- [`GITOPS-005` Flux Upgrade and Rollback](cluster/gitops-release.md#runbook-gitops-005)
- [`GITOPS-006` Branch-Based Live Validation Workflow](cluster/gitops-release.md#runbook-gitops-006)

#### Security and Access

- [`SEC-001` Credential Leak Response and Rotation](cluster/security-access.md#runbook-sec-001)
- [`SEC-002` Compromised Node Isolation and Rebuild](cluster/security-access.md#runbook-sec-002)
- [`SEC-003` TLS Private Key Compromise Response](cluster/security-access.md#runbook-sec-003)
- `SEC-004` RBAC Audit and Least-Privilege Review
- `SEC-005` Emergency Break-Glass Access

#### Upgrades and Change Management

- [`CHANGE-001` Pre-Change Go/No-Go Checklist](cluster/change-management.md#runbook-change-001)
- [`CHANGE-002` Post-Change Validation Checklist](cluster/change-management.md#runbook-change-002)
- `CHANGE-003` Platform Upgrade Orchestration and Rollback
- `CHANGE-004` Planned Maintenance Communications Checklist

#### Backup and Compliance

- [`BACKUP-001` Velero Namespace Restore Drill](cluster/backup-compliance.md#runbook-backup-001)
- [`BACKUP-002` Velero Full-Cluster Restore Drill](cluster/backup-compliance.md#runbook-backup-002)
- [`BACKUP-003` Backup Retention and Cleanup Execution](cluster/backup-compliance.md#runbook-backup-003)
- `AUDIT-001` Incident Evidence Collection and Audit Trail

#### Operations and Governance

- [`OPS-001` Incident Command Workflow](cluster/operations-governance.md#runbook-ops-001)
- [`OPS-002` Postmortem Template and Action Tracking](cluster/operations-governance.md#runbook-ops-002)
- `OPS-003` Monthly Platform Health Review Checklist
- `OPS-004` Runbook Review and Stale Runbook Cleanup Process

### Component Backlog Catalog

#### Keycloak

- [`KEYCLOAK-001` Wipe and recreate Keycloak database from scratch](components/keycloak.md#runbook-keycloak-001)
- [`KEYCLOAK-002` Keycloak config reconcile and drift recovery](components/keycloak.md#runbook-keycloak-002)
- [`KEYCLOAK-003` Restore Keycloak DB from CNPG backup](components/keycloak.md#runbook-keycloak-003)
- [`KEYCLOAK-004` Rotate Keycloak admin credentials (Vault + Keycloak)](components/keycloak.md#runbook-keycloak-004)
- [`KEYCLOAK-005` Rotate OIDC client secrets (Grafana, Kiali, OAuth2-Proxy)](components/keycloak.md#runbook-keycloak-005)
- [`KEYCLOAK-006` Keycloak Flux Kustomization incident triage](components/keycloak.md#runbook-keycloak-006)
- [`KEYCLOAK-007` Keycloak tofu-controller failure modes](components/keycloak.md#runbook-keycloak-007)
- [`KEYCLOAK-008` Keycloak CNPG cluster health and failover checks](components/keycloak.md#runbook-keycloak-008)
- [`KEYCLOAK-009` Keycloak namespace and service DNS debugging](components/keycloak.md#runbook-keycloak-009)
- [`KEYCLOAK-010` Planned upgrade (Keycloak, Operator, DB)](components/keycloak.md#runbook-keycloak-010)
- [`KEYCLOAK-011` Emergency disable of Keycloak SSO dependencies](components/keycloak.md#runbook-keycloak-011)
- [`KEYCLOAK-012` Safe decommission of Keycloak stack](components/keycloak.md#runbook-keycloak-012)
- [`KEYCLOAK-013` Keycloak post-incident validation checklist](components/keycloak.md#runbook-keycloak-013)

#### Vault

- [`VAULT-001` Vault Outage Triage and Unseal Workflow](components/vault.md#runbook-vault-001)
- [`VAULT-002` Vault Token, Policy, and Role Rotation](components/vault.md#runbook-vault-002)
- [`VAULT-003` Vault Backup and Restore](components/vault.md#runbook-vault-003)
- [`VAULT-004` Vault Auth Backend Troubleshooting (Kubernetes, AppRole)](components/vault.md#runbook-vault-004)
- [`VAULT-005` Vault Seal Migration and Key Rotation](components/vault.md#runbook-vault-005)

#### S3 Storage (RustFS)

- [`MINIO-001` MinIO Service Degradation Triage](components/s3-storage.md#runbook-minio-001)
- `MINIO-002` MinIO Credentials Rotation and Validation
- `MINIO-003` MinIO Backup Target Outage and Recovery
- `MINIO-004` MinIO Bucket Policy Audit and Restore
- `MINIO-005` MinIO Upgrade and Rollback

#### Elastic and Logging

- [`ELASTIC-001` Elasticsearch Red or Yellow Cluster Recovery](components/elastic-logging.md#runbook-elastic-001)
- `ELASTIC-002` Kibana Unavailability Triage
- `ELASTIC-003` Fluent Bit and Fluentd Ingestion Failure
- `ELASTIC-004` ILM and Index Template Drift Recovery
- `ELASTIC-005` Elastic Stack Upgrade and Rollback

#### Monitoring and Tracing

- [`OBS-001` Prometheus Target Missing Triage](components/observability.md#runbook-obs-001)
- `OBS-002` Alertmanager Notification Failures
- `OBS-003` Grafana Data Source and Auth Recovery
- [`OBS-004` Loki Ingestion and Retention Issues](components/observability.md#runbook-obs-004)
- `OBS-005` Tempo Tracing Pipeline Outage

#### Kafka and Data Services

- `KAFKA-001` Kafka Broker Outage and Partition Recovery
- `KAFKA-002` Kafka Auth and ACL Drift Recovery
- `MONGO-001` MongoDB Operator Failover and Restore
- `PG-001` CloudNativePG Generic Failover Operations

#### Service Mesh and Ingress

- `NET-001` Cilium Datapath Outage Triage
- `NET-002` Ingress NGINX Outage Triage
- `NET-003` ExternalDNS Reconciliation Failures
- [`NET-004` CoreDNS Outage and Recovery](components/networking-ingress.md#runbook-net-004)
- [`NET-005` TLS Certificate Issuance Failures (cert-manager)](components/networking-ingress.md#runbook-net-005)
- [`NET-006` TLS Endpoint Certificate Inspection and Chain Validation](components/networking-ingress.md#runbook-net-006)
- [`NET-007` Certificate Renewal Monitoring and Forced Reissuance](components/networking-ingress.md#runbook-net-007)
- [`NET-008` TLS Secret and Served Certificate Mismatch](components/networking-ingress.md#runbook-net-008)
