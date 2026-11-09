# Dev external services

Development-only S3 and secrets backends for the k3d environment. They run in
Docker on the `picluster` network, outside the cluster, to mirror the prod
topology.

| Service | Address | Notes |
| --- | --- | --- |
| RustFS S3 | `https://rustfs.picluster.local.test:9091` (host and pods, via DNS) / `https://127.0.0.1:9091` (host, published port) | TLS with the local dev CA |
| RustFS console | `https://rustfs.picluster.local.test:9092` | optional |
| Vault | `https://vault.picluster.local.test:8200` (host and pods, via DNS) / `https://127.0.0.1:8200` (host, published port) | dev mode, TLS with the local dev CA, root token in `.env`, opt-in profile |

The `*.picluster.local.test` names come from the laptop resolver: `rustfs` and
`vault` are explicit A records in that zone pointing at the fixed container IPs
(`172.30.100.10`, `172.30.100.11`). See
[the dev docs](../../docs/_docs/dev.md#accessing-services-from-the-host) for the
zone file.

## First start

```bash
cd dev/external-services
./gen-env.sh        # creates .env with random local credentials (gitignored)
./gen-certs.sh      # creates certs/ (gitignored)
docker compose --env-file .env up -d
./bootstrap.sh      # creates the dev buckets and the Barman user (uses rustfs/rc)
```

Or from `dev/`:

```bash
make dev-services-up
```

Start Vault too:

```bash
VAULT=1 make dev-services-up
```

## Stop / reset

```bash
make dev-services-down   # stop containers, keep data
make dev-services-reset  # stop and delete data (asks for confirmation)
```

## Files

| Path | Committed | Purpose |
| --- | --- | --- |
| `compose.yaml` | yes | RustFS + optional Vault |
| `.env.example` | yes | variable names, no secrets |
| `gen-env.sh` | yes | generates `.env` |
| `gen-certs.sh` | yes | generates the dev CA and the RustFS/Vault server certificates |
| `bootstrap.sh` | yes | creates buckets and the Barman user |
| `.env`, `certs/`, `data/` | no | local credentials, certificates, data |

The CA is generated once by `gen-certs.sh` and reused: it is the dev root of
trust. It signs the RustFS server certificate and is imported into the k3d
cluster by `make dev-seed-ca` (Secret `dev-root-ca`, used by
`ClusterIssuer/ca-issuer`) and into the namespaces whose workloads verify it
(`rustfs-ca`, `vault-ca`). Deleting `certs/` rotates it and invalidates every
certificate it signed;
re-run `gen-certs.sh` and `make dev-seed-ca` afterwards.
