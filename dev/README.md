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
RustFS/Vault, bootstraps Cilium/CoreDNS/Flux, publishes the dev CA and runs the
smoke test. The CA seed does not depend on any profile: `seed-ca.sh` creates the
`cert-manager` and `external-secrets` namespaces itself, so enabling
`cert-manager`/`ingress` later only needs a Flux reconcile.

## Lifecycle

| Level | Command | Removes |
| --- | --- | --- |
| stop, keep everything | `make dev-down` | k3d cluster only; services stopped, data/certs kept |
| recreate | `make dev-recreate` | cluster, then `dev-up` again (data/certs kept) |
| destroy | `make dev-destroy` | cluster, RustFS data, certs, `.env`, unused `picluster` network |

`dev-down` is the everyday target. `dev-destroy` deletes the dev CA and the
credentials, so the next `dev-up` generates new ones; it also leaves any
in-cluster copy of the old CA stale — `make dev-services-reset` alone warns
about this.

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
make dev-seed-ca             # re-publish the dev CA (idempotent)
make dev-services-down        # keep data
make dev-services-reset       # delete data (confirmation)
```

`dev-services-up` already seeds the CA; `dev-seed-ca` is for re-running it after
enabling a profile that added consumer namespaces (`velero`, `loki`, `tempo`).

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
- Everything the dev environment publishes is under
  `picluster.local.test`: the `ingress` profile serves `<name>.picluster.local.test`
  through Envoy Gateway (`172.30.200.1`), and RustFS/Vault answer on
  `rustfs.picluster.local.test:9091` / `vault.picluster.local.test:8200`
  (`172.30.100.10` / `.11`). Declare the zone in your laptop resolver and trust
  the dev CA. See
  [Accessing services from the host](../docs/_docs/dev.md#accessing-services-from-the-host).
- The dev CA and credentials are local-only and gitignored.
