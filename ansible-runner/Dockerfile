FROM alpine/kubectl:1.35.3 AS kubectl

FROM alpine/helm:4.1.4 AS helm

FROM alpine:3.23 AS tofu
COPY --from=ghcr.io/opentofu/opentofu:1.11.6 /usr/local/bin/tofu /usr/local/bin/tofu

FROM ghcr.io/astral-sh/uv:0.11.8 AS uv


FROM python:3.14-slim
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
COPY ansible/pyproject.toml /build/pyproject.toml
COPY ansible/uv.lock /build/uv.lock
COPY ansible/requirements.yml /build/requirements.yml

# Install OpenTofu from dedicated image
COPY --from=tofu /usr/local/bin/tofu /usr/local/bin/tofu

# Install kubectl and Helm from dedicated images
COPY --from=kubectl /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=helm /usr/bin/helm /usr/local/bin/helm

ENV USER=runner
ENV FOLDER=/home/runner
RUN /usr/sbin/groupadd $USER && \
    /usr/sbin/useradd $USER -m -d $FOLDER -g $USER -s /bin/bash && \
    echo $USER 'ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    echo 'case ":$PATH:" in *:/home/runner/.venv/bin:*) ;; *) export PATH="/home/runner/.venv/bin:$PATH" ;; esac' >> /home/runner/.bashrc && \
    echo 'case ":$PATH:" in *:/home/runner/.venv/bin:*) ;; *) export PATH="/home/runner/.venv/bin:$PATH" ;; esac' >> /home/runner/.profile && \
    mkdir -p /home/runner/.ansible/roles /home/runner/.ansible/collections /home/runner/.local /home/runner/.cache /home/runner/.config /home/runner/.ssh && \
    chmod 700 /home/runner/.ssh && \
    chown -R $USER:$USER /home/runner

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

# Install helm required plugins
RUN helm plugin install --verify=false https://github.com/databus23/helm-diff

WORKDIR /ansible
