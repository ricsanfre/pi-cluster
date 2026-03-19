.EXPORT_ALL_VARIABLES:

RUNNER := ansible-runner/ansible-runner.sh
ANSIBLE_DIR := ansible
ANSIBLE_LOCAL_ROLES_DIR := $(HOME)/.ansible/roles
ANSIBLE_LOCAL_COLLECTIONS_DIR := $(HOME)/.ansible/collections
KUBECONFIG := $(HOME)/.kube/config

VAULT_SECRET_FILE ?= $(HOME)/.secrets/vault.env
ifneq ($(wildcard $(VAULT_SECRET_FILE)),)
VAULT_ADDR ?= $(shell awk -F= '/^VAULT_ADDR=/{print substr($$0,index($$0,"=")+1); exit}' "$(VAULT_SECRET_FILE)")
VAULT_TOKEN ?= $(shell awk -F= '/^VAULT_TOKEN=/{print substr($$0,index($$0,"=")+1); exit}' "$(VAULT_SECRET_FILE)")
VAULT_CACERT ?= $(shell awk -F= '/^VAULT_CACERT=/{print substr($$0,index($$0,"=")+1); exit}' "$(VAULT_SECRET_FILE)")
endif
VAULT_ADDR ?=
VAULT_TOKEN ?=
VAULT_CACERT ?=
ifneq ($(wildcard $(KUBECONFIG)),)
K3S_API_VIP ?= $(shell awk '/^[[:space:]]*server:[[:space:]]*https?:\/\// {url=$$2; sub(/^https?:\/\//,"",url); sub(/:[0-9]+.*/,"",url); print url; exit}' "$(KUBECONFIG)")
endif
K3S_API_VIP ?= 10.0.0.11

TF_VAR_enable_kubernetes_auth ?= true
TF_VAR_enable_policies ?= true
TF_VAR_enable_roles ?= true
TF_VAR_enable_secrets ?= true
TF_VAR_kubernetes_host ?= https://$(K3S_API_VIP):6443

.DEFAULT_GOAL := help

.PHONY: \
	help \
	default \
	prepare-ansible \
	ansible-local-setup \
	ansible-local-galaxy \
	ansible-local-lint \
	ansible-local-syntax-check-external-services \
	uv-lock-check \
	lint \
	lint-ci \
	syntax-check-external-services \
	lint-fix-whitespace \
	clean \
	ansible-runner-setup \
	init \
	secret-files \
	os-upgrade \
	external-setup \
	nodes-setup \
	dns-setup \
	pxe-setup \
	external-services \
	configure-os-backup \
	os-backup \
	k3s-install \
	k3s-bootstrap \
	k3s-bootstrap-dev \
	k3s-reset \
	external-services-reset \
	openwrt-certbot-tls \
	deploy-monitoring-agent \
	shutdown-k3s-worker \
	shutdown-k3s-master \
	shutdown-picluster \
	deploy-vault \
	deploy-minio \
	load-external-services-keys \
	get-pi-status \
	install-local-utils \
	tofu-vault-init \
	tofu-vault-plan \
	tofu-vault-apply

help: ## Show this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9][a-zA-Z0-9_.-]*:.*##/ {printf "  %-32s %s\n", $$1, $$2}' $(firstword $(MAKEFILE_LIST))

default: help ## Alias for help

prepare-ansible: ansible-runner-setup secret-files ## Bootstrap runner and generate secret files

ansible-local-setup: ## Create/update local UV-based Ansible environment and install Galaxy deps
	cd $(ANSIBLE_DIR) && uv sync --frozen
	$(MAKE) ansible-local-galaxy

ansible-local-galaxy: ## Install Ansible roles/collections using local UV env
	cd $(ANSIBLE_DIR) && mkdir -p $(ANSIBLE_LOCAL_ROLES_DIR) $(ANSIBLE_LOCAL_COLLECTIONS_DIR)
	cd $(ANSIBLE_DIR) && uv run ansible-galaxy role install -r requirements.yml --roles-path "$(ANSIBLE_LOCAL_ROLES_DIR)" --timeout 600
	cd $(ANSIBLE_DIR) && uv run ansible-galaxy collection install -r requirements.yml --collections-path "$(ANSIBLE_LOCAL_COLLECTIONS_DIR)"

ansible-local-lint: ansible-local-setup ## Run yamllint using local UV env
	cd $(ANSIBLE_DIR) && uv run yamllint .

ansible-local-syntax-check-external-services: ansible-local-galaxy ## Syntax-check external services playbook using local UV env
	cd $(ANSIBLE_DIR) && uv run ansible-playbook --syntax-check external_services.yml

uv-lock-check: ## Ensure uv.lock is in sync with pyproject.toml
	cd $(ANSIBLE_DIR) && uv lock --check

lint: ## Run yamllint in the runner container
	$(RUNNER) yamllint .

lint-ci: lint ## CI-parity YAML lint

syntax-check-external-services: ansible-runner-setup ## Ansible syntax check for external services playbook
	cd ansible && ../$(RUNNER) ansible-playbook --syntax-check external_services.yml

lint-fix-whitespace: ## Trim trailing spaces and ensure newline at EOF for YAML files
	$(RUNNER) /bin/bash -lc 'cd /runner && find . -type f \( -name "*.yml" -o -name "*.yaml" \) ! -path "./.ansible/*" -print0 | xargs -0 sed -i -E "s/[[:space:]]+$$//"'
	$(RUNNER) /bin/bash -lc 'cd /runner && python3 -c "from pathlib import Path\nfor p in Path(\".\").rglob(\"*.yml\"):\n    if str(p).startswith(\".ansible/\"):\n        continue\n    b = p.read_bytes()\n    if b and not b.endswith(b\"\\n\"):\n        p.write_bytes(b + b\"\\n\")\nfor p in Path(\".\").rglob(\"*.yaml\"):\n    if str(p).startswith(\".ansible/\"):\n        continue\n    b = p.read_bytes()\n    if b and not b.endswith(b\"\\n\"):\n        p.write_bytes(b + b\"\\n\")"'

clean: k3s-reset external-services-reset ## Reset k3s and external services

ansible-runner-setup: ## Build and prepare ansible runner
	$(MAKE) -C ansible-runner

init: os-upgrade nodes-setup external-services configure-os-backup k3s-install k3s-bootstrap ## Full cluster initialization workflow

secret-files: ## Create encrypted/local secret files for Ansible runs
	$(RUNNER) ansible-playbook create_secret_files.yml

os-upgrade: ## Upgrade OS packages on target nodes
	$(RUNNER) ansible-playbook update.yml

external-setup: ## Configure external services host prerequisites
	$(RUNNER) ansible-playbook setup_picluster.yml --tags "external"

nodes-setup: ## Configure node prerequisites
	$(RUNNER) ansible-playbook setup_picluster.yml --tags "node"

dns-setup: ## Configure authoritative DNS
	$(RUNNER) ansible-playbook configure_dns_authoritative.yml

pxe-setup: ## Configure PXE server
	$(RUNNER) ansible-playbook configure_pxe_server.yml

external-services: ## Deploy and configure external services
	$(RUNNER) ansible-playbook external_services.yml

configure-os-backup: ## Configure node backup jobs
	$(RUNNER) ansible-playbook backup_configuration.yml

os-backup: ## Trigger restic backup on all cluster nodes
	$(RUNNER) ansible -b -m shell -a 'systemctl start restic-backup' picluster

k3s-install: ## Install k3s on cluster nodes
	$(RUNNER) ansible-playbook k3s_install.yml

k3s-bootstrap: ## Bootstrap k3s services and addons
	$(RUNNER) ansible-playbook k3s_bootstrap.yml

k3s-bootstrap-dev: ## Bootstrap k3s using dev overlay
	$(RUNNER) ansible-playbook k3s_bootstrap.yml -e overlay=dev

k3s-reset: ## Reset k3s from all nodes
	$(RUNNER) ansible-playbook k3s_reset.yml

external-services-reset: ## Reset external services
	$(RUNNER) ansible-playbook reset_external_services.yml

openwrt-certbot-tls: ## Generate gateway TLS certificate via certbot
	$(RUNNER) ansible-playbook generate_gateway_tls_certificate.yml
	./metal/openwrt/script/openwrt-deploy-tls.sh

deploy-monitoring-agent: ## Deploy monitoring agent
	$(RUNNER) ansible-playbook deploy_monitoring_agent.yml

shutdown-k3s-worker: ## Shutdown worker nodes in 1 minute
	$(RUNNER) ansible -b -m shell -a "shutdown -h 1 min" k3s_worker

shutdown-k3s-master: ## Shutdown master nodes in 1 minute
	$(RUNNER) ansible -b -m shell -a "shutdown -h 1 min" k3s_master

shutdown-picluster: ## Shutdown all cluster nodes in 1 minute
	$(RUNNER) ansible -b -m shell -a "shutdown -h 1 min" picluster

deploy-vault: ## Deploy Vault workloads
	$(RUNNER) ansible-playbook deploy_vault.yml

deploy-minio: ## Deploy MinIO workloads
	$(RUNNER) ansible-playbook deploy_minio.yml

load-external-services-keys: ## Load external services keys into the cluster
	$(RUNNER) ansible-playbook load_external_services_keys.yml

get-pi-status: ## Get Raspberry Pi throttling status
	$(RUNNER) ansible -b -m shell -a "pi_throttling" raspberrypi

install-local-utils: ## Install local utility tooling on localhost
	cd ansible; ansible-playbook install_utilities_localhost.yml --ask-become-pass

tofu-vault-init: ## Initialize terraform/vault with Vault env from $(VAULT_SECRET_FILE)
	@set -e; \
	[ -n "$(VAULT_ADDR)" ] || (echo "ERROR: VAULT_ADDR is empty. Set VAULT_ADDR or provide it in $(VAULT_SECRET_FILE)." && exit 1); \
	[ -n "$(VAULT_TOKEN)" ] || (echo "ERROR: VAULT_TOKEN is empty. Set VAULT_TOKEN or provide it in $(VAULT_SECRET_FILE)." && exit 1); \
	$(RUNNER) env \
	  VAULT_ADDR="$(VAULT_ADDR)" \
	  VAULT_ADDRESS="$(VAULT_ADDR)" \
	  VAULT_TOKEN="$(VAULT_TOKEN)" \
	  VAULT_CACERT="$(VAULT_CACERT)" \
	  TF_VAR_vault_address="$(VAULT_ADDR)" \
	  TF_VAR_vault_token="$(VAULT_TOKEN)" \
	  bash -lc 'cd /terraform/vault && tofu init -no-color'

tofu-vault-plan: tofu-vault-init ## Plan terraform/vault using configure_vault_integration.yml feature flags
	@set -e; \
	[ -n "$(VAULT_ADDR)" ] || (echo "ERROR: VAULT_ADDR is empty. Set VAULT_ADDR or provide it in $(VAULT_SECRET_FILE)." && exit 1); \
	[ -n "$(VAULT_TOKEN)" ] || (echo "ERROR: VAULT_TOKEN is empty. Set VAULT_TOKEN or provide it in $(VAULT_SECRET_FILE)." && exit 1); \
	$(RUNNER) env \
	  VAULT_ADDR="$(VAULT_ADDR)" \
	  VAULT_ADDRESS="$(VAULT_ADDR)" \
	  VAULT_TOKEN="$(VAULT_TOKEN)" \
	  VAULT_CACERT="$(VAULT_CACERT)" \
	  TF_VAR_vault_address="$(VAULT_ADDR)" \
	  TF_VAR_vault_token="$(VAULT_TOKEN)" \
	  TF_VAR_kubernetes_host="$(TF_VAR_kubernetes_host)" \
	  TF_VAR_enable_kubernetes_auth="$(TF_VAR_enable_kubernetes_auth)" \
	  TF_VAR_enable_policies="$(TF_VAR_enable_policies)" \
	  TF_VAR_enable_roles="$(TF_VAR_enable_roles)" \
	  TF_VAR_enable_secrets="$(TF_VAR_enable_secrets)" \
	  bash -lc 'cd /terraform/vault && tofu plan -no-color -var="enable_kubernetes_auth=true" -var="enable_policies=true" -var="enable_roles=true" -var="enable_secrets=true" -out=tfplan'

tofu-vault-apply: tofu-vault-plan ## Apply terraform/vault plan generated by tofu-vault-plan
	@set -e; \
	[ -n "$(VAULT_ADDR)" ] || (echo "ERROR: VAULT_ADDR is empty. Set VAULT_ADDR or provide it in $(VAULT_SECRET_FILE)." && exit 1); \
	[ -n "$(VAULT_TOKEN)" ] || (echo "ERROR: VAULT_TOKEN is empty. Set VAULT_TOKEN or provide it in $(VAULT_SECRET_FILE)." && exit 1); \
	$(RUNNER) env \
	  VAULT_ADDR="$(VAULT_ADDR)" \
	  VAULT_ADDRESS="$(VAULT_ADDR)" \
	  VAULT_TOKEN="$(VAULT_TOKEN)" \
	  VAULT_CACERT="$(VAULT_CACERT)" \
	  TF_VAR_vault_address="$(VAULT_ADDR)" \
	  TF_VAR_vault_token="$(VAULT_TOKEN)" \
	  TF_VAR_kubernetes_host="$(TF_VAR_kubernetes_host)" \
	  TF_VAR_enable_kubernetes_auth="$(TF_VAR_enable_kubernetes_auth)" \
	  TF_VAR_enable_policies="$(TF_VAR_enable_policies)" \
	  TF_VAR_enable_roles="$(TF_VAR_enable_roles)" \
	  TF_VAR_enable_secrets="$(TF_VAR_enable_secrets)" \
	  bash -lc 'cd /terraform/vault && tofu apply -no-color -auto-approve tfplan'
