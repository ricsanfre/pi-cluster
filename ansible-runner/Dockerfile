FROM ghcr.io/helmfile/helmfile:v1.2.3 AS helmfile

FROM ghcr.io/astral-sh/uv:0.10.4 AS uv


FROM python:3.12-slim
ARG ANSIBLE_GALAXY_CLI_COLLECTION_OPTS=--ignore-certs
ARG ANSIBLE_GALAXY_CLI_ROLE_OPTS=--ignore-certs
ENV UV_LINK_MODE=copy
ENV UV_PROJECT_ENVIRONMENT=/home/runner/.venv
RUN apt-get update -qq && \
    apt-get install sudo git apt-utils pwgen gnupg curl -y && \
    apt-get clean && \
    rm -rf /usr/share/doc/* /usr/share/man/* /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=uv /uv /uvx /usr/local/bin/

WORKDIR /build
COPY ansible-runner/build/install_opentofu.sh /build/install_opentofu.sh
COPY ansible-runner/build/ansible_runner_setup.yml /build/ansible_runner_setup.yml
COPY ansible/pyproject.toml /build/pyproject.toml
COPY ansible/uv.lock /build/uv.lock
COPY ansible/requirements.yml /build/requirements.yml

# Install OpenTofu
RUN chmod +x install_opentofu.sh
RUN ./install_opentofu.sh

ENV USER=runner
ENV FOLDER=/home/runner
RUN /usr/sbin/groupadd $USER && \
    /usr/sbin/useradd $USER -m -d $FOLDER -g $USER -s /bin/bash && \
    echo $USER 'ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    echo 'case ":$PATH:" in *:/home/runner/.venv/bin:*) ;; *) export PATH="/home/runner/.venv/bin:$PATH" ;; esac' >> /home/runner/.bashrc && \
    echo 'case ":$PATH:" in *:/home/runner/.venv/bin:*) ;; *) export PATH="/home/runner/.venv/bin:$PATH" ;; esac' >> /home/runner/.profile && \
    mkdir -p /home/runner/.ansible/roles /home/runner/.ansible/collections /home/runner/.local /home/runner/.cache /home/runner/.config && \
    chown -R $USER:$USER /home/runner

# Copy helmfile
COPY --from=helmfile /usr/local/bin/helmfile /usr/local/bin/helmfile

RUN for dir in \
      /runner \
      /ansible \
      /var/lib/letsencrypt \
      /etc/letsencrypt \
      /var/log/letsencrypt ; \
    do mkdir -p $dir ; chown $USER:$USER $dir; chmod 775 $dir ; done

USER $USER

# Install python dependencies
RUN uv sync --frozen --no-dev

# Install ansible roles/collections dependencies
RUN set -eux; \
        for attempt in 1 2 3; do \
            uv run ansible-galaxy role install $ANSIBLE_GALAXY_CLI_ROLE_OPTS -r requirements.yml --roles-path "/home/runner/.ansible/roles" --timeout 600 && break; \
            if [ "$attempt" -eq 3 ]; then exit 1; fi; \
            sleep 10; \
        done
RUN set -eux; \
        for attempt in 1 2 3; do \
            uv run ansible-galaxy collection install $ANSIBLE_GALAXY_CLI_COLLECTION_OPTS -r requirements.yml --collections-path "/home/runner/.ansible/collections" && break; \
            if [ "$attempt" -eq 3 ]; then exit 1; fi; \
            sleep 10; \
        done

# Configure ansible-runner
RUN ANSIBLE_ROLES_PATH="/home/runner/.ansible/roles:/usr/share/ansible/roles" \
    ANSIBLE_COLLECTIONS_PATHS="/home/runner/.ansible/collections:/usr/share/ansible/collections" \
    uv run ansible-playbook ansible_runner_setup.yml

# Install helmfile required plugins
RUN helm plugin install https://github.com/aslafy-z/helm-git
RUN helm plugin install https://github.com/databus23/helm-diff

WORKDIR /ansible
