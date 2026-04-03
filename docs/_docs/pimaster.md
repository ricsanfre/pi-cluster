---
title: Ansible Control Node
permalink: /docs/pimaster/
description: How to configure an Ansible Control node for our Raspberry Pi Kubernetes Cluster using the dual Ansible execution environment, using a Python virtual environment with UV package manager deployed in localhost or within a Docker container.
last_modified_at: "06-03-2026"
---

My laptop running Ubuntu desktop will be used as Ansible Control Node.

As an alternative, a VirtualBox VM running on a Windows PC can be used as the Ansible Control Node, `pimaster`, for automating the provisioning of the Raspberry Pi cluster.

As OS for `pimaster`, Ubuntu 22.04 LTS server can be used.

## Ansible Project structure and configuration

Ansible source code is structured following [typical directory layout](https://docs.ansible.com/ansible/latest/tips_tricks/sample_setup.html#sample-directory-layout):

```
📁 ansible
├── 📁 host_vars
├── 📁 group_vars
├── 📁 vars
├── 📁 tasks
├── 📁 templates
├── 📁 roles 
├── ansible.cfg
├── inventory.yml
├── requirements.yml
├── playbook1.yml
├── playbook2.yml
├── pyproject.toml
├── uv.lock
└── python-version
```

Where:

- `host_vars` and `group_vars` contain Ansible variables belonging to hosts and groups
- `vars` contains Ansible's variables files used by playbooks
- `tasks` contains Ansible's tasks files used by playbooks
- `templates` contains Jinja2's templates used by playbooks
- `roles` contains Ansible's roles
- `inventory.yml` defines hosts, groups, and group relationships used as playbook targets
- `requirements.yml` defines Galaxy roles and collections dependencies
- `pyproject.toml`, `uv.lock`, and `python-version` define the local Ansible execution environment dependencies and configuration to build a Python virtual environment with UV package manager to be used when running Ansible commands in the local environment.


## Ansible Local Running Environment

Create a Python virtual environment managed by [UV](https://astral.sh/uv/), Python's universal virtual environment manager, to run Ansible commands locally. This environment ensures that all dependencies are isolated and consistent.

Python dependencies are managed with UV virtual environment through the following files:

- `pyproject.toml` (dependency source of truth)
- `uv.lock` (pinned dependency graph)
- `.python-version` (Python `3.12`)

Step-by-step local environment setup:

1.  Install UV (if it is not already installed):

    ```shell
    curl -LsSf https://astral.sh/uv/install.sh | sh
    ```

2.  Create initial UV project files within `ansible` project directory (first-time setup only):

    ```shell
    cd ansible
    [ -f pyproject.toml ] || uv init --bare
    [ -f uv.lock ] || uv lock
    ```
    This creates `pyproject.toml` and `uv.lock` when starting from an empty local environment.

3.  Add Ansible and related dependencies to `pyproject.toml`:
    Add the required Ansible runtime and tooling dependencies to the project using `uv add`:

    At least ansible-core and ansible-lint are required, but additional Python dependencies can be added as needed for specific playbook requirements (e.g., `kubernetes`, `hvac`, `certbot`, etc.).

    ```shell
    uv add ansible-core
    uv add yamllint
    uv add ansible-lint
    ```
    Specific versions of dependencies can be added with `uv add <package>@<version>`.

3.  Sync the local Ansible virtual environment dependencies:

    ```shell
    cd ansible
    uv sync --frozen
    ```

5.  Verify local mode command execution:

    ```shell
    cd ansible
    uv run ansible-playbook --version
    ```

6.  Run local lint and syntax checks:

    ```shell
    cd ansible
    uv run yamllint .
    uv run ansible-playbook --syntax-check external_services.yml
    ```

### UV project dependency update flow

When Ansible or other Python dependencies need to be updated, follow this flow:

```shell
uv add <package>
uv lock
uv sync --frozen
```


## Ansible Galaxy dependencies

Ansible playbooks use [Ansible Galaxy](https://galaxy.ansible.com/) roles and collections, which are defined as dependencies in `requirements.yml` file.

Sample `requirements.yml` file:

```yaml
---
roles:
  - name: ricsanfre.minio
    version: v1.1.15
  - name: ricsanfre.backup
    version: v1.1.3
  - name: ricsanfre.vault
    version: v1.0.5
collections:
  - name: community.general
    version: 12.3.0
  - name: kubernetes.core
    version: 6.3.0
  - name: community.hashi_vault
    version: 7.1.0
  - name: ansible.posix
    version: 2.1.0
  - name: community.crypto
    version: 3.1.1
  - name: prometheus.prometheus
    version: 0.27.6
```

The following Ansible community collections are added to `requirements.yml`:

- `community.general`: broad set of general-purpose Ansible modules/plugins.
- `kubernetes.core`: Kubernetes modules for managing cluster resources.
- `community.hashi_vault`: modules/lookups for Vault integration.
- `ansible.posix`: POSIX/Linux modules (system, users, mounts, ACLs, etc.).
- `community.crypto`: crypto and certificate/key management modules.
- `prometheus.prometheus`: modules/roles for Prometheus ecosystem automation.

Ansible Galaxy roles and collections will be installed in a specfied location (e.g., `~/.ansible/roles` and `~/.ansible/collections`) and configured in `ansible.cfg` to be available for playbook execution.

```
📁 $HOME
└── 📁 .ansible
  ├── 📁 roles
  └── 📁 collections
```

```shell
mkdir -p ~/.ansible/roles ~/.ansible/collections
```

Install Galaxy dependencies from `ansible/requirements.yml`:

```shell
uv run ansible-galaxy role install -r requirements.yml --roles-path ~/.ansible/roles
uv run ansible-galaxy collection install -r requirements.yml --collections-path ~/.ansible/collections
```

## Ansible configuration

### Configuration file

Ansible configuration is in `ansible.cfg` file containing paths to roles, collections and inventory file:

`ansible.cfg`
```
[defaults]
# Inventory file location
inventory       = ./inventory.yml
# Ansible execution threads
forks          = 10
# Paths to search for roles in, colon separated
roles_path    = ~/.ansible/roles:./roles
# Path for collections
collections_path = ~/.ansible/collections:./collections
# Disable SSH key host checking
host_key_checking = false
```

### Inventory file

Ansible inventory file, `inventory.yml`, defines hosts and groups of hosts to target with playbooks. It also defines group relationships (e.g., parent-child) and variables specific to hosts or groups.

`inventory.yml`
```yaml
all:
  children:
    picluster:
      hosts:
        node1:
          ansible_host: 10.0.0.11
        node2:
          ansible_host: 10.0.0.12
    vaul:
      hosts:
        node1:  
```

`ansible_host` variable is used to specify the IP address or hostname to connect to for each host in the inventory, which can be different from the inventory hostname (e.g., `node1`, `node2`, etc.) used as an identifier in playbooks.

### SSH keys for Ansible connection

Authentication using SSH keys should be the only mechanism available to login to any server in the Pi Cluster.

In order to improve security, default UNIX user, `ubuntu`, created by cloud images will be disabled. A new unix user, `ricsanfre`, will be created in all servers with root privileges (sudo permissions). This user will be used to connect to the servers from my home laptop and to automate configuration activities using Ansible (used as `ansible_remote_user` variable when connecting).

Public ssh keys can be added to the UNIX user created in all servers as `ssh-authorized-keys` to enable passwordless SSH connection.

Default user in cluster nodes and its authorized SSH public keys will be added to cloud-init configuration when installing Ubuntu OS.


#### SSH keys generation

For generating ansible SSH keys in Linux server execute command:

```shell
ssh-keygen
```

In directory `$HOME/.ssh/` public and private key files can be found for the user

`id_rsa` contains the private key and `id_rsa.pub` contains the public key.

Content of the id_rsa.pub file has to be used as `ssh_authorized_keys` of UNIX user created in cloud-init `user-data`

```shell
cat id_rsa.pub 
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDsVSvxBitgaOiqeX4foCfhIe4yZj+OOaWP+wFuoUOBCZMWQ3cW188nSyXhXKfwYK50oo44O6UVEb2GZiU9bLOoy1fjfiGMOnmp3AUVG+e6Vh5aXOeLCEKKxV3I8LjMXr4ack6vtOqOVFBGFSN0ThaRTZwKpoxQ+pEzh+Q4cMJTXBHXYH0eP7WEuQlPIM/hmhGa4kIw/A92Rm0ZlF2H6L2QzxdLV/2LmnLAkt9C+6tH62hepcMCIQFPvHVUqj93hpmNm9MQI4hM7uK5qyH8wGi3nmPuX311km3hkd5O6XT5KNZq9Nk1HTC2GHqYzwha/cAka5pRUfZmWkJrEuV3sNAl ansible@pimaster
```

#### Configuring Ansible variables to use SSH keys

Ansible variables for SSH connection can be defined in `ansible.cfg` file or in playbooks as `ansible_ssh_private_key_file` variable. Also `ansible_user` variable can be defined to specify the remote user to connect to servers in the cluster (e.g., `ricsanfre`).

`ansible\vars\all.yml` file containing Ansible variables for all hosts can be created with the following content:
```yaml
ansible_user: ricsanfre
ansible_ssh_private_key_file: /home/ricsanfre/.ssh/id_rsa
```
So the same SSH key can be used for all servers in the cluster and the Ansible variable file can be used in all playbooks to avoid repeating the same variables in each playbook.


### Additional tools

Other tools used within Ansible playbooks may need to be installed in the local environment.

Example of such tools used in Pi Cluster automation are:

| Tool | Purpose |
|---|---|
| OpenTofu | Automate Terraform workflows in Ansible playbooks. |
| kubectl | Automate Kubernetes CLI operations in Ansible playbooks. |
| Helm | Automate Helm chart operations in Ansible playbooks. |
{: .table .border-dark } 



## Ansible Dockerized Running Environment

Runs Ansible commands inside the `ansible-runner` container avoiding the need to install Ansible and dependencies in the local environment or any of the additional tools used in the automation workflows.

A single Docker image contains a complete Ansible execution environment with all dependencies and tools pre-installed and configured, providing a consistent runtime for Ansible commands across different host environments.


#### Installing Docker


Follow official [installation guide](https://docs.docker.com/engine/install/ubuntu/).

- Step 1. Uninstall old versions of docker

  ```shell
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
  ```

- Step 2. Install packages to allow apt to use a repository over HTTPS

  ```shell
  sudo apt-get update

  sudo apt-get install \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release
  ```
  
- Step 3. Add Docker's official GPG key

  ```shell
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  ```
  
- Step 4: Add x86_64 repository 

  ```shell
  echo \
    "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  ```

- Step 5: Install Docker Engine

  ```shell
  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  ```

- Step 6: Enable Docker management with a non-privileged user

  - Create docker group

    ```shell
    sudo groupadd docker
    ```
    
  - Add user to docker group

    ```shell
    sudo usermod -aG docker $USER
    ```
    
- Step 7: Configure Docker to start on boot

  ```shell
  sudo systemctl enable docker.service
  sudo systemctl enable containerd.service
  ```

- Step 8: Configure docker daemon.

  - Edit file `/etc/docker/daemon.json`
  
    Set storage driver to overlay2 and to use systemd for the management of the container’s cgroups.
    Optionally default directory for storing images/containers can be changed to a different disk partition (example /data).
    Documentation about the possible options can be found [here](https://docs.docker.com/engine/reference/commandline/dockerd/#daemon-configuration-file)
    
    ```json
    {
        "exec-opts": ["native.cgroupdriver=systemd"],
        "log-driver": "json-file",
        "log-opts": {
        "max-size": "100m"
        },
        "storage-driver": "overlay2",
        "data-root": "/data/docker"  
    }
    ``` 
  - Restart docker

    ```shell
    sudo systemctl restart docker
    ```

#### Creating ansible-runner docker environment

The following directory/files structure is needed for the ansible runtime environment using docker.

```
📁 pi-cluster
├── 📁 ansible-runner
│   ├── docker-compose.yaml
│   ├── Dockerfile
└── 📁 ansible
    ├── ansible.cfg
    ├── inventory.yml
    ├── requirements.yml
    ├── pyproject.toml
    ├── uv.lock
    └── 📁 roles
```

Where:

- `ansible-runner` contains image build file `Dockerfile` and docker compose file `docker-compose.yaml` for lifecycle management of the runner container.
- `ansible` contains the Ansible project source and UV-based local execution environment definition files (pyproject.toml, uv.lock, etc.).

#### Docker Image build details

The runner image is defined in `ansible-runner/Dockerfile` and uses:

-  `python:3.12-slim` as base image
-   UV (`ghcr.io/astral-sh/uv`) for Python environment and dependency management
-   Same Ansible and Galaxy dependencies as the local environment defined in `ansible/pyproject.toml`, `ansible/uv.lock`, and `ansible/requirements.yml`
    - `ansible/pyproject.toml` + `ansible/uv.lock` for reproducible Python dependencies
    - `ansible/requirements.yml` for Galaxy roles and collections
-   Multi-stage binary sources for infrastructure tooling
  - `ghcr.io/opentofu/opentofu:1.11.5` for `tofu` (copied through an Alpine intermediary stage)
  - `alpine/kubectl:1.35.1` for `kubectl`
  - `alpine/helm:3.18.5` for `helm`


Build prerequisites checklist:

- Docker Engine and Docker Compose plugin are installed and working.
- Build context is the repository root (`pi-cluster/`) so all required files are available.
- Required files exist:
  - `ansible-runner/Dockerfile`
  - `ansible/pyproject.toml`
  - `ansible/uv.lock`
  - `ansible/requirements.yml`

Graphical build flow:

<pre class="mermaid">
flowchart TD
    A["1) Prepare build sources<br/>base image + helper stages"]
    B["2) Install OS dependencies<br/>apt packages + cleanup"]
    C["3) Copy build inputs<br/>Docker and Ansible files"]
    D["4) Install infrastructure tooling<br/>OpenTofu + kubectl + helm"]
    E["5) Prepare runner user environment<br/>user, PATH, directories"]
    F["6) Install Python + Galaxy dependencies<br/>uv sync + ansible-galaxy"]
    G["7) Finalize runtime tooling<br/>helm plugins"]
    H["8) Set runtime defaults<br/>WORKDIR /ansible"]

    A --> B --> C --> D --> E --> F --> G --> H
</pre>

Steps/tasks performed when building the Docker image:

1. Prepare build sources:
  - Pull helper binaries from multi-stage images (`uv`, `kubectl`, `helm`).
  - Start from `python:3.12-slim` as the runtime base.

2. Install OS-level runtime dependencies:
  - Install system packages required by Ansible workflows (`sudo`, `git`, `curl`, `gnupg`, etc.).
  - Clean apt caches to keep the image smaller.

3. Copy build inputs into the image:
  - Copy Python dependency files (`pyproject.toml`, `uv.lock`) and Galaxy dependency file (`requirements.yml`).

4. Install infrastructure tooling:
  - Copy `tofu` from `ghcr.io/opentofu/opentofu:1.11.5` via an Alpine intermediary stage.
  - Copy `kubectl` and `helm` binaries from dedicated Alpine images.

5. Create and prepare the `runner` user environment:
  - Create non-root `runner` user and home directory.
  - Configure PATH to include the UV virtual environment.
  - Create required directories for Ansible, cache/config, and runtime mounts.

6. Install Python and Galaxy dependencies:
  - Run `uv sync --frozen --no-dev` to create the pinned Python environment.
  - Install Galaxy roles and collections from `requirements.yml` (with retries).

7. Finalize runtime tooling:
  - Install Helm plugins (`helm-git`, `helm-diff`).

8. Set runtime defaults:
  - Set working directory to `/ansible` so commands run in the Ansible project context.

Current Dockerfile reference:

```dockerfile
FROM alpine/kubectl:1.35.1 AS kubectl

FROM alpine/helm:3.18.5 AS helm

FROM alpine:3.21 AS tofu
COPY --from=ghcr.io/opentofu/opentofu:1.11.5 /usr/local/bin/tofu /usr/local/bin/tofu

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
RUN helm plugin install https://github.com/aslafy-z/helm-git
RUN helm plugin install https://github.com/databus23/helm-diff

WORKDIR /ansible
```

#### Docker Compose details

The `ansible-runner` service is defined in `ansible-runner/docker-compose.yaml`.

```yaml
services:
  ansible-runner:
    image: ansible-runner
    build:
      context: ..
      dockerfile: ansible-runner/Dockerfile
    command: tail -f /dev/null
    container_name: ansible-runner
    restart: unless-stopped
    volumes:
      - ./../ansible:/ansible
      - ./../kubernetes:/kubernetes
      - ./../terraform:/terraform
      - ./../metal/x86/pxe-files:/metal/x86/pxe-files
      - ${HOME}/.secrets:/home/runner/.secrets
      - ${HOME}/.ssh/id_rsa:/home/runner/.ssh/id_rsa:ro
      - ${HOME}/.ssh/id_rsa.pub:/home/runner/.ssh/id_rsa.pub:ro
      - ${HOME}/.kube:/home/runner/.kube
      - ${HOME}/.certbot/log:/home/runner/.certbot/log
      - ${HOME}/.certbot/config:/home/runner/.certbot/config
      - ${HOME}/.certbot/work:/home/runner/.certbot/work
```

Mounted volumes (localhost → container):

  Volume map quick reference:

  | Host (localhost) | Container (`ansible-runner`) | Mode | Content |
  |---|---|---|---|
  | `./ansible` | `/ansible` | `rw` | Ansible project source (playbooks, roles, vars, inventory). |
  | `./kubernetes` | `/kubernetes` | `rw` | Kubernetes manifests and platform/app cluster configuration. |
  | `./terraform` | `/terraform` | `rw` | Terraform/OpenTofu code for Vault and MinIO automation. |
  | `./metal/x86/pxe-files` | `/metal/x86/pxe-files` | `rw` | PXE boot files and related bare-metal assets. |
  | `${HOME}/.secrets` | `/home/runner/.secrets` | `rw` | Local secret/env files used by automation workflows. |
  | `${HOME}/.ssh/id_rsa` | `/home/runner/.ssh/id_rsa` | `ro` | Private SSH key for remote host authentication. |
  | `${HOME}/.ssh/id_rsa.pub` | `/home/runner/.ssh/id_rsa.pub` | `ro` | Public SSH key paired with the private key. |
  | `${HOME}/.kube` | `/home/runner/.kube` | `rw` | Kubeconfig and Kubernetes client context data. |
  | `${HOME}/.certbot/log` | `/home/runner/.certbot/log` | `rw` | Certbot logs and execution history. |
  | `${HOME}/.certbot/config` | `/home/runner/.certbot/config` | `rw` | Certbot account data and issued certificate material. |
  | `${HOME}/.certbot/work` | `/home/runner/.certbot/work` | `rw` | Certbot temporary working files/state. |
  {: .table .border-dark }

This docker-compose file builds and starts the `ansible-runner` Docker container and mounts several host directories, including the Ansible project structure. The container is always running (command is `tail -f /dev/null`), so commands can be executed with `docker exec`, and there is no need to recreate a new container (`docker run`) every time a command needs to be executed.


#### Docker compose execution details

After the image is built and the compose service is defined, runner lifecycle can be managed manually as:

<pre class="mermaid">
flowchart TD
  A["Repository root"] --> B["cd ansible-runner"]
  B --> C["docker compose build"]
  C --> D["docker compose up -d"]
  D --> E["ansible-runner container running"]
  E --> F["docker exec -it ansible-runner &lt;command&gt;"]
  E --> G["docker exec -it ansible-runner /bin/bash"]
  E --> H["(optional) docker compose down"]
  H --> I["container stopped and removed"]
</pre>

```shell
cd ansible-runner
docker compose build
docker compose up -d
```

Any command can be executed in the running container:

```shell
docker exec -it ansible-runner <command>
```

Interactive shell:

```shell
docker exec -it ansible-runner /bin/bash
```

## Command Wrappers Script


After building the local UV-based environment and the Dockerized `ansible-runner` environment, a wrapper script can be used to run commands with a consistent interface using local environment or Dockerized environment based on an environment variable (`ANSIBLE_RUNNER_MODE`).

Create following wrapper script in the repository to run Ansible commands in both environments with the same interface:

`ansible-runner/ansible-runner.sh`
```shell
#!/bin/bash
if [ "$ANSIBLE_RUNNER_MODE" = "local" ]; then
  uv run "$@"
else
  docker exec -it ansible-runner "$@"
fi
```

- Local mode wrapper: `ANSIBLE_RUNNER_MODE=local ./ansible-runner/ansible-runner.sh <command>`
- Docker mode wrapper: `./ansible-runner/ansible-runner.sh <command>`

Examples:

```shell
# Local mode
ANSIBLE_RUNNER_MODE=local ./ansible-runner/ansible-runner.sh ansible-playbook --version

# Docker mode
./ansible-runner/ansible-runner.sh ansible-playbook --version
```


### Makefile

Wrapper script can be used in a Makefile to create convenient shortcuts for common Ansible commands:

```shell
.PHONY: lint syntax check ansible-playbook
lint:
  ./ansible-runner/ansible-runner.sh yamllint .
syntax:
  ./ansible-runner/ansible-runner.sh ansible-playbook --syntax-check
check: lint syntax

ansible-playbook:
  ./ansible-runner/ansible-runner.sh ansible-playbook $(playbook) -i inventory.yml
```

This Makefile defines shortcuts for linting and syntax checking Ansible playbooks, as well as a generic target for running any playbook with the `playbook` variable. The same Makefile can be used in both local and Dockerized environments without modification, providing a consistent interface for Ansible command execution.


