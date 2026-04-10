FROM ghcr.io/helmfile/helmfile:v1.4.4 AS helmfile

FROM python:slim
RUN apt-get update -qq && \
    apt-get install sudo git apt-utils python3-pip pwgen gnupg curl wireguard-tools vim whois -y && \
    apt-get clean && \
    rm -rf /usr/share/doc/* /usr/share/man/* /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install basic Python packages
RUN pip3 install --upgrade pip setuptools

ADD build /build
WORKDIR /build

# Install python dependencies
RUN pip3 install -r requirements.txt

# Install ansible roles/collections dependencies
RUN ansible-galaxy role install -r requirements.yaml --roles-path "/usr/share/ansible/roles" --timeout 120
RUN ansible-galaxy collection install -r requirements.yaml --collections-path "/usr/share/ansible/collections"

# Configure ansible-runner
RUN ansible-playbook ansible_runner_setup.yaml

# Copy helmfile
COPY --from=helmfile /usr/local/bin/helmfile /usr/local/bin/helmfile

ENV USER=runner
ENV FOLDER=/home/runner
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
