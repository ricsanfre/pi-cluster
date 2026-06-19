# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

Pi Kubernetes Cluster — a homelab monorepo for a hybrid ARM/x86 K3s cluster, automated with Ansible and FluxCD. Contains host provisioning, external services (Vault/RustFS), Kubernetes platform apps, and a Jekyll docs site.

## Tool versions (managed via mise)

```
kubectl 1.35.4 | flux2 2.8.6 | velero 1.18.0 | istioctl 1.29.2 | helm 4.1.4 | cilium-cli latest
```

## Common commands

All operational commands run through the Makefile at repo root. The Makefile wraps everything through the Ansible runner container.

### Setup and linting

```bash
# Build the Docker-based ansible runner (one-time prerequisite)
make ansible-runner-setup

# CI-parity YAML lint (minimum PR safety check)
make lint-ci

# Local UV-based Ansible environment (alternative to container runner)
make ansible-local-setup
make ansible-local-lint

# Verify uv.lock is in sync with pyproject.toml
make uv-lock-check
```

### Ansible operations (all via runner container)

```bash
# Full cluster initialization (os-upgrade → nodes-setup → external-services → os-backup → k3s-install → k3s-bootstrap)
make init

# Individual stages:
make secret-files          # Create encrypted/local secret files
make os-upgrade            # Upgrade OS packages on target nodes
make nodes-setup           # Configure node prerequisites
make external-services     # Deploy/configure Vault and RustFS
make k3s-install           # Install K3s on cluster nodes
make k3s-bootstrap         # Bootstrap FluxCD and cluster services

# Bootstrap with dev overlay (instead of prod)
make k3s-bootstrap-dev

# Destructive operations — never run without explicit user request:
make clean                 # k3s-reset + external-services-reset
make k3s-reset             # Remove K3s from all nodes
make external-services-reset

# Shutdown nodes (with 1-minute delay)
make shutdown-k3s-worker
make shutdown-k3s-master
make shutdown-picluster
```

### Terraform validation (safe, no-apply)

```bash
# Run inside the ansible runner container:
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/dns && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/minio && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/vault && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/elastic && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
```

### Running ansible directly (not via Make)

```bash
# Always use the runner wrapper — never run host ansible-playbook directly
./ansible-runner/ansible-runner.sh ansible-playbook --syntax-check external_services.yml
./ansible-runner/ansible-runner.sh ansible-playbook k3s_bootstrap.yml -e overlay=dev

# Local mode (bypasses Docker, uses uv):
ANSIBLE_RUNNER_MODE=local ./ansible-runner/ansible-runner.sh ansible-playbook --version
```

### Docs site

```bash
cd docs
bundle config set --local path 'vendor/bundle'
bundle install
bundle exec jekyll build
```

## Architecture

### Layered automation flow

```
Cloud-init (OS install) → Ansible (OS config + K3s + external services) → FluxCD (cluster apps)
```

The cluster is designed to be fully redeployable from scratch using this chain.

### Ansible layer (`ansible/`)

- **Inventory**: `ansible/inventory.yml` defines host groups: `picluster` (all nodes), `k3s_master` (nodes 2-4), `k3s_worker` (nodes 5-6 + HP nodes), `raspberrypi` (ARM), `x86` (HP mini PCs). External services (Vault, RustFS, DNS) run on `node1`.
- **Playbooks**: Top-level playbooks in `ansible/*.yml` — each maps to a Makefile target. Key ones: `setup_picluster.yml` (node/external host config, tag-filtered), `k3s_install.yml`, `k3s_bootstrap.yml` (installs FluxCD and bootstraps cluster services), `external_services.yml` (Vault/RustFS deployment), `deploy_rustfs.yml` (RustFS S3 server install).
- **Roles**: Custom roles in `ansible/roles/` — `basic_setup`, `dns`, `haproxy`, `pxe-server`.
- **Group vars**: `ansible/group_vars/all.yml` (global), `k3s_cluster.yml`, `k3s_master.yml`, `external.yml`, `control.yml`.
- **Python deps**: Managed by `uv` via `ansible/pyproject.toml` and `ansible/uv.lock`. Key deps: `ansible-core==2.20.5`, `kubernetes`, `hvac` (Vault client), `certbot` + `certbot-dns-ionos`.
- **Lint config**: `ansible/.yamllint` (extends default, 180-char line limit as warning, ignores `.venv/`, roles, docs).

### Ansible runner (`ansible-runner/`)

A Docker container that provides a consistent Ansible execution environment with all tooling pre-installed:
- Built from `python:3.14-slim` with OpenTofu, kubectl, helm, uv, and ansible collections/roles baked in.
- Mounts `ansible/`, `kubernetes/`, `terraform/`, SSH keys, kubeconfig, and secrets from the host.
- The wrapper script `ansible-runner.sh` runs commands via `docker exec` by default; set `ANSIBLE_RUNNER_MODE=local` to use local `uv run` instead.

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

**Flux reconciliation flow**: Flux watches the Git repo → `<service>-app` Kustomization creates namespace + HelmRelease → `<service>-config` depends on `<service>-app` and applies config resources.

**Key FluxCD patterns**:
- Environment-specific values go in `overlays/{dev,prod}/values.yaml`, never duplicate base manifests.
- Cluster-wide settings live in a ConfigMap (`cluster-settings`) in `clusters/<env>/config/`, consumed by HelmReleases via `valuesFrom`.
- Flux `Kustomization` resources in `clusters/<env>/infra/` point to `platform/<service>/app/overlays/<env>` with `dependsOn` chains for ordering.
- The `boilerplate/` directory contains a `gruntwork-io/boilerplate` template for generating new FluxCD app manifests.

### Terraform layer (`terraform/`)

Four independent modules, each with its own state backend:

| Module | Purpose | Provider |
|--------|---------|----------|
| `dns/` | DNS records at IONOS | IONOS DNS |
| `minio/` | S3 buckets, users, policies (RustFS backend) | MinIO |
| `vault/` | Vault secrets, policies, K8s auth roles | Vault + Kubernetes |
| `elastic/` | Elasticsearch roles, users, ILM, templates | Elasticsearch |
| `keycloak/` | Keycloak groups, clients, users, scopes | Keycloak |

Vault/RustFS/Elastic/Keycloak modules follow a data-driven pattern: resource definitions are loaded from `resources/*.json|*.yaml` files and fed into Terraform via `locals` + `for_each`, keeping `.tf` files thin.

### External services

Vault (secrets management) and RustFS (S3 object storage for backups) run **outside the cluster** on `node1`, deployed via Ansible playbooks (`deploy_rustfs.yml`), configured via Terraform (`terraform/minio/`). RustFS replaces MinIO with an S3-compatible API; the existing `aminueza/minio` Terraform provider is compatible. This keeps them locally accessible without public internet exposure.

### Dev cluster (`dev/`)

Local development environment using `k3d` (K3s in Docker):
- `create_cluster.sh` provisions a k3d cluster
- `helmfile.yaml` bootstraps base services (Prometheus, Cilium, CoreDNS, Istio)
- Dev overlays in `kubernetes/platform/*/app/overlays/dev/` and `kubernetes/clusters/dev/`

### Test workloads (`test/`)

Service-specific validation: `kafka/`, `mongodb/`, `tracing/`, `velero/`. These contain client configs and test scripts for verifying deployed services.

## CI

GitHub Actions in `.github/workflows/ci.yml`: runs `yamllint .` inside `ansible/` directory on PRs and pushes to `master`.

## Safety constraints

- **Never run** destructive actions (`make clean`, `make k3s-reset`, `make external-services-reset`, `tofu apply`) without explicit user request.
- Do not run host `ansible-playbook` directly — always use the runner wrapper.
- `scripts/` directory is empty; any existing scripts expect a live cluster and valid kubeconfig.
- Treat `make lint-ci` failures on pre-existing issues in untouched files as informational, not blockers.
- Avoid touching generated/vendor trees: `docs/vendor/`, `docs/_site/`, `docs/.bundle/`, `ansible/.ansible/`, `ansible-runner/runner/.kube/cache/`.

## FluxCD PR branch workflow

When validating changes from a feature branch in the live cluster:

1. Create branch `feature/<desc>` or `issue/<desc>` from master
2. Edit `kubernetes/platform/flux-operator/instance/overlays/prod/values.yaml` → set `instance.sync.ref` to the branch
3. Commit and push
4. Patch in-cluster GitRepository to the same branch and reconcile:
   ```bash
   GR_NAME="$(kubectl -n flux-system get gitrepository -o jsonpath='{range .items[?(@.spec.url=="https://github.com/ricsanfre/pi-cluster")]}{.metadata.name}{"\n"}{end}' | head -n1)"
   kubectl -n flux-system patch gitrepository "${GR_NAME}" --type merge -p '{"spec":{"ref":{"branch":"<branch>"}}}'
   flux reconcile source git "${GR_NAME}" -n flux-system
   flux reconcile kustomization flux-system -n flux-system --with-source
   ```
5. After merge: revert `instance.sync.ref` to `refs/heads/master`, push, and patch in-cluster GitRepository back to `master`

## Search strategy

- Start with targeted path-scoped searches: `ansible/**`, `terraform/**`, `kubernetes/**`, `dev/**`, `test/**`
- Exclude noisy trees: `docs/vendor/`, `docs/_site/`, `docs/.bundle/`, `ansible/.ansible/`, `ansible/.venv/`

## Git Commit Guidelines
- Never add Co-Authored-By to commit messages