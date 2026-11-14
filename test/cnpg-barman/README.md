# Barman Cloud plugin migration rehearsal

Proof of concept for [ADR 0013](../../design/adr/0013-barman-cloud-plugin-migration.md):
move both CloudNativePG clusters from the in-tree `spec.backup.barmanObjectStore`
to the Barman Cloud plugin (`barman-cloud.cloudnative-pg.io`).

This runs in the **dev k3d cluster only**, in a throwaway `cnpg-barman`
namespace, against the dev RustFS instance. Nothing here is wired through Flux:
`poc.sh` applies and deletes the POC resources. The operator and the plugin are
Flux-managed (`cnpg` dev profile) because those are the components the
migration actually adds.

## What it proves

| Gate | Command | Pass condition |
| --- | --- | --- |
| In-tree baseline still works | `./poc.sh phase-a`, `./poc.sh marker phase-a`, `./poc.sh backup intree` | `ContinuousArchiving=True`, WAL segment advances, base backup `completed` |
| Plugin reaches RustFS with barman-cloud 3.20.1 (sidecar) | `./poc.sh phase-b`, `./poc.sh marker phase-b` | WAL segment advances after the switch, `failed_count` stops increasing |
| Pre-switch backups stay readable | `./poc.sh restore-intree` | `pg-poc-restore-intree` Ready, only the `phase-a` marker recovered |
| WAL archived after the switch is replayed | `./poc.sh restore` | `poc_marker` shows the `phase-b` row as well |
| Sidecar footprint | `./poc.sh measure` | idle ~15Mi; peak ~300-360Mi while restoring WAL |
| Rolling restart on a 2-instance cluster | `./poc.sh phase-b` | both pods recreated, primary retained or switchover logged; note the single-instance window |
| ScheduledBackup plugin syntax | `./poc.sh status` | `pg-poc-intree-daily` has `METHOD=plugin`; a scheduled backup completes |

`phase-b` keeps the same cluster name, so the manifest diff is exactly the
production change: `spec.backup` removed, `spec.plugins` added, `ObjectStore`
created, `ScheduledBackup.method` set to `plugin`.

## Prerequisites

```bash
cd dev
make dev-up            # cluster + RustFS + Flux; cert-manager and cnpg profiles on
kubectl -n databases rollout status deploy/plugin-barman-cloud
```

The `cnpg` profile installs the operator and the plugin in `databases`
(`kubernetes/clusters/dev/profiles/cnpg.yaml`). If the plugin is missing, check
`kubectl get helmrelease -n databases` and that cert-manager is Ready.

## Run order

```bash
cd test/cnpg-barman
./poc.sh secrets         # namespace + cnpg-poc-s3 + rustfs-ca (dev .env, never committed)
./poc.sh phase-a         # in-tree Cluster + ScheduledBackup
./poc.sh marker phase-a  # marker row + WAL switch + archiving check
./poc.sh backup intree   # base backup with the in-tree method
./poc.sh wal             # record pg_stat_archiver before the switch
./poc.sh phase-b         # ObjectStore + plugin switch + rolling restart
./poc.sh marker phase-b  # prove WAL archived by the sidecar
./poc.sh backup plugin   # base backup with the plugin method
./poc.sh measure         # sidecar CPU/memory per instance
./poc.sh restore         # latest backup: phase-a + phase-b markers
./poc.sh restore-intree  # targetTime before the plugin backup: phase-a only
./poc.sh status
```

`restore-intree` deletes `pg-poc-restore` first to keep the namespace inside its
memory quota; the two restore clusters are never needed at the same time.
`restore/restore-cluster-intree.yaml` carries the `targetTime` recorded during
the 2026-11-14 run; a new run must set it between its own phase A and phase B
backups.

Capture the output of `wal`, `measure`, and the rollout from `phase-b` into the
ADR's "Proof of Concept" section before teardown.

## Teardown

```bash
./poc.sh down
```

Deletes the namespace and every POC resource. The plugin Deployment, its
certificates and the `ObjectStore` CRD stay in `databases` because Flux owns
them; `cd dev && make dev-down` removes the whole dev cluster.

The dev bucket prefix `s3://k3s-barman/poc/cnpg-barman` is left in RustFS;
`make -C dev dev-services-reset` removes the RustFS data.

## Notes

- `cnpg-poc-s3` uses the dev Barman user from `dev/external-services/.env`
  (`BARMAN_ACCESS_KEY`/`BARMAN_SECRET_KEY`) and is created by the script. It is
  never committed; production keeps `postgres-keycloak-s3-secret` and
  `postgres-ecommerce-s3-secret`.
- The dev RustFS certificate is signed by the dev CA, so the `ObjectStore` uses
  `endpointCA` pointing at the `rustfs-ca` Secret. In production that field is
  only needed if the RustFS endpoint certificate is not publicly trusted.
- `ObjectStore.spec.configuration.serverName` must stay empty. The restore
  cluster passes `serverName` as a plugin parameter instead.
- The sidecar is injected as a restartable init container named
  `plugin-barman-cloud`, not as a regular container. `kubectl top pod
  --containers` and any resource reasoning must look at `initContainers`.
- Do not set a 256Mi memory limit on the sidecar: it was `OOMKilled` while
  restoring WAL on a restarted standby. The PoC uses 512Mi memory and 500m CPU
  (250m throttled the catch-up) and measured an idle footprint of ~15Mi.
- If archiving fails with an `x-amz-content-sha256` error, add the
  `AWS_REQUEST_CHECKSUM_CALCULATION` / `AWS_RESPONSE_CHECKSUM_VALIDATION`
  workaround from the plugin documentation to
  `spec.instanceSidecarConfiguration.env` and record it in the ADR.
