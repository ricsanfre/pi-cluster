#!/bin/bash
#
# Generate a local dev CA and a RustFS server certificate.
#
# Files (gitignored):
#   certs/ca.crt, certs/ca.key
#   certs/rustfs_cert.pem, certs/rustfs_key.pem
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="$SCRIPT_DIR/certs"
mkdir -p "$CERT_DIR"

if [ -f "$CERT_DIR/ca.crt" ] && [ -f "$CERT_DIR/rustfs_cert.pem" ] && [ -f "$CERT_DIR/rustfs_key.pem" ]; then
  echo "Using existing certificates in $CERT_DIR"
  exit 0
fi

echo "Generating dev CA and RustFS certificate"

openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout "$CERT_DIR/ca.key" \
  -out "$CERT_DIR/ca.crt" \
  -subj "/CN=dev-picluster-ca" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" >/dev/null 2>&1

cat >"$CERT_DIR/rustfs-san.cnf" <<'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no

[req_distinguished_name]
CN = rustfs.dev-external.svc.cluster.local

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = rustfs
DNS.2 = rustfs.dev-external
DNS.3 = rustfs.dev-external.svc
DNS.4 = rustfs.dev-external.svc.cluster.local
DNS.5 = localhost
IP.1 = 127.0.0.1
IP.2 = 172.30.100.10
EOF

openssl req -newkey rsa:2048 -nodes \
  -keyout "$CERT_DIR/rustfs_key.pem" \
  -out "$CERT_DIR/rustfs.csr" \
  -config "$CERT_DIR/rustfs-san.cnf" >/dev/null 2>&1

openssl x509 -req -in "$CERT_DIR/rustfs.csr" \
  -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" -CAcreateserial \
  -out "$CERT_DIR/rustfs_cert.pem" -days 825 -sha256 \
  -extensions req_ext -extfile "$CERT_DIR/rustfs-san.cnf" >/dev/null 2>&1

rm -f "$CERT_DIR/rustfs.csr"

# RustFS runs as UID/GID 10001 and must be able to read its key. The
# `rustfs-perms` Compose service also chowns the mounted certs at startup;
# this best-effort chown keeps things working when run as root.
chown 10001:10001 "$CERT_DIR/rustfs_key.pem" "$CERT_DIR/rustfs_cert.pem" 2>/dev/null || true
chmod 644 "$CERT_DIR/ca.crt"
chmod 600 "$CERT_DIR/ca.key"
chmod 640 "$CERT_DIR/rustfs_key.pem" "$CERT_DIR/rustfs_cert.pem"

echo "Certificates written to $CERT_DIR"
