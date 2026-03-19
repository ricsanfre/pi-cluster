#!/bin/bash
# openwrt-deploy-tls.sh
# Deploy renewed Let's Encrypt cert to OpenWRT gateway if changed

set -euo pipefail

CERT_PATH="$HOME/.certbot/config/live/gateway.homelab.ricsanfre.com/fullchain.pem"
KEY_PATH="$HOME/.certbot/config/live/gateway.homelab.ricsanfre.com/privkey.pem"
REMOTE_HOST="gateway"
REMOTE_CERT="/etc/uhttpd.crt"
REMOTE_KEY="/etc/uhttpd.key"
REMOTE_SERVICE="/etc/init.d/uhttpd"

# Get current checksum (empty if file does not exist)
old_cert_sum=$(ssh "$REMOTE_HOST" "[ -f $REMOTE_CERT ] && sha256sum $REMOTE_CERT | awk '{print \$1}' || echo -n ''")
old_key_sum=$(ssh "$REMOTE_HOST" "[ -f $REMOTE_KEY ] && sha256sum $REMOTE_KEY | awk '{print \$1}' || echo -n ''")

echo "[INFO] Current remote cert checksum: $old_cert_sum"
echo "[INFO] Current remote key checksum: $old_key_sum"

# Get new checksum
new_cert_sum=$(sha256sum "$CERT_PATH" | awk '{print $1}')
new_key_sum=$(sha256sum "$KEY_PATH" | awk '{print $1}')

echo "[INFO] New cert checksum: $new_cert_sum"
echo "[INFO] New key checksum: $new_key_sum"

# Only deploy if changed
if [[ "$old_cert_sum" != "$new_cert_sum" ]] || [[ "$old_key_sum" != "$new_key_sum" ]]; then
  echo "[INFO] Certificate or key changed, deploying to $REMOTE_HOST..."
  scp -O "$KEY_PATH" "$REMOTE_HOST:$REMOTE_KEY"
  scp -O "$CERT_PATH" "$REMOTE_HOST:$REMOTE_CERT"
  ssh "$REMOTE_HOST" "$REMOTE_SERVICE restart"
  echo "[INFO] Deployment complete."
else
  echo "[INFO] Certificate and key unchanged. No deployment needed."
fi
