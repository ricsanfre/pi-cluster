
include runner/env

.EXPORT_ALL_VARIABLES:

.PHONY: default
default: build-ansible-runner runner/.vault/vault_passphrase.gpg

.PHONY: build-ansible-runner
build-ansible-runner:
	docker build ${BUILD_ARGS} --tag ${DOCKER_IMG} .

runner/.vault/vault_passphrase.gpg:
	runner/ansible-runner.sh /bin/bash -c "scripts/generate_gpg_key.sh"
	runner/ansible-runner.sh /bin/bash -c "scripts/generate_vault_password.sh"

.PHONY: create-vault-credentials
create-vault-credentials:
	runner/ansible-runner.sh /bin/bash -c "cd /runner/project && ansible-playbook create_vault_credentials.yml"

.PHONY: view-vault-credentials
view-vault-credentials:
	runner/ansible-runner.sh /bin/bash -c "cd /runner/project && ansible-vault view vars/vault.yml"
