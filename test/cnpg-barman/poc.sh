#!/bin/bash
#
# Barman Cloud plugin migration rehearsal (design/adr/0013).
#
# Dev k3d cluster only. The CloudNativePG operator and the plugin are deployed
# by the Flux `cnpg` profile; this script drives only the POC resources in the
# `cnpg-barman` namespace, in gate order.
#
# Usage: ./poc.sh <command>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEV_ENV="$ROOT/dev/external-services/.env"
DEV_CERTS="$ROOT/dev/external-services/certs"

KUBE_CONTEXT="${KUBE_CONTEXT:-k3d-picluster}"
NS="${NS:-cnpg-barman}"
CLUSTER="pg-poc"
RESTORE_CLUSTER="pg-poc-restore"
PLUGIN="barman-cloud.cloudnative-pg.io"
S3_SECRET="cnpg-poc-s3"

die() { echo "ERROR: $*" >&2; exit 1; }

require_dev() {
  command -v kubectl >/dev/null || die "kubectl not found"
  local ctx
  ctx="$(kubectl config current-context 2>/dev/null || true)"
  [ "$ctx" = "$KUBE_CONTEXT" ] || die "kubectl context is '${ctx:-<none>}', expected '$KUBE_CONTEXT'"
  kubectl get --raw /readyz >/dev/null 2>&1 || die "cluster '$KUBE_CONTEXT' is not reachable"
}

require_operator() {
  kubectl -n databases get deploy plugin-barman-cloud >/dev/null 2>&1 \
    || die "plugin-barman-cloud not found in 'databases'; enable the cnpg Flux profile first"
  kubectl -n databases rollout status deploy/plugin-barman-cloud --timeout=120s
}

require_poc_secrets() {
  kubectl -n "$NS" get secret "$S3_SECRET" >/dev/null 2>&1 \
    || die "Secret/$NS/$S3_SECRET missing; run '$0 secrets' first"
  kubectl -n "$NS" get secret rustfs-ca >/dev/null 2>&1 \
    || die "Secret/$NS/rustfs-ca missing; run '$0 secrets' first"
}

require_dev_env() {
  [ -f "$DEV_ENV" ] || die "$DEV_ENV missing; run 'make -C dev dev-prepare'"
  [ -f "$DEV_CERTS/ca.crt" ] || die "$DEV_CERTS/ca.crt missing; run 'make -C dev dev-prepare'"
}

apply() { kubectl apply -f "$1"; }

wait_cluster() {
  local name="$1" timeout="${2:-900s}"
  echo "Waiting for cluster/$name to be Ready (up to $timeout)"
  kubectl -n "$NS" wait --for=condition=Ready "cluster/$name" --timeout="$timeout"
}

primary() {
  kubectl -n "$NS" get cluster "$CLUSTER" -o jsonpath='{.status.currentPrimary}'
}

# psql into the current primary of pg-poc.
psql_poc() {
  local p
  p="$(primary)"
  [ -n "$p" ] || die "cluster/$CLUSTER has no current primary yet"
  kubectl -n "$NS" exec "$p" -c postgres -- psql -U postgres -d app -tAc "$1"
}

wait_backup() {
  local name="$1" phase=""
  echo "Waiting for backup/$name"
  for _ in $(seq 1 120); do
    phase="$(kubectl -n "$NS" get backup "$name" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "$phase" in
      completed) echo "backup/$name completed"; return 0 ;;
      failed) die "backup/$name failed; see 'kubectl -n $NS describe backup/$name'" ;;
    esac
    sleep 5
  done
  die "backup/$name did not complete (last phase: ${phase:-unknown})"
}

trigger_backup() {
  local method="$1" prefix manifest name
  case "$method" in
    intree)
      prefix="poc-intree"
      manifest=$(cat <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  generateName: ${prefix}-
  namespace: ${NS}
spec:
  cluster:
    name: ${CLUSTER}
  method: barmanObjectStore
EOF
)
      ;;
    plugin)
      prefix="poc-plugin"
      manifest=$(cat <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  generateName: ${prefix}-
  namespace: ${NS}
spec:
  cluster:
    name: ${CLUSTER}
  method: plugin
  pluginConfiguration:
    name: ${PLUGIN}
EOF
)
      ;;
    *) die "unknown backup method '$method' (intree|plugin)" ;;
  esac

  name="$(printf '%s' "$manifest" | kubectl create -f - -o name)"
  name="${name#backup.postgresql.cnpg.io/}"
  echo "Created backup/$name method=$method"
  wait_backup "$name"
  kubectl -n "$NS" get backup "$name"
}

cmd_secrets() {
  require_dev
  require_dev_env
  # shellcheck disable=SC1091
  set -a; source "$DEV_ENV"; set +a
  [ -n "${BARMAN_ACCESS_KEY:-}" ] || die "BARMAN_ACCESS_KEY missing from $DEV_ENV"
  [ -n "${BARMAN_SECRET_KEY:-}" ] || die "BARMAN_SECRET_KEY missing from $DEV_ENV"

  apply "$SCRIPT_DIR/00-namespace.yaml"

  # Dev-only credentials: the Barman user created by dev/external-services/
  # bootstrap.sh. Never committed.
  kubectl -n "$NS" create secret generic "$S3_SECRET" \
    --from-literal=AWS_ACCESS_KEY_ID="$BARMAN_ACCESS_KEY" \
    --from-literal=AWS_SECRET_ACCESS_KEY="$BARMAN_SECRET_KEY" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "Secret/$NS/$S3_SECRET ready"

  # RustFS is served over TLS with the dev CA.
  kubectl -n "$NS" create secret generic rustfs-ca \
    --from-file=ca.crt="$DEV_CERTS/ca.crt" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "Secret/$NS/rustfs-ca ready"
}

cmd_phase_a() {
  require_dev
  require_operator
  require_poc_secrets
  apply "$SCRIPT_DIR/00-namespace.yaml"
  apply "$SCRIPT_DIR/phase-a/cluster.yaml"
  apply "$SCRIPT_DIR/phase-a/scheduledbackup.yaml"
  wait_cluster "$CLUSTER"
  cmd_status
}

cmd_phase_b() {
  require_dev
  require_operator
  require_poc_secrets
  apply "$SCRIPT_DIR/phase-b/objectstore.yaml"
  echo
  echo "Current primary before the switch: $(primary)"
  kubectl -n "$NS" get pods -l "cnpg.io/cluster=$CLUSTER" \
    -o custom-columns=NAME:.metadata.name,START:.status.startTime
  echo
  echo "Applying the plugin switch (Cluster spec + ScheduledBackup)"
  apply "$SCRIPT_DIR/phase-b/cluster.yaml"
  apply "$SCRIPT_DIR/phase-b/scheduledbackup.yaml"
  echo
  echo "Watch the rollout with: kubectl -n $NS get pods -l cnpg.io/cluster=$CLUSTER -w"
  wait_cluster "$CLUSTER" 1200s
  echo
  echo "Primary after the switch: $(primary)"
  kubectl -n "$NS" get pods -l "cnpg.io/cluster=$CLUSTER" \
    -o custom-columns=NAME:.metadata.name,START:.status.startTime,RESTARTS:.status.containerStatuses[0].restartCount
  cmd_status
}

cmd_marker() {
  local label="${1:-}"
  [ -n "$label" ] || die "usage: $0 marker <label>"
  require_dev

  psql_poc "CREATE TABLE IF NOT EXISTS poc_marker(id bigserial primary key, label text, inserted_at timestamptz default now());"
  psql_poc "INSERT INTO poc_marker(label) VALUES ('$label');"

  local before after failed
  before="$(psql_poc "SELECT coalesce(last_archived_wal, '') FROM pg_stat_archiver;")"
  psql_poc "SELECT pg_switch_wal();" >/dev/null
  echo "Inserted marker '$label'; waiting for WAL archiving to advance (was '${before:-none}')"
  for _ in $(seq 1 60); do
    after="$(psql_poc "SELECT coalesce(last_archived_wal, '') FROM pg_stat_archiver;")"
    [ -n "$after" ] && [ "$after" != "$before" ] && break
    sleep 2
  done
  failed="$(psql_poc 'SELECT failed_count FROM pg_stat_archiver;')"
  [ -n "$after" ] && [ "$after" != "$before" ] \
    || die "archiver did not advance (failed_count=$failed); check ContinuousArchiving"
  echo "Archived WAL segment: $after (failed_count=$failed)"
}

cmd_wal() {
  require_dev
  echo "== pg_stat_archiver (primary: $(primary)) =="
  psql_poc "SELECT archived_count, failed_count, last_archived_wal, last_archived_time, last_failed_wal FROM pg_stat_archiver;"
  echo
  echo "== ObjectStore recovery window =="
  kubectl -n "$NS" get objectstore pg-poc-store -o yaml 2>/dev/null \
    | sed -n '/serverRecoveryWindow:/,$p' || echo "not created yet"
}

cmd_restore() {
  require_dev
  require_poc_secrets
  apply "$SCRIPT_DIR/restore/restore-cluster.yaml"
  wait_cluster "$RESTORE_CLUSTER" 1200s
  echo
  echo "== Markers recovered into $RESTORE_CLUSTER (latest backup) =="
  print_markers "$RESTORE_CLUSTER"
}

# Point-in-time restore that forces the pre-switch in-tree base backup: the
# target time falls between the phase A backup and the phase B plugin backup.
cmd_restore_intree() {
  require_dev
  require_poc_secrets
  # Keep the namespace inside its memory quota: one restore cluster at a time.
  kubectl -n "$NS" delete cluster "$RESTORE_CLUSTER" --ignore-not-found --wait=true --timeout=300s
  apply "$SCRIPT_DIR/restore/restore-cluster-intree.yaml"
  wait_cluster "pg-poc-restore-intree" 1200s
  echo
  echo "== Markers recovered into pg-poc-restore-intree (in-tree backup + plugin WAL) =="
  print_markers "pg-poc-restore-intree"
}

print_markers() {
  local cluster="$1" p
  p="$(kubectl -n "$NS" get cluster "$cluster" -o jsonpath='{.status.currentPrimary}')"
  kubectl -n "$NS" exec "$p" -c postgres -- \
    psql -U postgres -d app -tAc "SELECT label, inserted_at FROM poc_marker ORDER BY id;"
}

cmd_measure() {
  require_dev
  echo "== Sidecar and instance containers (usage) =="
  kubectl -n "$NS" top pods --containers | awk 'NR==1 || /pg-poc/'
  echo
  echo "== Declared resources =="
  kubectl -n "$NS" get pods -l "cnpg.io/cluster=$CLUSTER" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .spec.containers[*]}  {.name}: {.resources}{"\n"}{end}{end}'
}

cmd_status() {
  require_dev
  echo "== Clusters =="
  kubectl -n "$NS" get clusters.postgresql.cnpg.io 2>/dev/null \
    -o custom-columns=NAME:.metadata.name,INSTANCES:.status.instances,READY:.status.readyInstances,PRIMARY:.status.currentPrimary,AGE:.metadata.creationTimestamp || true
  echo
  echo "== Continuous archiving =="
  kubectl -n "$NS" get cluster "$CLUSTER" -o jsonpath='{range .status.conditions[?(@.type=="ContinuousArchiving")]}{.type}={.status} {.message}{"\n"}{end}' 2>/dev/null || true
  echo
  echo "== Backups =="
  kubectl -n "$NS" get backups.postgresql.cnpg.io 2>/dev/null \
    -o custom-columns=NAME:.metadata.name,METHOD:.spec.method,PHASE:.status.phase,ERROR:.status.error || true
  echo
  echo "== ScheduledBackups =="
  kubectl -n "$NS" get scheduledbackups.postgresql.cnpg.io 2>/dev/null \
    -o custom-columns=NAME:.metadata.name,METHOD:.spec.method,SUSPEND:.spec.suspend || true
  echo
  echo "== Pods =="
  kubectl -n "$NS" get pods -o wide || true
}

cmd_down() {
  require_dev
  echo "Deleting POC resources in namespace/$NS (dev only)"
  kubectl -n "$NS" delete cluster --all --wait=true --timeout=300s 2>/dev/null || true
  kubectl -n "$NS" delete scheduledbackup,backup,objectstore --all --wait=true --timeout=120s 2>/dev/null || true
  kubectl delete namespace "$NS" --ignore-not-found --wait=false
  echo "Namespace deletion requested. The plugin and its ObjectStore CRD stay"
  echo "installed (Flux-managed in 'databases')."
}

usage() {
  cat <<EOF
Barman Cloud plugin migration rehearsal (design/adr/0013).
Dev k3d cluster only; drives the POC resources in namespace/$NS.

Commands:
  secrets       Create namespace and dev-only S3/CA secrets
  phase-a       Apply the in-tree baseline cluster and wait for Ready
  marker LABEL  Insert a marker row and wait for WAL archiving to advance
  backup METHOD Trigger a base backup (METHOD: intree|plugin) and wait
  phase-b       Apply the ObjectStore and switch the cluster to the plugin
  wal           Print pg_stat_archiver and the ObjectStore recovery window
  restore       Create pg-poc-restore from the object store and print markers
  restore-intree  Restore before the plugin backup: proves the in-tree base backup is readable
  measure       Show per-container CPU/memory of the instance pods
  status        Clusters, archiving condition, backups, pods
  down          Delete every POC resource in namespace/$NS
EOF
}

case "${1:-}" in
  secrets) cmd_secrets ;;
  phase-a) cmd_phase_a ;;
  marker) shift; cmd_marker "$@" ;;
  backup) shift; trigger_backup "${1:-}" ;;
  phase-b) cmd_phase_b ;;
  wal) cmd_wal ;;
  restore) cmd_restore ;;
  restore-intree) cmd_restore_intree ;;
  measure) cmd_measure ;;
  status) cmd_status ;;
  down) cmd_down ;;
  *) usage; exit 1 ;;
esac
