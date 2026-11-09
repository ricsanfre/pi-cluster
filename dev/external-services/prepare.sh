#!/bin/bash
#
# Prepare the host-side artifacts the dev cluster depends on: random
# credentials and the dev CA with its server certificates.
#
# This is host-only and does not touch the cluster. It runs before `dev-up`
# seeds the CA (`make dev-seed-ca`) and before Flux bootstraps.
#
# Safe to re-run. Existing credentials, the CA and certificates whose SANs
# still match are reused.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

./gen-env.sh
./gen-certs.sh
