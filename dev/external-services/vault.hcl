# Dev Vault listener configuration.
#
# Vault runs with `-dev` (in-memory storage, unsealed, fixed root token from
# VAULT_DEV_ROOT_TOKEN_ID), which always opens its own plaintext listener. The
# Compose service moves it to 127.0.0.1:8299 through
# VAULT_DEV_LISTEN_ADDRESS (container-local, not reachable from the picluster
# network) so this TLS listener can own 0.0.0.0:8200.
#
# The image entrypoint loads this directory automatically and adds
# -dev-root-token-id and -dev-listen-address, so do not pass -config again.
#
# The certificate is issued by the dev CA (gen-certs.sh) with SANs for
# vault.picluster.local.test, the dev-external Service names, localhost and the
# container IP, so the laptop and the pods validate the same certificate.
api_addr = "https://vault.picluster.local.test:8200"

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = false
  tls_cert_file   = "/vault/certs/vault_cert.pem"
  tls_key_file    = "/vault/certs/vault_key.pem"
}
