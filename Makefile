.EXPORT_ALL_VARIABLES:

RUNNER=ansible-runner/ansible-runner.sh
KUBECONFIG = $(shell pwd)/ansible-runner/runner/.kube/config

.PHONY: default
default: clean

.PHONY: prepare-ansible
prepare-ansible: ansible-runner-setup ansible-credentials

.PHONY: clean
clean: k3s-reset external-services-reset

.PHONY: ansible-runner-setup
ansible-runner-setup:
	make -C ansible-runner

.PHONY: init
init: os-upgrade nodes-setup external-services configure-os-backup k3s-install k3s-bootstrap

.PHONY: ansible-credentials
ansible-credentials:
	${RUNNER} ansible-playbook create_vault_credentials.yml

.PHONY: view-vault-credentials
view-vault-credentials:
	${RUNNER} ansible-vault view vars/vault.yml

.PHONY: os-upgrade
os-upgrade:
	${RUNNER} ansible-playbook update.yml

.PHONY: external-setup
external-setup:
	${RUNNER} ansible-playbook setup_picluster.yml --tags "external"

.PHONY: nodes-setup
nodes-setup:
	${RUNNER} ansible-playbook setup_picluster.yml --tags "node"

.PHONY: dns-setup
dns-setup:
	${RUNNER} ansible-playbook configure_dns_authoritative.yml

.PHONY: pxe-setup
pxe-setup:
	${RUNNER} ansible-playbook configure_pxe_server.yml

.PHONY: external-services
external-services:
	${RUNNER} ansible-playbook external_services.yml

.PHONY: configure-os-backup
configure-os-backup:
	${RUNNER} ansible-playbook backup_configuration.yml

.PHONY: os-backup
os-backup:
	${RUNNER} ansible -b -m shell -a 'systemctl start restic-backup' picluster

.PHONY: k3s-install
k3s-install:
	${RUNNER} ansible-playbook k3s_install.yml

.PHONY: k3s-bootstrap
k3s-bootstrap:
	${RUNNER} ansible-playbook k3s_bootstrap.yml

.PHONY: k3s-bootstrap-dev
k3s-bootstrap-dev:
	${RUNNER} ansible-playbook k3s_bootstrap.yml -e overlay=dev

.PHONY: k3s-reset
k3s-reset:
	${RUNNER} ansible-playbook k3s_reset.yml

.PHONY: external-services-reset
external-services-reset:
	${RUNNER} ansible-playbook reset_external_services.yml

.PHONY: openwrt-certbot-tls
openwrt-certbot-tls:
	${RUNNER} ansible-playbook generate_gateway_tls_certificate.yml

.PHONY: shutdown-k3s-worker
shutdown-k3s-worker:
	${RUNNER} ansible -b -m shell -a "shutdown -h 1 min" k3s_worker

.PHONY: shutdown-k3s-master
shutdown-k3s-master:
	${RUNNER} ansible -b -m shell -a "shutdown -h 1 min" k3s_master


.PHONY: shutdown-picluster
shutdown-picluster:
	${RUNNER} ansible -b -m shell -a "shutdown -h 1 min" picluster

.PHONY: kubernetes-vault-config
kubernetes-vault-config:
	${RUNNER} ansible-playbook kubernetes_vault_config.yml

.PHONY: get-pi-status
get-pi-status:
	${RUNNER} ansible -b -m shell -a "pi_throttling" raspberrypi

.PHONY: install-local-utils
install-local-utils:
	echo "dummy" > ansible/vault-pass-dummy
	cd ansible; ANSIBLE_VAULT_PASSWORD_FILE=vault-pass-dummy ansible-playbook install_utilities_localhost.yml --ask-become-pass
	rm ansible/vault-pass-dummy