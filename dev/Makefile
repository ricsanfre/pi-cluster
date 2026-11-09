SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

DEVDIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
ROOT := $(abspath $(DEVDIR)/..)
KUBE_CONTEXT ?= k3d-picluster
K3D_CLUSTER ?= picluster
DEV_MIN_MEM_GB ?= 8
VAULT ?= 0
NAME ?=
FORCE ?= 0

.DEFAULT_GOAL := help

define require_context
	@ctx="$$(kubectl config current-context 2>/dev/null || true)"; \
	if [ "$$ctx" != "$(KUBE_CONTEXT)" ]; then \
		echo "ERROR: kubectl context is '$${ctx:-<none>}', expected '$(KUBE_CONTEXT)'" >&2; \
		exit 1; \
	fi
endef

.PHONY: help
help: ## Show this help
	@echo "Dev environment targets:"
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*## "}; {printf "  %-24s %s\n", $$1, $$2}'

.PHONY: load-kernel-modules
load-kernel-modules: ## Load the kernel modules Cilium needs (requires sudo)
	sudo modprobe -v iptable_filter
	sudo modprobe -v ip_tables
	sudo modprobe -v iptable_mangle
	sudo modprobe -v iptable_raw
	sudo modprobe -v iptable_nat
	sudo modprobe -v xt_socket

.PHONY: dev-preflight
dev-preflight: ## Check host memory, required tools and writability of the dev tree
	@for cmd in docker k3d kubectl helm flux openssl curl tmpl; do \
		command -v $$cmd >/dev/null || { echo "ERROR: missing '$$cmd'" >&2; exit 1; }; \
	done
	@docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon is not reachable" >&2; exit 1; }
	@docker compose version >/dev/null 2>&1 || { echo "ERROR: the 'docker compose' plugin is not available" >&2; exit 1; }
	@certdir="$(DEVDIR)/external-services/certs"; \
	if [ -d "$$certdir" ] && [ ! -w "$$certdir" ]; then \
		echo "ERROR: $$certdir is not writable by $(shell id -un); cert re-issue and CA seeding would fail" >&2; \
		echo "       Fix: sudo chown -R $$(id -u):$$(id -g) $$certdir" >&2; \
		exit 1; \
	fi
	@mem_kb=$$(awk '/^MemAvailable:/ {print $$2}' /proc/meminfo); \
	mem_gb=$$((mem_kb / 1024 / 1024)); \
	if [ "$$mem_gb" -lt "$(DEV_MIN_MEM_GB)" ]; then \
		echo "ERROR: only $${mem_gb} GiB available, need at least $(DEV_MIN_MEM_GB) GiB" >&2; \
		exit 1; \
	fi; \
	echo "MemAvailable: $${mem_gb} GiB (minimum $(DEV_MIN_MEM_GB) GiB)"
	@ctx="$$(kubectl config current-context 2>/dev/null || true)"; \
	if [ -n "$$ctx" ] && [ "$$ctx" != "$(KUBE_CONTEXT)" ]; then \
		echo "WARNING: current kubectl context is '$$ctx'; dev-up will switch to '$(KUBE_CONTEXT)'"; \
	fi

.PHONY: dev-up
dev-up: ## Create the cluster, start external services, bootstrap Flux and run smoke tests
	$(MAKE) dev-preflight
	./create_cluster.sh
	# Cilium must be installed before the node can become Ready. Do this
	# before starting external services so the cluster comes up promptly.
	./bootstrap.sh
	$(MAKE) dev-services-up
	$(MAKE) dev-smoke

.PHONY: dev-bootstrap
dev-bootstrap: ## Re-run the Cilium/CoreDNS/Flux bootstrap
	@ctx="$$(kubectl config current-context 2>/dev/null || true)"; \
	if [ "$$ctx" != "$(KUBE_CONTEXT)" ]; then \
		echo "ERROR: kubectl context is '$${ctx:-<none>}', expected '$(KUBE_CONTEXT)'" >&2; \
		exit 1; \
	fi
	./bootstrap.sh

.PHONY: dev-status
dev-status: ## Show cluster, Flux and workload status
	$(require_context)
	./status.sh

.PHONY: dev-smoke
dev-smoke: ## Run the base smoke test
	$(require_context)
	./smoke.sh

.PHONY: dev-usage
dev-usage: ## Show host memory, Docker stats and kubectl top
	./usage.sh

.PHONY: dev-render
dev-render: ## Render every dev kustomization without touching a cluster
	./render.sh

.PHONY: dev-down
dev-down: ## Stop external services and delete the k3d cluster (data is kept)
	$(MAKE) dev-services-down
	-k3d cluster delete "$(K3D_CLUSTER)"

.PHONY: dev-recreate
dev-recreate: ## Recreate the cluster from scratch and run smoke tests
	$(MAKE) dev-down
	$(MAKE) dev-up

.PHONY: dev-destroy
dev-destroy: ## Delete the cluster, external-services data, certs and credentials (prompts)
	$(MAKE) dev-services-reset FORCE=$(FORCE)
	-k3d cluster delete "$(K3D_CLUSTER)"
	@if docker network inspect picluster >/dev/null 2>&1; then \
		if [ -z "$$(docker network inspect picluster --format '{{range .Containers}}{{.Name}}{{end}}')" ]; then \
			docker network rm picluster; \
		else \
			echo "Keeping network 'picluster': containers are still attached"; \
		fi; \
	fi

.PHONY: dev-services-up
dev-services-up: ## Start RustFS (and Vault when VAULT=1)
	VAULT=$(VAULT) ./external-services/up.sh

.PHONY: dev-seed-ca
dev-seed-ca: ## Seed the dev CA into the cluster (cert-manager issuer + trust bundle)
	$(require_context)
	./external-services/seed-ca.sh

.PHONY: dev-services-down
dev-services-down: ## Stop external services, keep data
	./external-services/down.sh

.PHONY: dev-services-reset
dev-services-reset: ## Stop external services and delete data/certs/credentials
	FORCE=$(FORCE) ./external-services/reset.sh

.PHONY: dev-poc-new
dev-poc-new: ## Create a new POC workspace: make dev-poc-new NAME=<name>
	@if [ -z "$(NAME)" ]; then echo "ERROR: NAME is required, e.g. make dev-poc-new NAME=cnpg-barman" >&2; exit 1; fi
	./dev-poc-new.sh "$(NAME)"

# Compatibility aliases for existing muscle memory.
.PHONY: create-k3d delete-k3d cluster-bootstrap
create-k3d: ## Alias for create_cluster.sh
	./create_cluster.sh

delete-k3d: ## Alias for k3d cluster delete
	k3d cluster delete "$(K3D_CLUSTER)"

cluster-bootstrap: ## Alias for dev-bootstrap
	./bootstrap.sh
