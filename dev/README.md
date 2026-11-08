# Dev environment (k3d)

Laptop-sized k3d environment for POCs. The full documentation is
[docs/_docs/dev.md](../docs/_docs/dev.md); this file is the short quickstart.

## Quick start

```bash
cd dev
make dev-preflight
make dev-up
make dev-status
make dev-smoke
make dev-usage
make dev-down
```

`make dev-up` creates the `picluster` Docker network, the k3d cluster, starts
RustFS, bootstraps Cilium/CoreDNS/Flux and runs the smoke test.

## Profiles

Profiles are opt-in. Add one file per profile to
`kubernetes/clusters/dev/profiles/kustomization.yaml`:

```yaml
resources:
  - cert-manager.yaml
  - cnpg.yaml
```

Available: `cert-manager`, `ingress`, `cnpg`, `secrets`, `observability`,
`logging`, `tracing`, `messaging`, `data`, `keycloak`, `velero`.

## POC

```bash
make dev-poc-new NAME=my-poc
# then add profiles/poc-my-poc.yaml to profiles/kustomization.yaml
```

## External services

```bash
make dev-services-up          # RustFS
VAULT=1 make dev-services-up  # RustFS + Vault
make dev-seed-ca             # publish the dev CA to the cluster
make dev-services-down        # keep data
make dev-services-reset       # delete data (confirmation)
```

## Layout

```text
dev/
├── Makefile
├── create_cluster.sh
├── bootstrap.sh
├── render.sh / smoke.sh / status.sh / usage.sh
├── k3d-cluster/k3d-cluster.yaml.tmpl
├── external-services/       # RustFS + optional Vault Compose stack
└── poc-template/            # Namespace + ResourceQuota + LimitRange
```

## Limitations

- Longhorn is not supported in k3d; `local-path` is used.
- Flux tracks `master`; revert any branch validation.
- Services behind the `ingress` profile are reached over HTTPS at
  `<name>.k3d.local.test`; add a wildcard for `*.k3d` pointing at
  `172.30.200.1` in your local `local.test` zone and trust the dev CA.
  RustFS and Vault keep names in the parent zone
  (`rustfs.local.test:9091`, `vault.local.test:8200`). See
  [Accessing services from the host](../docs/_docs/dev.md#accessing-services-from-the-host).
- The dev CA and credentials are local-only and gitignored.
