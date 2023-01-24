---
title: Quick Start Instructions
permalink: /docs/ansible/
description: Quick Start guide to deploy our Raspberry Pi Kuberentes Cluster using cloud-init, ansible playbooks and ArgoCD
last_modified_at: "23-01-2023"
---

This are the instructions to quickly deploy Kuberentes Pi-cluster using the following tools:
- [cloud-init](https://cloudinit.readthedocs.io/en/latest/): to automate initial OS installation/configuration on each node of the cluster
- [Ansible](https://docs.ansible.com/): to automatically configure cluster nodes,  install and configure external services (DNS, DHCP, Firewall, S3 Storage server, Hashicorp Vautl) install K3S, and bootstraping cluster through installation and configuration of ArgoCD
- [Argo CD](https://argo-cd.readthedocs.io/en/stable/): to automatically deploy Applications to Kuberenetes cluster from manifest files in Git repository.

{{site.data.alerts.note}}

Step-by-step manual process to deploy and configure each component is also described in this documentation.

{{site.data.alerts.end}}

## Preparing the Ansible Control node

- Set-up a Ubuntu Server VM in your laptop to become ansible control node `pimaster`  and create the SSH public/private keys needed for connecting remotely to the servers

  Follow instructions in ["Ansible Control Node"](/docs/pimaster/).

- Clone [Pi-Cluster Git repo](https://github.com/ricsanfre/pi-cluster) or download using the 'Download ZIP' link on GitHub.

  ```shell
  git clone https://github.com/ricsanfre/pi-cluster.git
  ```

- Install Ansible requirements:

  Developed Ansible playbooks depend on external roles that need to be installed.

  ```shell
  ansible-galaxy install -r requirements.yml
  ```

{{site.data.alerts.important}}

All ansible commands (`ansible`, `ansible-galaxy`, `ansible-playbook`, `ansible-vault`) need to be executed within [`/ansible`] directory, so the configuration file [`/ansible/ansible.cfg`]({{ site.git_edit_address }}/ansible/ansible.cfg) can be used. Playbooks are configured to be launched from this directory.

{{site.data.alerts.end}}

## Ansible configuration

### Inventory file

Adjust [`ansible/inventory.yml`]({{ site.git_edit_address }}/ansible/inventory.yml) inventory file to meet your cluster configuration: IPs, hostnames, number of nodes, etc.

{{site.data.alerts.tip}}

If you maintain the private network assigned to the cluster (10.0.0.0/24) and nodes' hostname and IP address, field `mac` (node's mac address) is the only field that you need to change in `inventory.yml` file. MAC addresses will be used to configure automatically DHCP server and assign the proper IP to each node.

This information can be taken when Raspberry PI is booted for first time during the firmware update step: see [Raspberry PI Firmware Update](/docs/firmware).

{{site.data.alerts.end}}

### Configuring ansible remote access 

The UNIX user to be used in remote connection (i.e.: `ansible`) user and its SSH key file location need to be specified

- Modify [`ansible/group_vars/all.yml`]({{ site.git_edit_address }}/ansible/group_vars/all.yml) to set the UNIX user to be used by Ansible in the remote connection (default value `ansible`)

- Modify [`ansible/ansible.cfg`]({{ site.git_edit_address }}/ansible/ansible.cfg) file to include the path to the SSH key of the `ansible` user used in remote connections (`private_key_file` variable)

  ```
  # SSH key
  private_key_file = $HOME/ansible-ssh-key.pem
  ```

### Encrypting secrets/key variables

All secrets/key/passwords variables are stored in a dedicated file, `vars/vault.yml`, so this file can be encrypted using [Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html)

`vault.yml` file is a Ansible vars file containing just a unique yaml variable, `vault`: a yaml dictionary containing all keys/passwords used by the different cluster components.

vault.yml sample file is like this:

```yml
---
vault:
  # K3s secrets
  k3s:
    k3s_token: s1cret0
  # traefik secrets
  traefik:
    basic_auth:
      user: admin
      passwd: s1cret0
  # Minio S3 secrets
  minio:
    root:
      user: root
      key: supers1cret0
    restic:
      user: restic
      key: supers1cret0
....
```

The manual steps to encrypt passwords/keys used in all Playbooks is the following:

1. Edit content `var/vault.yml` file specifying your own values for each of the key/password/secret specified.

2. Encrypt file using ansible-vault

   ```shell
   ansible-vault encrypt vault.yml
   ```
   The command ask for a ansible vault password to encrypt the file.
   After executing the command the file `vault.yml` is encrypted. Yaml content file is not readable.

   {{site.data.alerts.note}}
  
   The file can be decrypted using the following command

   ```shell
   ansible-vault decrypt vault.yml
   ```
   The password using during encryption need to be provided to decrypt the file
   After executing the command the file `vault.yml` is decrypted and show the content in plain text.

   File can be viewed decrypted without modifiying the file using the command

   ```shell
   ansible-vault view vault.yaml 
   ```
   {{site.data.alerts.end}}

{{site.data.alerts.important}}

You do not need to modify and ecrypt manually `vault.yml` file. The file is generated automatically and  encrypted executing an Ansible playbook, see instructions below.

{{site.data.alerts.end}}

#### Automate Ansible Vault decryption with GPG

When using encrypted vault.yaml file all playbooks executed with `ansible-playbook` command need the argument `--ask-vault-pass`, so the password used to encrypt vault file can be provided when starting the playbook.

```shell
ansible-playbook playbook.yml --ask-vault-pass
```

Ansible vault password decryption can be automated using `--vault-password-file` parameter , instead of manually providing the password with each execution (`--ask-vault-pass`).

Ansible vault password file can contain the password in plain-text or a script able to obtain the password.

vault-password-file location can be added to ansible.cfg file, so it is not needed to pass as parameter each time ansible-playbook command is executed

Linux GPG will be used to encrypt Ansible Vault passphrase and automatically obtain the vault password using a vault-password-file script.

- [GnuPG](https://gnupg.org/) Installation and configuration

  In Linux GPG encryption can be used to encrypt/decrypt passwords and tokens data using a GPG key-pair

  GnuPG package has to be installed and a GPG key pair need to be created for encrytion/decryption 

  - Step 1. Install GnuPG packet

    ```shell
    sudo apt install gnupg 
    ```

    Check if it is installed
    ```shell
    gpg --help
    ```

  - Step 2. Generating Your GPG Key Pair

    GPG key-pair consist on a public and private key used for encrypt/decrypt

    ```shell
    gpg --gen-key
    ```

    The process requires to provide a name, email-address and user-id which identify the recipient

    The output of the command is like this:

      ```
      gpg (GnuPG) 2.2.4; Copyright (C) 2017 Free Software Foundation, Inc.
      This is free software: you are free to change and redistribute it.
      There is NO WARRANTY, to the extent permitted by law.

      Note: Use "gpg --full-generate-key" for a full featured key generation dialog.

      GnuPG needs to construct a user ID to identify your key.

      Real name: Ricardo
      Email address: ricsanfre@gmail.com
      You selected this USER-ID:
          "Ricardo <ricsanfre@gmail.com>"

      Change (N)ame, (E)mail, or (O)kay/(Q)uit? O
      We need to generate a lot of random bytes. It is a good idea to perform
      some other action (type on the keyboard, move the mouse, utilize the
      disks) during the prime generation; this gives the random number
      generator a better chance to gain enough entropy.
      We need to generate a lot of random bytes. It is a good idea to perform
      some other action (type on the keyboard, move the mouse, utilize the
      disks) during the prime generation; this gives the random number
      generator a better chance to gain enough entropy.
      gpg: /home/ansible/.gnupg/trustdb.gpg: trustdb created
      gpg: key D59E854B5DD93199 marked as ultimately trusted
      gpg: directory '/home/ansible/.gnupg/openpgp-revocs.d' created
      gpg: revocation certificate stored as '/home/ansible/.gnupg/openpgp-revocs.d/A4745167B84C8C9A227DC898D59E854B5DD93199.rev'
      public and secret key created and signed.

      pub   rsa3072 2021-08-13 [SC] [expires: 2023-08-13]
            A4745167B84C8C9A227DC898D59E854B5DD93199
      uid                      Ricardo <ricsanfre@gmail.com>
      sub   rsa3072 2021-08-13 [E] [expires: 2023-08-13]

      ```

    During the generation process you will be prompted to provide a passphrase.

    This passphrase is needed to decryp


- Generate Vault password and store it in GPG

  Generate the password to be used in ansible-vault encrypt/decrypt process and ecrypt it in using GPG

  - Step 1. Install pwgen packet

      ```shell
      sudo apt install pwgen 
      ```

  - Step 2: Generate Vault password and encrypt it using GPG. Store the result as a file in $HOME/.vault

    ```shell
    mkdir -p $HOME/.vault
    pwgen -n 71 -C | head -n1 | gpg --armor --recipient <recipient> -e -o $HOME/.vault/vault_passphrase.gpg
    ```

    where `<recipient>` must be the email address configured during GPG key creation. 

  - Step 3: Generate a script `vault_pass.sh`

    ```shell
    #!/bin/sh
    gpg --batch --use-agent --decrypt $HOME/.vault/vault_passphrase.gpg
    ```
  - Step 4: Modify `ansible.cfg` file, so you can omit the `--vault-password-file` argument.

    ```
    [defaults]
    vault_password_file=vault_pass.sh
    ```
  
  {{site.data.alerts.note}}
  If this repository is clone steps 3 and 4 are not needed since the files are already there.
  {{site.data.alerts.end}}  
  
- Encrypt vautl.yaml file using ansible-vault and GPG password

  ```shell
  ansible-vault encrypt vault.yaml
  ```
  This time only your GPG key passphrase will be asked to automatically encrypt/decrypt the file

#### Vault credentials generation 

Execute playbook to generate ansible vault variable file (`var/vault.yml`) containing all credentials/passwords. Random generated passwords will be generated for all cluster services.

Execute the following command:
```shell
ansible-playbook create_vault_credentials.yml
```
Credentials for external cloud services (IONOS DNS API credentials) will be asked during the execution of the script.

### Modify Ansible Playbook variables

Adjust ansible playbooks/roles variables defined within `group_vars`, `host_vars` and `vars` directories to meet your specific configuration.

The following table shows the variable files defined at ansible's group and host levels

| Group/Host Variable file | Nodes affected |
|----|----|
| [ansible/group_vars/all.yml]({{ site.git_edit_address }}/ansible/group_vars/all.yml){: .link-dark } | all nodes of cluster + gateway node + pimaster |
| [ansible/group_vars/control.yml]({{ site.git_edit_address }}/ansible/group_vars/control.yml){: .link-dark } | control group: gateway node + pimaster |
| [ansible/group_vars/k3s_cluster.yml]({{ site.git_edit_address }}/ansible/group_vars/k3s_cluster.yml){: .link-dark } | all nodes of the k3s cluster |
| [ansible/group_vars/k3s_master.yml]({{ site.git_edit_address }}/ansible/group_vars/k3s_master.yml){: .link-dark } | K3s master nodes |
| [ansible/host_vars/gateway.yml]({{ site.git_edit_address }}/ansible/host_vars/gateway.yml){: .link-dark } | gateway node specific variables|
{: .table .table-secondary .border-dark }


The following table shows the variable files used for configuring the storage, backup server and K3S cluster and services.

| Specific Variable File | Configuration |
|----|----|
| [ansible/vars/picluster.yml]({{ site.git_edit_address }}/ansible/vars/picluster.yml){: .link-dark } | K3S cluster and external services configuration variables |
| [ansible/vars/dedicated_disks/local_storage.yml]({{ site.git_edit_address }}/ansible/vars/dedicated_disks/local_storage.yml){: .link-dark } | Configuration nodes local storage: Dedicated disks setup|
| [ansible/vars/centralized_san/centralized_san_target.yml]({{ site.git_edit_address }}/ansible/vars/centralized_san/centralized_san_target.yml){: .link-dark } | Configuration iSCSI target  local storage and LUNs: Centralized SAN setup|
| [ansible/vars/centralized_san/centralized_san_initiator.yml]({{ site.git_edit_address }}/ansible/vars/centralized_san/centralized_san_initiator.yml){: .link-dark } | Configuration iSCSI Initiator: Centralized SAN setup|
{: .table .table-secondary .border-dark }


{{site.data.alerts.important}}: **About storage configuration**

Ansible Playbook used for doing the basic OS configuration (`setup_picluster.yml`) is able to configure two different storage setups (dedicated disks or centralized SAN) depending on the value of the variable `centralized_san` located in [`ansible/group_vars/all.yml`]({{ site.git_edit_address }}/ansible/group_vars/all.yml). If `centralized_san` is `false` (default value) dedicated disk setup will be applied, otherwise centralized san setup will be configured.

- **Centralized SAN** setup assumes `gateway` node has a SSD disk attached (`/dev/sda`) that has been partitioned during server first boot (part of the cloud-init configuration) reserving 30Gb for the root partition and the rest of available disk for hosting the LUNs

  Final `gateway` disk configuration is:

  - /dev/sda1: Boot partition
  - /dev/sda2: Root Filesystem
  - /dev/sda3: For being used for creating LUNS using LVM.
  
  <br>
  LVM configuration is done by `setup_picluster.yml` Ansible's playbook and the variables used in the configuration can be found in `vars/centralized_san/centralized_san_target.yml`: `storage_volumegroups` and `storage_volumes` variables. Sizes of the different LUNs can be tweaked to fit the size of the SSD Disk used. I used a 480GB disk so, I was able to create LUNs of 100GB for each of the nodes.

- **Dedicated disks** setup assumes that all cluster nodes (`node1-5`) have a SSD disk attached that has been partitioned during server first boot (part of the cloud-init configuration) reserving 30Gb for the root partition and the rest of available disk for creating a logical volume (LVM) mounted as `/storage`

  Final `node1-5` disk configuration is:

  - /dev/sda1: Boot partition
  - /dev/sda2: Root filesystem
  - /dev/sda3: /storage partition
  
  <br>
  LVM configuration is done by `setup_picluster.yml` Ansible's playbook and the variables used in the configuration can be found in `vars/dedicated_disks/local_storage.yml`: `storage_volumegroups`, `storage_volumes`, `storage_filesystems` and `storage_mounts` variables. The default configuration assings all available space in sda3 to a new logical volume formatted with ext4 and mounted as `/storage`

{{site.data.alerts.end}}

{{site.data.alerts.important}}: **About TLS Certificates configuration**

Default configuration, assumes the use of Letscrypt TLS certificates and IONOS DNS for DNS01 challenge.

As an alternative, a custom CA can be created and use it to sign all certificates:
The following changes need to be done:

- Modify Ansible variable `enable_letsencrypt` to false in `/ansible/picluster.yml` file
- Modify Kubernetes applications `ingress.tlsIssuer` (`/argocd/system/<app>/values.yaml`) to `ca` instead of `letsencrypt`.

{{site.data.alerts.end}}


## Installing the nodes

### Update Raspberry Pi firmware

Update firmware in all Raspberry-PIs following the procedure described in ["Raspberry PI firmware update"](/docs/firmware/)

### Install gateway node

Install `gateway` Operating System on Rapberry PI.
   
The installation procedure followed is the described in ["Ubuntu OS Installation"](/docs/ubuntu/) using cloud-init configuration files (`user-data` and `network-config`) for `gateway`, depending on the storage setup selected:

| Storage Configuration | User data    | Network configuration |
|--------------------| ------------- |-------------|
|  Dedicated Disks |[user-data]({{ site.git_edit_address }}/cloud-init/dedicated_disks/gateway/user-data){: .link-dark } | [network-config]({{ site.git_edit_address }}/cloud-init/dedicated_disks/gateway/network-config){: .link-dark }|
| Centralized SAN | [user-data]({{ site.git_edit_address }}/cloud-init/centralized_san/gateway/user-data){: .link-dark } | [network-config]({{ site.git_edit_address }}/cloud-init/centralized_san/gateway/network-config){: .link-dark } |
{: .table .table-secondary .border-dark }

{{site.data.alerts.warning}}**About SSH keys**

Before applying the cloud-init files of the table above, remember to change the following

- `user-data` file: 
  - `ssh_authorized_keys` fields for both users (`ansible` and `oss`). Your own ssh public keys, created during `pimaster` control node preparation, must be included.
  - `timezone` and `locale` can be changed as well to fit your environment.

- `network-config` file: to fit yor home wifi network
   - Replace <SSID_NAME> and <SSID_PASSWORD> by your home wifi credentials
   - IP address (192.168.0.11 in the sample file ), and your home network gateway (192.168.0.1 in the sample file)

{{site.data.alerts.end}}

### Configure gateway node

For automatically execute basic OS setup tasks and configuration of gateway's services (DNS, DHCP, NTP, Firewall, etc.), executes the playbook:

```shell
ansible-playbook setup_picluster.yml --tags "gateway"
```

### Install cluster nodes.

Once `gateway` is up and running the rest of the nodes can be installed and connected to the LAN switch, so they can obtain automatic network configuration via DHCP.

Install `node1-5` Operating System on Raspberry Pi

Follow the installation procedure indicated in ["Ubuntu OS Installation"](/docs/ubuntu/) using the corresponding cloud-init configuration files (`user-data` and `network-config`) depending on the storage setup selected. Since DHCP is used there is no need to change default `/boot/network-config` file located in the ubuntu image.

| Storage Architeture | node1   | node2 | node3 | node4 | node5 |
|-----------| ------- |-------|-------|--------|--------|
| Dedicated Disks | [user-data]({{ site.git_edit_address }}/cloud-init/dedicated_disks/node1/user-data){: .link-dark } | [user-data]({{ site.git_edit_address }}/cloud-init/dedicated_disks/node2/user-data){: .link-dark }| [user-data]({{ site.git_edit_address }}/cloud-init/dedicated_disks/node3/user-data){: .link-dark } | [user-data]({{ site.git_edit_address }}/cloud-init/dedicated_disks/node4/user-data){: .link-dark } | [user-data]({{ site.git_edit_address }}/cloud-init/dedicated_disks/node5/user-data){: .link-dark } |
| Centralized SAN | [user-data]({{ site.git_edit_address }}/cloud-init/centralized_san/node1/user-data){: .link-dark } | [user-data]({{ site.git_edit_address }}/cloud-init/centralized_san/node2/user-data){: .link-dark }| [user-data]({{ site.git_edit_address }}/cloud-init/centralized_san/node3/user-data){: .link-dark } | [user-data]({{ site.git_edit_address }}/cloud-init/centralized_san/node4/user-data){: .link-dark } | [user-data]({{ site.git_edit_address }}/cloud-init/centralized_san/node5/user-data){: .link-dark } |
{: .table .table-secondary .border-dark }

{{site.data.alerts.warning}}**About SSH keys**

Before applying the cloud-init files of the table above, remember to change the following

- `user-data` file: 
  - `ssh_authorized_keys` fields for both users (`ansible` and `oss`). Your own ssh public keys, created during `pimaster` control node preparation, must be included.
  - `timezone` and `locale` can be changed as well to fit your environment.

{{site.data.alerts.end}}

### Configure cluster nodes

For automatically execute basic OS setup tasks (DNS, DHCP, NTP, etc.), executes the playbook:

```shell
ansible-playbook setup_picluster.yml --tags "node"
```

## Configuring external services (Minio and Hashicorp Vault)

Install and configure S3 Storage server (Minio), and Secret Manager (Hashicorp Vault) running the playbook

```shell
ansible-playbook external_services.yml
```
Playbook assumes S3 server is installed in `node1` and Hashicorp Vault in `gateway`.

{{site.data.alerts.note}}
All Ansible vault credentials (vault.yml) are also stored in Hashicorp Vault
{{site.data.alerts.end}}

## Configuring OS level backup (restic)

Automate backup tasks at OS level with restic in all nodes (`node1-node5` and `gateway`) running the playbook:

```shell
ansible-playbook backup_configuration.yml
```
Minio S3 server running in `node1` will be used as backup backend.

{{site.data.alerts.note}}

List of directories to be backed up by restic in each node can be found in variables file `var/all.yml`: `restic_backups_dirs`

Variable `restic_clean_service` which configure and schedule restic's purging activities need to be set to "true" only in one of the nodes. Defaul configuration set `gateway` as the node for executing these tasks.

{{site.data.alerts.end}}

## Kubernetes Applications (GitOps)

ArgoCD is used to deploy automatically packaged applications contained in the repository. These applications are located in [`/argocd`]({{site.git_address}}/tree/master/argocd) directory.

- Modify Root application (App of Apps pattern) to point to your own repository

  Edit file [`/argocd/bootstrap/root/values.yaml`]({{ site.git_edit_address }}/argocd/bootstrap/root/values.yaml).
 
  `gitops.repo` should point to your own cloned repository.
  
  ```yml
  gitops:
    repo: https://github.com/<your-user>/pi-cluster 
  ```

- Tune parameters of the different packaged Applications to meet your specific configuration

  Edit `values.yaml` file of the different applications located in [`/argocd/system`]({{site.git_address}}/tree/master/argocd/system) directory.

## K3S

### K3S Installation

To install K3S cluster execute the playbook:

```shell
ansible-playbook k3s_install.yml
```

### K3S Bootstrap

To bootstrap the cluster, run the playbook:

```shell
ansible-playbook k3s_bootstrap.yml
```
Argo CD will be installed and it will automatically deploy all cluster applications automatically from git repo

- `argocd\bootstrap\root`: Containing root application (App of Apss ArgoCD pattern)
- `argocd\system\<app>`: Containing manifest files for application <app>

### K3s Cluster reset

If you mess anything up in your Kubernetes cluster, and want to start fresh, the K3s Ansible playbook includes a reset playbook, that you can use to remove the installation of K3S:

```shell
ansible-playbook k3s_reset.yml
```

## Shutting down the Raspberry Pi Cluster

To automatically shut down the Raspberry PI cluster, Ansible can be used.

[Kubernetes graceful node shutdown feature](https://kubernetes.io/blog/2021/04/21/graceful-node-shutdown-beta/) is enabled in the culster. This feature is documented [here](https://kubernetes.io/docs/concepts/architecture/nodes/#graceful-node-shutdown). and it ensures that pods follow the normal [pod termination process](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination) during the node shutdown.

For doing a controlled shutdown of the cluster execute the following commands

- Step 1: Shutdown K3S workers nodes:

  ```shell
  ansible-playbook shutdown.yml --limit k3s_worker
  ```
  Command `shutdown -h 1m` is sent to each k3s-worker. Wait for workers nodes to shutdown.

- Step 2: Shutdown K3S master nodes:

  ```shell
  ansible-playbook shutdown.yml --limit k3s_master
  ```
  Command `shutdown -h 1m` is sent to each k3s-master. Wait for master nodes to shutdown.

- Step 3: Shutdown gateway node:
  ```shell
  ansible-playbook shutdown.yml --limit gateway
  ```

`shutdown.yml` playbook connects to each Raspberry PI in the cluster and execute the command `sudo shutdown -h 1m`, commanding the raspberry-pi to shutdown in 1 minute.

After a few minutes, all raspberry pi will be shutdown. You can notice that when the Switch ethernet ports LEDs are off. Then it is safe to unplug the Raspberry PIs.

## Updating Ubuntu packages

To automatically update Ubuntu OS packages run the following playbook:

```shell
ansible-playbook update.yml
```

This playbook automatically updates OS packages to the latest stable version and it performs a system reboot if needed.