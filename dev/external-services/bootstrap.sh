#!/bin/bash
#
# Create the S3 buckets and the bucket-scoped Barman credentials used by the
# dev environment. Safe to re-run.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RC_IMAGE="${RC_IMAGE:-rustfs/rc:v0.1.36}"

if [ ! -f .env ]; then
  echo "ERROR: .env not found. Run ./gen-env.sh first." >&2
  exit 1
fi
# shellcheck disable=SC1091
set -a
source .env
set +a

if [ ! -f certs/ca.crt ]; then
  echo "ERROR: certs/ca.crt not found. Run ./gen-certs.sh first." >&2
  exit 1
fi

echo "Waiting for RustFS to become healthy"
for i in $(seq 1 60); do
  if curl --silent --fail --cacert certs/ca.crt https://127.0.0.1:9091/health >/dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "ERROR: RustFS did not become healthy" >&2
    exit 1
  fi
  sleep 2
done

rc() {
  docker run --rm --network picluster \
    -v "$SCRIPT_DIR/certs:/certs:ro" \
    -e RUSTFS_ACCESS_KEY \
    -e RUSTFS_SECRET_KEY \
    -e BARMAN_ACCESS_KEY \
    -e BARMAN_SECRET_KEY \
    --entrypoint /bin/sh "$RC_IMAGE" -c '
      set -e
      rc alias set dev https://rustfs:9091 "$RUSTFS_ACCESS_KEY" "$RUSTFS_SECRET_KEY" --ca-bundle /certs/ca.crt >/dev/null
      '"$*"'
    '
}

for bucket in k3s-barman k3s-loki k3s-tempo k3s-velero; do
  echo "Ensuring bucket s3://$bucket"
  rc "rc bucket create dev/$bucket --ignore-existing >/dev/null"
done

echo "Creating Barman user '$BARMAN_ACCESS_KEY'"
if rc 'rc admin user info dev "$BARMAN_ACCESS_KEY" >/dev/null 2>&1 || rc admin user add dev "$BARMAN_ACCESS_KEY" "$BARMAN_SECRET_KEY" >/dev/null'; then
  rc 'rc admin policy attach dev readwrite --user "$BARMAN_ACCESS_KEY" >/dev/null 2>&1 || true'
  echo "Barman user ready"
else
  echo "WARNING: could not create the Barman user via rc." >&2
  echo "         Use the RustFS root credentials in .env for dev-only POCs." >&2
fi

echo "Buckets: k3s-barman k3s-loki k3s-tempo k3s-velero"
