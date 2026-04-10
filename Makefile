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
init: gateway-init os-upgrade gateway-setup external-setup nodes-setup external-services configure-os-backup k3s-install k3s-bootstrap

.PHONY: ansible-credentials
ansible-credentials:
	${RUNNER} ansible-playbook create_vault_credentials.yaml

.PHONY: view-vault-credentials
view-vault-credentials:
	${RUNNER} ansible-vault view vars/vault.yaml

.PHONY: os-upgrade
os-upgrade:
	${RUNNER} ansible-playbook update.yaml

.PHONY: gateway-init
gateway-init:
	${RUNNER} ansible-playbook initialise_gateway.yaml

.PHONY: gateway-setup
gateway-setup:
	${RUNNER} ansible-playbook setup_rdxcluster.yaml --tags "gateway"

.PHONY: gateways-setup
gateways-setup:
	${RUNNER} ansible-playbook setup_rdxcluster.yaml --tags "gateways"

.PHONY: external-setup
external-setup:
	${RUNNER} ansible-playbook setup_rdxcluster.yaml --tags "external"

.PHONY: nodes-setup
nodes-setup:
	${RUNNER} ansible-playbook setup_rdxcluster.yaml --tags "node"

.PHONY: external-services
external-services:
	${RUNNER} ansible-playbook external_services.yaml

.PHONY: configure-os-backup
configure-os-backup:
	${RUNNER} ansible-playbook backup_configuration.yaml

.PHONY: os-backup
os-backup:
	${RUNNER} ansible -b -m shell -a 'systemctl start restic-backup' rdxcluster

.PHONY: k3s-install
k3s-install:
	${RUNNER} ansible-playbook k3s_install.yaml

.PHONY: k3s-bootstrap
k3s-bootstrap:
	${RUNNER} ansible-playbook k3s_bootstrap.yaml

.PHONY: k3s-bootstrap-dev
k3s-bootstrap-dev:
	${RUNNER} ansible-playbook k3s_bootstrap.yaml -e overlay=dev

.PHONY: k3s-reset
k3s-reset:
	${RUNNER} ansible-playbook k3s_reset.yaml

.PHONY: external-services-reset
external-services-reset:
	${RUNNER} ansible-playbook reset_external_services.yaml

.PHONY: deploy-monitoring-agent
deploy-monitoring-agent:
	${RUNNER} ansible-playbook deploy_monitoring_agent.yaml

.PHONY: shutdown
shutdown:
	${RUNNER} ansible-playbook shutdown.yaml

.PHONY: reboot
reboot:
	${RUNNER} ansible-playbook reboot.yaml

.PHONY: kubernetes-vault-config
kubernetes-vault-config:
	${RUNNER} ansible-playbook kubernetes_vault_config.yaml

.PHONY: install-local-utils
install-local-utils:
	echo "dummy" > ansible/vault-pass-dummy
	cd ansible; ANSIBLE_VAULT_PASSWORD_FILE=vault-pass-dummy ansible-playbook install_utilities_localhost.yaml --ask-become-pass
	rm ansible/vault-pass-dummy
