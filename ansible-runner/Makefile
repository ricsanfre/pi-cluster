
include runner/env

RUNNER=./ansible-runner.sh

.EXPORT_ALL_VARIABLES:

.PHONY: default start-ansible-runner
default: start-ansible-runner

.PHONY: start-ansible-runner
start-ansible-runner:
	docker compose up --detach
