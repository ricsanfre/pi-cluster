
include runner/env

RUNNER=./ansible-runner.sh

.EXPORT_ALL_VARIABLES:

.PHONY: default
default: start-ansible-runner runner/.vault/vault_passphrase.gpg

.PHONY: start-ansible-runner
start-ansible-runner:
	docker-compose up --detach

runner/.vault/vault_passphrase.gpg:
	${RUNNER} scripts/generate_gpg_key.sh
	${RUNNER} scripts/generate_vault_password.sh
