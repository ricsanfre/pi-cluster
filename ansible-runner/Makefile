.EXPORT_ALL_VARIABLES:

BUILD_ARGS=
TAG=ansible-runner

.PHONY: default
default: build-ansible-runner config-ansible-runner

.PHONY: build-ansible-runner
build-ansible-runner:
	docker build ${BUILD_ARGS} --tag ${TAG} .

.PHONY: config-ansible-runner
config-ansible-runner:
	docker run --rm -it \
	  --env-file env \
	  -v ${PWD}/../ansible:/runner/project \
	  -v ${PWD}/runner/artifacts:/runner/artifacts \
      -v ${PWD}/runner/.gnupg:/home/runner/.gnupg \
      -v ${PWD}/runner/.vault:/home/runner/.vault \
      -v ${PWD}/../scripts:/home/runner/scripts \
	  ${TAG} /bin/bash -c "scripts/generate_gpg_key.sh"
	docker run --rm \
	  --env-file env \
	  -v ${PWD}/../ansible:/runner/project \
	  -v ${PWD}/runner/artifacts:/runner/artifacts \
      -v ${PWD}/runner/.gnupg:/home/runner/.gnupg \
      -v ${PWD}/runner/.vault:/home/runner/.vault \
      -v ${PWD}/../scripts:/home/runner/scripts \
	  ${TAG} /bin/bash -c "scripts/generate_vault_password.sh"

.PHONY: execute-ansible
execute-ansible:
	docker run -it --rm -v ${PWD}/../ansible:/runner/project \
	  -v ${PWD}/runner/artifacts:/runner/artifacts \
      -v ${PWD}/runner/.gnupg:/home/runner/.gnupg \
      -v ${PWD}/runner/.vault:/home/runner/.vault \
	  ${TAG} ansible-runner run /runner -p patch_grafana_dashboards.yml
