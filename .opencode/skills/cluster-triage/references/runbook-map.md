# Runbook Map

Symptom-to-runbook index for triage. Canonical catalog: [`runbooks/README.md`](../../../runbooks/README.md).

## Cluster-wide

### Bootstrap and recovery — `runbooks/cluster/bootstrap-recovery.md`

| ID | Use when |
| --- | --- |
| `CLUSTER-001` | Rebuilding the cluster from zero (new hardware, clean OS, full reinstall) |
| `CLUSTER-002` | Recovering a lost cluster from Git and backups |

### Nodes and capacity — `runbooks/cluster/nodes-capacity.md`

| ID | Use when |
| --- | --- |
| `CLUSTER-010` | Replacing a failed node |
| `CLUSTER-011` | Planned drain, reboot, or maintenance |
| `CLUSTER-012` | `DiskPressure`, evictions, or a full node filesystem |

### GitOps and release — `runbooks/cluster/gitops-release.md`

| ID | Use when |
| --- | --- |
| `GITOPS-001` | Flux cannot fetch from Git; source `READY=False` |
| `GITOPS-002` | A Kustomization is stuck or not ready |
| `GITOPS-003` | A HelmRelease is stuck or not ready |
| `GITOPS-004` | You need to suspend and later resume reconciliation safely |
| `GITOPS-005` | Upgrading or rolling back Flux itself |
| `GITOPS-006` | Validating a branch against the live cluster |

### Security and access — `runbooks/cluster/security-access.md`

| ID | Use when |
| --- | --- |
| `SEC-001` | A credential leaked and must be rotated |
| `SEC-002` | A node is suspected compromised |
| `SEC-003` | A TLS private key may be compromised |

### Upgrades and change — `runbooks/cluster/change-management.md`

| ID | Use when |
| --- | --- |
| `CHANGE-001` | Before any risky change: go/no-go checklist |
| `CHANGE-002` | After a change: validation checklist |

### Backup and compliance — `runbooks/cluster/backup-compliance.md`

| ID | Use when |
| --- | --- |
| `BACKUP-001` | Restoring a single namespace with Velero |
| `BACKUP-002` | Full-cluster restore drill or recovery |
| `BACKUP-003` | Retention, cleanup, or storage pressure on backups |

### Operations and governance — `runbooks/cluster/operations-governance.md`

| ID | Use when |
| --- | --- |
| `OPS-001` | An incident needs command structure and coordination |
| `OPS-002` | Writing a postmortem and tracking follow-ups |

## Components

### Keycloak — `runbooks/components/keycloak.md`

| ID | Use when |
| --- | --- |
| `KEYCLOAK-001` | Wiping and recreating the Keycloak database |
| `KEYCLOAK-002` | Config drift; reconciling Keycloak from Git |
| `KEYCLOAK-003` | Restoring the Keycloak DB from a CNPG backup |
| `KEYCLOAK-004` | Rotating the Keycloak admin credentials |
| `KEYCLOAK-005` | Rotating OIDC client secrets (Grafana, Kiali, OAuth2-Proxy) |
| `KEYCLOAK-006` | Keycloak Flux Kustomization incident |
| `KEYCLOAK-007` | tofu-controller failure modes |
| `KEYCLOAK-008` | CNPG health and failover checks |
| `KEYCLOAK-009` | Namespace/service DNS debugging |
| `KEYCLOAK-010` | Planned upgrade of Keycloak, operator, or DB |
| `KEYCLOAK-011` | Emergency disable of SSO dependencies |
| `KEYCLOAK-012` | Safe decommission of the stack |
| `KEYCLOAK-013` | Post-incident validation |

### Vault — `runbooks/components/vault.md`

| ID | Use when |
| --- | --- |
| `VAULT-001` | Vault outage; sealed or unreachable |
| `VAULT-002` | Token, policy, or role rotation |
| `VAULT-003` | Backup and restore |
| `VAULT-004` | Auth backend troubleshooting (Kubernetes, AppRole) |
| `VAULT-005` | Seal migration and key rotation |

### S3 storage (RustFS) — `runbooks/components/s3-storage.md`

| ID | Use when |
| --- | --- |
| `MINIO-001` | S3 service degraded or unavailable |

`MINIO-*` IDs are historical; the deployed object store is RustFS.

### Elastic and logging — `runbooks/components/elastic-logging.md`

| ID | Use when |
| --- | --- |
| `ELASTIC-001` | Elasticsearch cluster red or yellow |

### Monitoring and tracing — `runbooks/components/observability.md`

| ID | Use when |
| --- | --- |
| `OBS-001` | Prometheus target missing or scrape failing |
| `OBS-004` | Loki ingestion or retention problems |

### Service mesh and ingress — `runbooks/components/networking-ingress.md`

| ID | Use when |
| --- | --- |
| `NET-004` | CoreDNS outage or resolution failures |
| `NET-005` | Certificate issuance failing (cert-manager) |
| `NET-006` | Inspecting served certificates and chain |
| `NET-007` | Renewal monitoring and forced reissuance |
| `NET-008` | TLS secret does not match the served certificate |

## Backlog (no runbook yet)

These IDs are catalogued but not written. If a task falls into one, use the closest triage runbook and
flag the gap:

`CLUSTER-003`, `CLUSTER-013`, `SEC-004`, `SEC-005`, `CHANGE-003`, `CHANGE-004`, `AUDIT-001`,
`OPS-003`, `OPS-004`, `MINIO-002` … `MINIO-005`, `ELASTIC-002` … `ELASTIC-005`, `OBS-002`,
`OBS-003`, `OBS-005`, `KAFKA-001`, `KAFKA-002`, `MONGO-001`, `PG-001`, `NET-001` … `NET-003`.
