# AGENTS.md

Guidance for coding agents working in this repository. Tools that look for a
tool-specific memory file (for example `CLAUDE.md`) should use this file.

## Repository overview

Pi Kubernetes Cluster — a homelab monorepo for a hybrid ARM/x86 K3s cluster, automated with
Ansible and FluxCD. Contains host provisioning, external services (Vault/RustFS), Kubernetes
platform apps, Terraform-managed service configuration, operational runbooks, design notes, and a
Jekyll documentation site.

## Tooling

CLI versions are pinned in [`.mise.toml`](.mise.toml) (`kubectl`, `flux2`, `velero`, `istioctl`,
`helm`, `opentofu`, `cilium-cli`, Longhorn CLI). Run `mise install` to provision them; do not
duplicate version numbers in documentation.

All repository entry points are exposed by `make`. Run `make help` for the authoritative list.

## Execution rules

- Run operational commands through the Makefile, or through the Ansible runner wrapper
  (`ansible-runner/ansible-runner.sh`). **Never run host `ansible-playbook` directly.**
- The default runner mode is Docker (`docker exec` into the `ansible-runner` container). Set
  `ANSIBLE_RUNNER_MODE=local` to use the local `uv` environment instead.
- Kubernetes contexts: `picluster-prod` (lab) and `k3d-picluster` (dev). Pass `--context`
  explicitly (`kubectl` and `flux` both accept it) rather than relying on the current context.
  `make k3s-install` writes the production entry to `~/.kube/pi-cluster.yaml` and merges it into
  `~/.kube/config`, so the dev context survives a lab reinstall.
- Git and Flux are the source of truth for cluster state. Do not `kubectl edit` live resources;
  change manifests, commit, and reconcile.
- Never run destructive actions without an explicit user request (see
  [Safety constraints](#safety-constraints)).
- Never hardcode secrets, tokens, or credentials in tracked files.

## Common commands

### Setup and linting

```bash
# Build and start the Docker-based Ansible runner (one-time prerequisite)
make ansible-runner-setup

# CI-parity YAML lint (minimum PR safety check)
make lint-ci

# Local UV-based Ansible environment (alternative to the container runner)
make ansible-local-setup
make ansible-local-lint

# Verify uv.lock is in sync with pyproject.toml
make uv-lock-check
```

### Ansible operations (all via the runner container)

```bash
# Full cluster initialization:
# os-upgrade -> nodes-setup -> external-services -> configure-os-backup -> k3s-install -> k3s-bootstrap
make init

# Individual stages
make secret-files          # Create encrypted/local secret files
make os-upgrade            # Upgrade OS packages on target nodes
make external-setup        # External-services host prerequisites
make nodes-setup           # Node prerequisites
make dns-setup             # Authoritative DNS configuration
make pxe-setup             # PXE server configuration
make external-services     # Deploy/configure Vault and RustFS
make configure-os-backup   # Configure node backup jobs
make os-backup             # Trigger restic backup on all nodes
make k3s-install           # Install K3s on cluster nodes
make k3s-bootstrap         # Bootstrap FluxCD and cluster services
make k3s-bootstrap-dev     # Bootstrap using the dev overlay
make deploy-vault          # Vault workloads
make deploy-rustfs         # RustFS S3 workloads
make configure-vault       # Terraform-driven Vault configuration
make configure-minio       # Terraform-driven S3 (RustFS) configuration
make load-external-services-keys
make get-pi-status         # Raspberry Pi throttling status

# Destructive operations — never run without explicit user request
make clean                 # k3s-reset + external-services-reset
make k3s-reset             # Remove K3s from all nodes
make external-services-reset
make shutdown-k3s-worker
make shutdown-k3s-master
make shutdown-picluster
```

### Running Ansible directly (not via Make)

```bash
# Always use the runner wrapper — never run host ansible-playbook directly
./ansible-runner/ansible-runner.sh ansible-playbook --syntax-check external_services.yml
./ansible-runner/ansible-runner.sh ansible-playbook k3s_bootstrap.yml -e overlay=dev

# Local mode (bypasses Docker, uses uv)
ANSIBLE_RUNNER_MODE=local ./ansible-runner/ansible-runner.sh ansible-playbook --version
```

### Terraform validation (safe, no apply)

Four independent modules, each with its own state backend:

```bash
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/elastic  && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/keycloak && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/minio    && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/vault    && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
```

### Docs site

```bash
cd docs
bundle config set --local path 'vendor/bundle'
bundle install
bundle exec jekyll build
```

### Dev cluster (k3d)

```bash
cd dev
make create-k3d        # provision the local k3d cluster
make helm-setup        # add chart repositories
make cluster-setup     # base services via helmfile + overlays
make cluster-bootstrap # Flux entrypoints
make delete-k3d
```

## Architecture

### Layered automation flow

```
Cloud-init (OS install) -> Ansible (OS config + K3s + external services) -> FluxCD (cluster apps)
```

The cluster is designed to be fully redeployable from scratch using this chain.

### Ansible layer (`ansible/`)

- **Inventory**: `ansible/inventory.yml` defines host groups: `picluster` (all nodes), `k3s_cluster`
  (with `k3s_master` for node2-node4 and `k3s_worker` for node5 + the x86 mini PCs),
  `raspberrypi` (ARM), `x86` (mini PCs). External services (Vault, RustFS, DNS) run on `node1`.
- **Playbooks**: top-level playbooks in `ansible/*.yml` — each maps to a Makefile target. Key ones:
  `setup_picluster.yml` (node/external host config, tag-filtered), `k3s_install.yml`,
  `k3s_bootstrap.yml` (installs FluxCD and bootstraps cluster services), `external_services.yml`,
  `deploy_rustfs.yml`.
- **Roles**: custom roles in `ansible/roles/` — `basic_setup`, `dns`, `haproxy`, `k3s`, `pxe-server`.
- **Group vars**: `ansible/group_vars/all.yml` (global), `k3s_cluster.yml`, `k3s_master.yml`,
  `external.yml`, `control.yml`.
- **Python deps**: managed by `uv` via `ansible/pyproject.toml` and `ansible/uv.lock`.
- **Lint config**: `ansible/.yamllint` (extends default, 180-char line limit as warning).

### Ansible runner (`ansible-runner/`)

A Docker container providing a consistent execution environment:
- Built from `python:3.14-slim` with OpenTofu, kubectl, helm, uv, and Ansible collections/roles baked in.
- Mounts `ansible/`, `kubernetes/`, `terraform/`, SSH keys, kubeconfig, and secrets from the host.
- `ansible-runner.sh` runs commands via `docker exec` by default; `ANSIBLE_RUNNER_MODE=local` uses
  local `uv run` instead.

### Kubernetes / FluxCD layer (`kubernetes/`)

The cluster follows a **platform + apps** pattern with environment overlays:

```
kubernetes/
├── clusters/           # Flux entrypoints per environment
│   ├── prod/           # Production cluster
│   │   ├── config/     # Root GitRepository + cluster-settings ConfigMap
│   │   ├── infra/      # Platform infra Kustomizations (one per service)
│   │   └── apps/       # Workload Kustomizations
│   └── dev/            # Dev cluster (k3d-based)
├── platform/           # Shared platform services (Helm + Kustomize)
│   └── <service>/
│       ├── app/        # HelmRelease manifests
│       │   ├── base/           # Base: helm.yaml, ns.yaml, kustomization.yaml, values.yaml
│       │   ├── components/     # Reusable patch/value bundles (e.g., dns01, monitoring)
│       │   └── overlays/{dev,prod}/  # Env-specific: helm-patch.yaml, kustomization.yaml, values.yaml
│       └── config/     # Non-Helm Kubernetes resources (ConfigMaps, policies, etc.)
└── apps/               # User workload manifests (same structure as platform/)
```

**Flux reconciliation flow**: Flux watches the Git repo → `<service>-app` Kustomization creates the
namespace + HelmRelease → `<service>-config` depends on `<service>-app` and applies config resources.

**Key FluxCD patterns**:
- Environment-specific values go in `overlays/{dev,prod}/values.yaml`, never duplicate base manifests.
- Cluster-wide settings live in the `cluster-settings` ConfigMap in `clusters/<env>/config/`, consumed
  by HelmReleases via `valuesFrom`.
- Flux `Kustomization` resources in `clusters/<env>/infra/` point to
  `platform/<service>/app/overlays/<env>` with `dependsOn` chains for ordering.
- `boilerplate/` contains a `gruntwork-io/boilerplate` template for generating new FluxCD app manifests.

### Terraform layer (`terraform/`)

| Module | Purpose | Provider |
| --- | --- | --- |
| `elastic/` | Elasticsearch roles, users, ILM, templates | Elasticsearch |
| `keycloak/` | Keycloak groups, clients, users, scopes | Keycloak |
| `minio/` | S3 buckets, users, policies (RustFS backend) | MinIO |
| `vault/` | Vault secrets, policies, K8s auth roles | Vault + Kubernetes |

The modules follow a data-driven pattern: resource definitions are loaded from
`resources/*.json|*.yaml` files and fed into Terraform via `locals` + `for_each`, keeping `.tf`
files thin. Prefer editing those input files over duplicating logic in `.tf`.

### External services

Vault (secrets management) and RustFS (S3 object storage for backups) run **outside the cluster** on
`node1`, deployed via Ansible (`deploy_rustfs.yml`) and configured via Terraform (`terraform/minio/`).
RustFS replaces MinIO with an S3-compatible API; the `aminueza/minio` provider remains compatible.

### Dev cluster (`dev/`)

Local development environment using `k3d` (K3s in Docker):
- `create_cluster.sh` provisions the cluster; `dev/Makefile` wraps the workflow.
- `helmfile.yaml` bootstraps base services (Prometheus, Cilium, CoreDNS, Istio).
- Dev overlays live in `kubernetes/platform/*/app/overlays/dev/` and `kubernetes/clusters/dev/`.

### Test workloads (`test/`)

Service-specific validation: `kafka/`, `mongodb/`, `tracing/`, `velero/` — client configs and test
scripts for verifying deployed services.

### Documentation

- `runbooks/` — operational runbooks, catalogued in [`runbooks/README.md`](runbooks/README.md).
  Split by domain (`cluster/`, `components/`). Runbook IDs are stable; never renumber.
- `design/` — design notes and ADRs (`design/adr/`). These explain *why*, not *how to operate*.
- `docs/_docs/` — Jekyll pages published at <https://picluster.ricsanfre.com>.
- `docs/_posts/` — release announcements.
- `docs/_data/docs.yml` — sidebar navigation. A page missing here is not reachable in the site.
- `README.md` — repository entry point.

## Documentation conventions

When a change alters behavior, commands, architecture, or an operational procedure, update the
documentation in the same change.

### Jekyll pages (`docs/_docs/<name>.md`)

```yaml
---
title: Human Readable Title
permalink: /docs/<slug>/
description: One-sentence summary used for SEO and search.
last_modified_at: "DD-MM-YYYY"
---
```

Then register the slug under the right section in `docs/_data/docs.yml`. Conventions:
- Headings drive the on-page table of contents; keep a clean `##` / `###` hierarchy.
- Callouts use the data files: `{{site.data.alerts.note}} … {{site.data.alerts.end}}`
  (`tip`, `note`, `important`, `warning`).
- Images live in `docs/assets/img/` and are referenced as `/assets/img/<file>`.
- Build before committing: `cd docs && bundle exec jekyll build`.

### Runbooks (`runbooks/`)

Add new runbooks to the matching domain file using the template in `runbooks/README.md`, keep the
`<a id="runbook-<id>"></a>` anchor, and link the catalog entry at `runbooks/README.md`.

### Release notes (`docs/_posts/`)

New post per release: `YYYY-MM-DD-announcing-release-X.Y.md` with `layout: post`, `title`, `date`,
`author`, `description`.

## FluxCD PR branch workflow

When validating changes from a feature branch in the live cluster:

1. Create a branch `feature/<desc>` or `issue/<desc>` from `master`.
2. Edit `kubernetes/platform/flux-operator/instance/overlays/prod/values.yaml` and set
   `instance.sync.ref` to the branch.
3. Commit and push.
4. Patch the in-cluster GitRepository to the same branch and reconcile:

   ```bash
   GR_NAME="$(kubectl -n flux-system get gitrepository -o jsonpath='{range .items[?(@.spec.url=="https://github.com/ricsanfre/pi-cluster")]}{.metadata.name}{"\n"}{end}' | head -n1)"
   kubectl -n flux-system patch gitrepository "${GR_NAME}" --type merge -p '{"spec":{"ref":{"branch":"<branch>"}}}'
   flux reconcile source git "${GR_NAME}" -n flux-system
   flux reconcile kustomization flux-system -n flux-system --with-source
   ```

5. After merge, revert `instance.sync.ref` to `refs/heads/master`, push, and patch the in-cluster
   GitRepository back:

   ```bash
   kubectl -n flux-system patch gitrepository "${GR_NAME}" --type merge -p '{"spec":{"ref":{"branch":"master","name":null}}}'
   flux reconcile source git "${GR_NAME}" -n flux-system
   ```

## Discovery spikes

Use a spike when the question is "should we use X, Y or Z" rather than "add X". The `tech-spike`
skill carries the procedure.

- Frame a concrete decision, a timebox, and what evidence would settle it.
- Judge candidates against this cluster: hybrid ARM64/AMD64, 8–16 GB nodes, Longhorn, FluxCD,
  Vault/External Secrets, Keycloak, Envoy Gateway, the Prometheus/Loki/Tempo stack, RustFS backups,
  and homelab cost/power limits.
- Shortlist 2–4 candidates and score them on a stated matrix. ARM64 support and licensing are
  disqualifying, not weighted.
- A proof of concept runs in the dev cluster or a throwaway namespace — never in prod — and is torn
  down afterwards. Measure resource usage instead of trusting the project's claims.
- Record the outcome in `design/adr/NNNN-<slug>.md` (format of `design/adr/0010-*`, status
  `Proposed`) when adopting, or `design/<slug>.md` as a spike note with a verdict and a revisit
  trigger when deferring or rejecting.

## Delivering a new service

Use this checklist when adding a platform capability or a workload. The agent skill `new-service`
carries the detailed procedure; `service-testing` covers validation.

1. **Classify** — `kubernetes/platform/<service>/` for infrastructure (operators, controllers,
   storage, networking, observability); `kubernetes/apps/<group>/` for user workloads.
2. **Pin upstream** — exact chart version, OCI (`OCIRepository`) vs HTTP (`HelmRepository`), CRD
   ownership, ARM64/AMD64 image support, persistence needs.
3. **Scaffold** — copy `boilerplate/fluxcd-app-template-vars.yaml.example`, fill the variables, run
   `make -C boilerplate generate-fluxcd-app`, then move the result into place. `boilerplate/output/`
   is scratch and must not be committed.
4. **Layer** — `app/base` for chart + generic values, `app/components` for reusable bundles
   (monitoring, route, auth, istio), `app/overlays/{dev,prod}` for environment values only,
   `config/base` + `config/overlays` for non-Helm resources.
5. **Secrets** — Vault is the source. Define the secret in `terraform/vault/resources/`, then consume
   it with an `ExternalSecret` referencing the shared `vault-backend` `ClusterSecretStore`. Never
   commit a secret.
6. **SSO** — Keycloak clients/groups in `terraform/keycloak/resources/`, applied through the
   tofu-controller pattern in `kubernetes/platform/keycloak/config/base/terraform.yaml`.
7. **Observability** — ServiceMonitor/PodMonitor in `config/components/monitoring`, Grafana dashboard
   next to it, stdout logs, OTLP traces to the `otel` collector when supported.
8. **Ingress/TLS** — Envoy Gateway `HTTPRoute` with `${CLUSTER_DOMAIN}` from `cluster-settings`;
   cert-manager handles TLS; ExternalDNS publishes the hostname.
9. **Wire Flux** — add `<service>-app.yaml` (and `-config.yaml`) under
   `kubernetes/clusters/prod/{infra,apps}/`, with real `dependsOn` entries and
   `postBuild.substituteFrom` when using `${...}` variables; register it in `kustomization.yaml`.
10. **Document** — `docs/_docs/<service>.md` plus `docs/_data/docs.yml`; design note in `design/`
    when the choice is non-obvious; runbook in `runbooks/` plus catalog and runbook-map entries.
11. **Test before prod** — render both overlays, deploy to the dev cluster, run the `service-testing`
    ladder, and present the promotion checklist. Prod wiring needs an explicit request.

## Safety constraints

- **Never run** destructive actions without an explicit user request: `make clean`, `make k3s-reset`,
  `make external-services-reset`, the `shutdown-*` targets, `tofu apply`/`terraform apply`, or
  `kubectl delete` against cluster resources.
- Do not run host `ansible-playbook` directly — always use the runner wrapper.
- Treat `make lint-ci` failures in untouched pre-existing files as informational, not blockers.
- Avoid touching generated/vendor trees: `docs/vendor/`, `docs/_site/`, `docs/.bundle/`,
  `ansible/.ansible/`, `ansible/.venv/`, `ansible-runner/runner/.kube/cache/`, `**/node_modules/`.
- `scripts/` holds recovery utilities that expect a live cluster and a valid kubeconfig.
- Never commit secrets. Secret material is stored in Vault and mounted into the runner.

## Verification / definition of done

Run the narrowest check that covers the change:

| Change | Check |
| --- | --- |
| Any YAML | `make lint-ci` |
| Ansible playbook/role | `./ansible-runner/ansible-runner.sh ansible-playbook --syntax-check <playbook>.yml` |
| Terraform module | `tofu init -backend=false && tofu validate && tofu fmt -check` (inside runner) |
| Flux/Kubernetes overlay | `kubectl kustomize kubernetes/platform/<svc>/app/overlays/<env>` |
| `docs/` | `cd docs && bundle exec jekyll build` |
| Runbooks | Catalog link resolves to the new anchor |

State what you ran and what passed. If a check could not run, say why.

## Search strategy

- Start with targeted path-scoped searches: `ansible/**`, `terraform/**`, `kubernetes/**`, `dev/**`,
  `test/**`, `runbooks/**`, `design/**`, `docs/_docs/**`.
- Exclude noisy trees: `docs/vendor/`, `docs/_site/`, `docs/.bundle/`, `ansible/.ansible/`,
  `ansible/.venv/`, `node_modules/`.

## Git commit guidelines

- Never add `Co-Authored-By` to commit messages.
- Never add `🤖 Generated with …` or similar AI attributions to commits or PR bodies.
- Use conventional commit prefixes where they fit: `feat:`, `fix:`, `docs:`, `chore:`.

## Agents and skills

OpenCode project agents live in `.opencode/agents/` and skills in `.opencode/skills/`. Usage and the
extension guide are documented in [`docs/_docs/opencode-agents.md`](docs/_docs/opencode-agents.md);
the rationale is in [`design/adr/0012-opencode-sre-agent.md`](design/adr/0012-opencode-sre-agent.md).

- **`sre`** — DevOps/SRE and platform engineer for triage, service delivery/testing, technology
  spikes, Ansible stages, Terraform validation, and runbook-driven operations. Read-only by default;
  mutations require approval; destructive commands are denied.
- Skills: `cluster-triage`, `flux-change`, `change-preflight`, `tech-spike`, `new-service`,
  `service-testing`, `docs-authoring`.
