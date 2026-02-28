
include runner/env

RUNNER=./ansible-runner.sh

.EXPORT_ALL_VARIABLES:

.PHONY: default
default: start-ansible-runner runner/.ssh/id_rsa

.PHONY: start-ansible-runner
start-ansible-runner:
	docker compose up --detach


runner/.ssh/id_rsa:
	${RUNNER} ssh-keygen -t rsa -P '' -f /home/runner/.ssh/id_rsa

