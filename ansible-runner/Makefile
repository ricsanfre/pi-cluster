include runner/env

RUNNER=./ansible-runner.sh

.PHONY: default
default: start-ansible-runner runner/.ssh/id_ed25519 runner/.vault/vault_passphrase.gpg

.PHONY: start-ansible-runner
start-ansible-runner:
	docker compose up --detach

runner/.ssh/id_ed25519:
	${RUNNER} ssh-keygen -t ed25519 -P '' -f /home/runner/.ssh/id_ed25519

runner/.vault/vault_passphrase.gpg:
	${RUNNER} /home/runner/scripts/generate_gpg_key.sh
	${RUNNER} /home/runner/scripts/generate_vault_password.sh
