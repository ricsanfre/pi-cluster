.EXPORT_ALL_VARIABLES:

GPG_EMAIL=ricsanfre@gmail.com
GPG_NAME=Ricardo Sanchez

RUNNER=ansible-runner/ansible-runner.sh


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
init: os-upgrade gateway-setup nodes-setup external-services configure-os-backup k3s-install k3s-bootstrap configure-monitoring-gateway


.PHONY: ansible-credentials
ansible-credentials:
	${RUNNER} ansible-playbook create_vault_credentials.yml

.PHONY: view-vault-credentials
view-vault-credentials:
	${RUNNER} ansible-vault view vars/vault.yml

.PHONY: os-upgrade
os-upgrade:
	${RUNNER} ansible-playbook update.yml

.PHONY: gateway-setup
gateway-setup:
	${RUNNER} ansible-playbook setup_picluster.yml --tags "gateway"

.PHONY: nodes-setup
nodes-setup:
	${RUNNER} ansible-playbook setup_picluster.yml --tags "nodes"

.PHONY: external-services
external-services:
	${RUNNER} ansible-playbook external_services.yml

.PHONY: configure-os-backup
configure-os-backup:
	${RUNNER} ansible-playbook backup_configuration.yml

.PHONY: configure-monitoring-gateway
configure-monitoring-gateway:
	${RUNNER} ansible-playbook deploy_monitoring_agent.yml

.PHONY: os-backup
os-backup:
	${RUNNER} ansible -b -m shell -a 'systemctl start restic-backup' raspberrypi

.PHONY: k3s-install
k3s-install:
	${RUNNER} ansible-playbook k3s_install.yml

.PHONY: k3s-bootstrap
k3s-bootstrap:
	${RUNNER} ansible-playbook k3s_bootstrap.yml

.PHONY: k3s-reset
k3s-reset:
	${RUNNER} ansible-playbook k3s_reset.yml

.PHONY: external-services-reset
external-services-reset:
	${RUNNER} ansible-playbook reset_external_services.yml

.PHONY: shutdown-k3s-worker
shutdown-k3s-worker:
	${RUNNER} ansible -b -m shell -a "shutdown -h 1 min" k3s_worker

.PHONY: shutdown-k3s-master
shutdown-k3s-master:
	${RUNNER} ansible -b -m shell -a "shutdown -h 1 min" k3s_master

.PHONY: shutdown-gateway
shutdown-gateway:
	${RUNNER} ansible -b -m shell -a "shutdown -h 1 min" gateway
