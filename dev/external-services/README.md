# Dev external services

Development-only S3 and secrets backends for the k3d environment. They run in
Docker on the `picluster` network, outside the cluster, to mirror the prod
topology.

| Service | Address | Notes |
| --- | --- | --- |
| RustFS S3 | `https://127.0.0.1:9091` (host) / `https://rustfs.dev-external.svc.cluster.local:9091` (cluster) | TLS with the local dev CA |
| RustFS console | `https://127.0.0.1:9092` | optional |
| Vault | `http://127.0.0.1:8200` (opt-in profile) | dev mode, root token in `.env` |

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
| `gen-certs.sh` | yes | generates the dev CA and RustFS cert |
| `bootstrap.sh` | yes | creates buckets and the Barman user |
| `.env`, `certs/`, `data/` | no | local credentials, certificates, data |

The CA certificate (`certs/ca.crt`) is public and is copied into POC
namespaces as the `rustfs-ca` Secret when needed.
