FROM ghcr.io/helmfile/helmfile:v1.1.7 AS helmfile


FROM python:slim
ARG ANSIBLE_GALAXY_CLI_COLLECTION_OPTS=--ignore-certs
ARG ANSIBLE_GALAXY_CLI_ROLE_OPTS=--ignore-certs
RUN apt-get update -qq && \
    apt-get install sudo git apt-utils python3-pip pwgen gnupg curl -y && \
    apt-get clean && \
    rm -rf /usr/share/doc/* /usr/share/man/* /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Intall basic Python packages
RUN pip3 install --upgrade pip setuptools
# RUN pip3 install ansible-core ansible-runner

ADD build /build
WORKDIR /build

# Install python dependencies
RUN pip3 install -r requirements.txt

# Install ansible roles/collections dependencies
RUN ansible-galaxy role install $ANSIBLE_GALAXY_CLI_ROLE_OPTS -r requirements.yml --roles-path "/usr/share/ansible/roles" --timeout 600
RUN ANSIBLE_GALAXY_DISABLE_GPG_VERIFY=1 ansible-galaxy collection install $ANSIBLE_GALAXY_CLI_COLLECTION_OPTS -r requirements.yml --collections-path "/usr/share/ansible/collections"

# Configure ansible-runner
RUN ansible-playbook ansible_runner_setup.yml

# Copy helmfile
COPY --from=helmfile /usr/local/bin/helmfile /usr/local/bin/helmfile

ENV USER runner
ENV FOLDER /home/runner
RUN /usr/sbin/groupadd $USER && \
    /usr/sbin/useradd $USER -m -d $FOLDER -g $USER -s /bin/bash && \
    echo $USER 'ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

RUN for dir in \
      /runner \
      /var/lib/letsencrypt \
      /etc/letsencrypt \
      /var/log/letsencrypt ; \
    do mkdir -p $dir ; chown $USER:$USER $dir; chmod 775 $dir ; done

USER $USER

# Install helmfile helm plugins
RUN helmfile init --force

RUN echo "export GPG_TTY=\$(tty)" >> /home/runner/.bashrc

WORKDIR /runner
