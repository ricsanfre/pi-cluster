GPG_RECIPIENT=vault@ansible

.PHONY: install-ansible-requirements
install-ansible-requirements: # install Ansible requirements
	cd ansible && ansible-galaxy install -r requirements.yml

.PHONY: gpg-init
gpg-init:
	gpg --quick-generate-key ${GPG_RECIPIENT}

~/.vault/vault_passphrase.gpg: # Ansible vault gpg password
	mkdir -p ~/.vault
	pwgen -n 71 -C | head -n1 | gpg --armor --recipient ${GPG_RECIPIENT} -e -o ~/.vault/vault_passphrase.gpg

.PHONY: init
init: ~/.vault/vault_passphrase.gpg install-ansible-requirements
	cd ansible && ansible-playbook create_vault_credentials.yml

.PHONY: gateway-setup
gateway-setup:
	cd ansible && ansible-playbook setup_picluster.yml --tags "gateway"

.PHONY: nodes-setup
nodes-setup:
	cd ansible && ansible-playbook setup_picluster.yml --tags "nodes"

.PHONY: external-services
external-services:
	cd ansible && ansible-playbook external_services.yml

.PHONY: os-backup
os-backup:
	cd ansible && ansible-playbook backup_configuration.yml

.PHONY: os-upgrade
os-upgrade:
	cd ansible && ansible-playbook update.yml

.PHONY: k3s-install
k3s-install:
	cd ansible && ansible-playbook k3s_install.yml

.PHONY: k3s-bootstrap
k3s-bootstrap:
	cd ansible && ansible-playbook k3s_bootstrap.yml

.PHONY: k3s-reset
k3s-reset:
	cd ansible && ansible-playbook k3s_reset.yml

.PHONY: external-services-reset
external-services-reset:
	cd ansible && ansible-playbook reset_external_services.yml
