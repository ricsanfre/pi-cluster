DEFAULT_GOAL := help

BOILERPLATE ?= boilerplate
TEMPLATE_DIR ?= fluxcd-app-template
VARS_FILE ?= fluxcd-app-template-vars.yaml
OUTPUT_DIR ?= ./output/$(shell yq '.app_name' $(VARS_FILE) 2>/dev/null | tr -d '"')

.PHONY: \
	help \
	check \
	vars-example \
	generate-fluxcd-app

help: ## Show available targets
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9][a-zA-Z0-9_.-]*:.*##/ {printf "  %-24s %s\n", $$1, $$2}' $(firstword $(MAKEFILE_LIST))

check: ## Verify boilerplate CLI is installed
	@command -v $(BOILERPLATE) >/dev/null 2>&1 || { \
		echo "boilerplate CLI not found in PATH."; \
		echo "Install with: go install github.com/gruntwork-io/boilerplate@latest"; \
		exit 1; \
	}

vars-example: ## Create vars file from example if missing
	@test -f $(VARS_FILE) || cp fluxcd-app-template-vars.yaml.example $(VARS_FILE)
	@echo "Vars file: $(VARS_FILE)"

generate-fluxcd-app: check vars-example ## Generate FluxCD sample app manifests from template
	@mkdir -p "$(OUTPUT_DIR)"
	$(BOILERPLATE) \
		--template-url "$(PWD)/$(TEMPLATE_DIR)" \
		--output-folder "$(OUTPUT_DIR)" \
		--var-file "$(VARS_FILE)" \
		--non-interactive
	@echo "Generated manifests in: $(OUTPUT_DIR)"
