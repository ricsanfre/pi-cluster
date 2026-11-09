#!/bin/bash
#
# Create the dev root CA and the server certificates for the external services
# (RustFS and Vault).
#
# The CA is created once and then reused: it is the dev trust anchor, and
# `make dev-seed-ca` imports it into the cluster for cert-manager. Server
# certificates are re-issued only when they are missing or do not cover the
# SANs below.
#
# Files (gitignored):
#   certs/ca.crt, certs/ca.key
#   certs/rustfs_cert.pem, certs/rustfs_key.pem
#   certs/vault_cert.pem, certs/vault_key.pem
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="$SCRIPT_DIR/certs"
mkdir -p "$CERT_DIR"

# Older installs had the compose stack chown the whole certs directory to the
# RustFS UID, which leaves ca.key unreadable here.
if [ -f "$CERT_DIR/ca.key" ] && [ ! -r "$CERT_DIR/ca.key" ]; then
  echo "ERROR: cannot read $CERT_DIR/ca.key (owner UID $(stat -c %u "$CERT_DIR/ca.key"))" >&2
  echo "       Restore ownership with: sudo chown -R $(id -u):$(id -g) $CERT_DIR" >&2
  exit 1
fi

# issue_server_cert <name> <common-name/check-host> <alt-names block>
#
# Re-issues the certificate when it is missing or does not cover the check
# host (for example after adding a SAN). -checkhost exits non-zero when the
# certificate does not match, which is the signal to re-issue.
issue_server_cert() {
  local name="$1" host="$2" alt_names="$3"
  local crt="$CERT_DIR/${name}_cert.pem"
  local key="$CERT_DIR/${name}_key.pem"
  local cnf="$CERT_DIR/${name}-san.cnf"
  local csr="$CERT_DIR/${name}.csr"

  if [ -f "$crt" ] && [ -f "$key" ] \
    && openssl x509 -in "$crt" -noout -checkhost "$host" >/dev/null 2>&1; then
    echo "Using existing $name certificate in $CERT_DIR"
    return 0
  fi

  echo "Generating $name server certificate"

  cat >"$cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[req_distinguished_name]
CN = $host

[req_ext]
subjectAltName = @alt_names

[alt_names]
$alt_names
EOF

  openssl req -newkey rsa:2048 -nodes \
    -keyout "$key" \
    -out "$csr" \
    -config "$cnf" >/dev/null 2>&1

  openssl x509 -req -in "$csr" \
    -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" -CAcreateserial \
    -out "$crt" -days 825 -sha256 \
    -extensions req_ext -extfile "$cnf" >/dev/null 2>&1

  rm -f "$csr"
}

# The CA is created once and then reused. It is the dev root of trust for both
# the external services and the cluster's cert-manager issuer (`make
# dev-seed-ca` imports it as the `dev-root-ca` Secret), so regenerating it
# invalidates every certificate signed by it: the RustFS and Vault server
# certificates *and* the ones cert-manager has issued.
if [ -f "$CERT_DIR/ca.crt" ] && [ -f "$CERT_DIR/ca.key" ]; then
  echo "Using existing dev CA in $CERT_DIR"
else
  echo "Generating dev CA"

  openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
    -keyout "$CERT_DIR/ca.key" \
    -out "$CERT_DIR/ca.crt" \
    -subj "/CN=dev-picluster-ca" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" >/dev/null 2>&1
fi

issue_server_cert rustfs rustfs.dev-external.svc.cluster.local \
  "DNS.1 = rustfs
DNS.2 = rustfs.dev-external
DNS.3 = rustfs.dev-external.svc
DNS.4 = rustfs.dev-external.svc.cluster.local
DNS.5 = localhost
DNS.6 = rustfs.picluster.local.test
IP.1 = 127.0.0.1
IP.2 = 172.30.100.10"

issue_server_cert vault vault.dev-external.svc.cluster.local \
  "DNS.1 = vault
DNS.2 = vault.dev-external
DNS.3 = vault.dev-external.svc
DNS.4 = vault.dev-external.svc.cluster.local
DNS.5 = localhost
DNS.6 = vault.picluster.local.test
IP.1 = 127.0.0.1
IP.2 = 172.30.100.11"

# RustFS runs as UID/GID 10001 and must be able to read its key. The
# `rustfs-perms` Compose service also chowns its keypair at startup; this
# best-effort chown keeps things working when run as root. Vault drops to the
# image's `vault` user (UID 100) after start, so its keypair is world-readable:
# it protects an in-memory dev server whose root token lives in .env anyway.
chown 10001:10001 "$CERT_DIR/rustfs_key.pem" "$CERT_DIR/rustfs_cert.pem" 2>/dev/null || true
chmod 644 "$CERT_DIR/ca.crt" "$CERT_DIR/vault_cert.pem" "$CERT_DIR/vault_key.pem"
chmod 600 "$CERT_DIR/ca.key"
# `rustfs-perms` has already given the RustFS keypair to UID 10001, so after the
# first `dev-services-up` the host user cannot chmod it any more (EPERM, which
# aborted this script). Compose guarantees its modes; only fix files we own.
if [ -O "$CERT_DIR/rustfs_cert.pem" ]; then chmod 644 "$CERT_DIR/rustfs_cert.pem"; fi
if [ -O "$CERT_DIR/rustfs_key.pem" ]; then chmod 640 "$CERT_DIR/rustfs_key.pem"; fi

echo "Certificates written to $CERT_DIR"
