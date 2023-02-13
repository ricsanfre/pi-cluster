
include runner/env

.EXPORT_ALL_VARIABLES:

.PHONY: default
default: start-ansible-runner runner/.vault/vault_passphrase.gpg

.PHONY: start-ansible-runner
start-ansible-runner:
	docker-compose up --detach

runner/.vault/vault_passphrase.gpg:
	docker exec -it ansible-runner /bin/bash -lic "scripts/generate_gpg_key.sh"
	docker exec -it ansible-runner /bin/bash -lic "scripts/generate_vault_password.sh"

.PHONY: create-vault-credentials
create-vault-credentials:
	docker exec -it ansible-runner /bin/bash -lic "cd /runner/project && ansible-playbook create_vault_credentials.yml"

.PHONY: view-vault-credentials
view-vault-credentials:
	docker exec -it ansible-runner  /bin/bash -lic "cd /runner/project && ansible-vault view vars/vault.yml"
