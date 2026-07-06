# Internal Services Configuration — Helm + Tofu Controller

**Date:** July 2026
**Status:** Implemented as of release v1.12
**Applies to:** Elastic Stack, Keycloak

---

## Design Rationale

Elastic Stack and Keycloak run inside the Kubernetes cluster, deployed via FluxCD HelmReleases. Their day-2 configuration (users, roles, clients, realms, ILM policies, index templates) is managed declaratively through Terraform, executed by FluxCD's Tofu Controller as part of the GitOps reconciliation loop.

### Before: CLI-based configuration

```
Manual / CLI tools
──────────────────
Elasticsearch REST API     ← curl scripts, Kibana dev tools
Keycloak Admin Console     ← keycloak-config-cli YAML files
```

Configuration changes required manual intervention outside the GitOps workflow. No drift detection, no audit trail, no rollback capability.

### After: Tofu Controller-driven Terraform

```
FluxCD GitOps Loop
──────────────────
Git Repository (pi-cluster)
  │
  ▼
Flux Source Controller (GitRepository)
  │
  ▼
Tofu Controller (Terraform CRD)
  │  watches ./terraform/elastic or ./terraform/keycloak
  │  reconcile interval: 30m
  │  approvePlan: auto
  ▼
Terraform Runner Pod
  │  tofu init → plan → apply
  │  authenticates to Vault (K8s auth, tf-runner role)
  ▼
Target Service
  Elasticsearch / Kibana  ← roles, users, ILM, templates, dataviews
  Keycloak                ← realm, clients, users, groups, scopes
```

Every configuration change goes through Git → PR review → merge → Tofu Controller detects drift → auto-apply. State is tracked in a Kubernetes Secret (`tf-config-elastic-output` / `tf-config-keycloak-output`).

---

## Service Details

### Elastic Stack

**Install:** ECK Operator via FluxCD HelmRelease (`kubernetes/platform/eck-operator/`)

**Configure:** `Terraform` CRD at `kubernetes/platform/elastic-stack/config/base/terraform.yaml`

```
apiVersion: infra.contrib.fluxcd.io/v1alpha2
kind: Terraform
metadata:
  name: config-elastic
spec:
  interval: 30m
  approvePlan: auto
  path: ./terraform/elastic
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  vars:
    - name: vault_address
      value: "https://vault.${CLUSTER_DOMAIN}:8200"
    - name: vault_kubernetes_auth_role
      value: "tf-runner"
    - name: elasticsearch_endpoint
      value: "http://efk-es-http.elastic.svc:9200"
```

**What Terraform manages:**
- Elasticsearch roles (prometheus, fluentd, otel, grafana)
- Elasticsearch users
- ILM policies (lifecycle management for log indices)
- Index templates and component templates
- Kibana dataviews

**Vault integration:** The Tofu Controller runner pod authenticates to Vault using Kubernetes auth with the `tf-runner` role. The Elasticsearch admin password is fetched from `secret/elastic` at plan/apply time.

### Keycloak

**Install:** Keycloak Operator via FluxCD HelmRelease (`kubernetes/platform/keycloak/`)

**Configure:** `Terraform` CRD at `kubernetes/platform/keycloak/config/base/terraform.yaml`

```
apiVersion: infra.contrib.fluxcd.io/v1alpha2
kind: Terraform
metadata:
  name: config-keycloak
spec:
  interval: 30m
  approvePlan: auto
  path: ./terraform/keycloak
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  vars:
    - name: vault_address
      value: "https://vault.${CLUSTER_DOMAIN}:8200"
    - name: vault_kubernetes_auth_role
      value: "tf-runner"
    - name: keycloak_url
      value: "http://keycloak-service.keycloak.svc:8080"
```

**What Terraform manages:**
- Realm configuration (replacing `keycloak-config-cli`)
- OIDC clients (Grafana, Kafdrop, e-commerce)
- Users and groups
- Client roles and scopes
- Identity provider settings

**Vault integration:** Same pattern as Elastic — the Tofu Controller pod authenticates via Kubernetes auth. Keycloak client secrets and user credentials are stored in Vault under `secret/keycloak` and `secret/e-commerce`.

---

## Data-Driven Resource Pattern

Both modules follow the same pattern as Vault and MinIO: resource definitions in structured JSON files, thin `.tf` files with `for_each`:

```
terraform/
├── elastic/resources/
│   ├── roles/prometheus_role.json
│   ├── roles/fluentd_role.json
│   ├── roles/otel_role.json
│   ├── roles/grafana_role.json
│   └── users/
└── keycloak/resources/
    ├── realm/realm.json
    ├── clients/kafdrop.json
    ├── groups/admin.json
    ├── scopes/roles-id-token.json
    └── client_roles/grafana.json
```

Adding a new user, client, or role is a matter of adding a JSON file and pushing to Git — Tofu Controller picks up the change within 30 minutes and auto-applies.

---

## Tofu Controller Setup

The Tofu Controller itself is deployed as a FluxCD HelmRelease at `kubernetes/platform/flux-operator/tofu-controller/`. It is configured with cross-namespace references enabled, allowing Terraform CRDs in service namespaces to reference the GitRepository source in `flux-system`.

```yaml
# Key helm values
runner:
  grpc:
    maxMessageSize: 20  # Accommodates larger Terraform outputs
```

---

## Comparison: External vs Internal Services

| Dimension | External (Vault, RustFS) | Internal (Elastic, Keycloak) |
|-----------|--------------------------|------------------------------|
| **Where they run** | Bare-metal on `node1` | Kubernetes pods |
| **Installer** | Ansible playbooks | FluxCD HelmReleases |
| **Terraform runner** | Ansible triggers tofu in runner container | Tofu Controller spawns runner pods in K8s |
| **Trigger** | Manual or playbook-driven | GitOps (Git → Flux → Tofu Controller) |
| **Reconcile interval** | On-demand | Every 30 minutes (auto) |
| **Vault auth** | Token from `~/.secrets/vault.env` | Kubernetes auth (`tf-runner` role) |
| **State storage** | Tofu state in backend | Tofu state in backend + output in K8s Secret |

---

## Related Documents

- [External Services Terraform Configuration](external-services-terraform-configuration.md) — Ansible + Terraform pattern for Vault and RustFS
- [HashiCorp Vault Migration Design](hashicorp-vault-migration.md) — Vault secrets management
- [FluxCD Tofu Controller](/docs/fluxcd/) — Tofu Controller usage in the cluster
