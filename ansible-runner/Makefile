.EXPORT_ALL_VARIABLES:

BUILD_ARGS=
TAG=ansible-runner

.PHONY: default
default: build-ansible-runner runner/.vault/vault_passphrase.gpg

.PHONY: build-ansible-runner
build-ansible-runner:
	docker build ${BUILD_ARGS} --tag ${TAG} .

runner/.vault/vault_passphrase.gpg:
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

.PHONY: create-vault-credentials
create-vault-credentials:
	docker run -it --rm \
	  --env-file env \
	  -v ${PWD}/../ansible:/runner/project \
	  -v ${PWD}/runner/artifacts:/runner/artifacts \
      -v ${PWD}/runner/.gnupg:/home/runner/.gnupg \
      -v ${PWD}/runner/.vault:/home/runner/.vault \
	  ${TAG} /bin/bash -c "cd /runner/project && ansible-playbook create_vault_credentials.yml"

.PHONY: view-vault-credentials
view-vault-credentials:
	docker run -it --rm \
	  --env-file env \
	  -v ${PWD}/../ansible:/runner/project \
	  -v ${PWD}/runner/artifacts:/runner/artifacts \
      -v ${PWD}/runner/.gnupg:/home/runner/.gnupg \
      -v ${PWD}/runner/.vault:/home/runner/.vault \
	  ${TAG} /bin/bash -c "cd /runner/project && ansible-vault view vars/vault.yml"
