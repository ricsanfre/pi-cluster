---
title: Quick Start Instructions
permalink: /docs/ansible/
description: Quick Start guide to deploy our Raspberry Pi Kuberentes Cluster using cloud-init, ansible playbooks and ArgoCD
last_modified_at: "24-06-2023"
---

This are the instructions to quickly deploy Kuberentes Pi-cluster using the following tools:
- [cloud-init](https://cloudinit.readthedocs.io/en/latest/): to automate initial OS installation/configuration on each node of the cluster
- [Ansible](https://docs.ansible.com/): to automatically configure cluster nodes,  install and configure external services (DNS, DHCP, Firewall, S3 Storage server, Hashicorp Vautl) install K3S, and bootstraping cluster through installation and configuration of ArgoCD
- [Argo CD](https://argo-cd.readthedocs.io/en/stable/): to automatically deploy Applications to Kuberenetes cluster from manifest files in Git repository.

{{site.data.alerts.note}}

Step-by-step manual process to deploy and configure each component is also described in this documentation.

{{site.data.alerts.end}}

## Ansible control node setup

- Use your own Linux-based PC or set-up a Ubuntu Server VM to become ansible control node (`pimaster`)

  In case of building a VM check out tip for automating its creation in ["Ansible Control Node"](/docs/pimaster/).

- Clone [Pi-Cluster Git repo](https://github.com/ricsanfre/pi-cluster) or download using the 'Download ZIP' link on GitHub.

  ```shell
  git clone https://github.com/ricsanfre/pi-cluster.git
  ```

- Install `docker` and `docker-compose`

  Follow instructions in ["Ansible Control Node: Installing Ansible Runtime environment"](/docs/pimaster/#installing-ansible-runtime-environment).

- Create and configure Ansible execution environment (`ansible-runner`):

  ```shell
  make ansible-runner-setup
  ```

  This will automatically build and start `ansible-runner` docker container (including all packages and its dependencies), generate GPG key for encrypting with ansible-vault and create SSH key for remote connections.


## Ansible configuration

Ansible configuration (variables and inventory files) might need to be adapted to your particular environment

### Inventory file

Adjust [`ansible/inventory.yml`]({{ site.git_edit_address }}/ansible/inventory.yml) inventory file to meet your cluster configuration: IPs, hostnames, number of nodes, etc.

Add Raspberry PI nodes to the `rpi` group and x86 nodes to `x86` nodes.

{{site.data.alerts.tip}}

If you maintain the private network assigned to the cluster (10.0.0.0/24) and nodes' hostname and IP address, `mac` field (node's mac address) is the only that you need to change in `inventory.yml` file. MAC addresses are used by DHCP server to assign the proper IP to each node.

{{site.data.alerts.end}}

### Configuring ansible remote access 

The UNIX user to be used in remote connections (i.e.: `ricsanfre`) and its SSH key file location need to be specified.

Modify [`ansible/group_vars/all.yml`]({{ site.git_edit_address }}/ansible/group_vars/all.yml) to set the UNIX user to be used by Ansible in the remote connection, `ansible_user` (default value `ansible`) and its SSH private key, `ansible_ssh_private_key_file`

  ```yml
  # Remote user name
  ansible_user: ricsanfre

  # Ansible ssh private key
  ansible_ssh_private_key_file: ~/.ssh/id_rsa
  ```

By default it uses the ssh key automatically created when initializing ansible-runner (`make ansible-runner-setup`) located at `ansible-runner/runner/.ssh` directory.


### Modify Ansible Playbook variables

Adjust ansible playbooks/roles variables defined within `group_vars`, `host_vars` and `vars` directories to meet your specific configuration.

The following table shows the variable files defined at ansible's group and host levels

| Group/Host Variable file | Nodes affected |
|----|----|
| [ansible/group_vars/all.yml]({{ site.git_edit_address }}/ansible/group_vars/all.yml) | all nodes of cluster + gateway node + pimaster |
| [ansible/group_vars/control.yml]({{ site.git_edit_address }}/ansible/group_vars/control.yml) | control group: gateway node + pimaster |
| [ansible/group_vars/k3s_cluster.yml]({{ site.git_edit_address }}/ansible/group_vars/k3s_cluster.yml) | all nodes of the k3s cluster |
| [ansible/group_vars/k3s_master.yml]({{ site.git_edit_address }}/ansible/group_vars/k3s_master.yml) | K3s master nodes |
| [ansible/host_vars/gateway.yml]({{ site.git_edit_address }}/ansible/host_vars/gateway.yml) | gateway node specific variables|
{: .table .table-white .border-dark }


The following table shows the variable files used for configuring the storage, backup server and K3S cluster and services.

| Specific Variable File | Configuration |
|----|----|
| [ansible/vars/picluster.yml]({{ site.git_edit_address }}/ansible/vars/picluster.yml) | K3S cluster and external services configuration variables |
| [ansible/vars/centralized_san/centralized_san_target.yml]({{ site.git_edit_address }}/ansible/vars/centralized_san/centralized_san_target.yml) | Configuration iSCSI target  local storage and LUNs: Centralized SAN setup|
| [ansible/vars/centralized_san/centralized_san_initiator.yml]({{ site.git_edit_address }}/ansible/vars/centralized_san/centralized_san_initiator.yml) | Configuration iSCSI Initiator: Centralized SAN setup|
{: .table .table-white .border-dark }


{{site.data.alerts.important}}: **About Raspberry PI storage configuration**

Ansible Playbook used for doing the basic OS configuration (`setup_picluster.yml`) is able to configure two different storage setups (dedicated disks or centralized SAN) depending on the value of the variable `centralized_san` located in [`ansible/group_vars/all.yml`]({{ site.git_edit_address }}/ansible/group_vars/all.yml). If `centralized_san` is `false` (default value) dedicated disk setup will be applied, otherwise centralized san setup will be configured.

- **Centralized SAN** setup assumes `gateway` node has a SSD disk attached (`/dev/sda`) that has been partitioned during server first boot (part of the cloud-init configuration) reserving 30Gb for the root partition and the rest of available disk for hosting the LUNs

  Final `gateway` disk configuration is:

  - /dev/sda1: Boot partition
  - /dev/sda2: Root Filesystem
  - /dev/sda3: For being used for creating LUNS (LVM partition)
  
  <br>
  LVM configuration is done by `setup_picluster.yml` Ansible's playbook and the variables used in the configuration can be found in `vars/centralized_san/centralized_san_target.yml`: `storage_volumegroups` and `storage_volumes` variables. Sizes of the different LUNs can be tweaked to fit the size of the SSD Disk used. I used a 480GB disk so, I was able to create LUNs of 100GB for each of the nodes.

- **Dedicated disks** setup assumes that all cluster nodes (`node1-5`) have a SSD disk attached that has been partitioned during server first boot (part of the cloud-init configuration) reserving 30Gb for the root partition and the rest of available disk for creating a Linux partition mounted as `/storage`

  Final `node1-5` disk configuration is:

  - /dev/sda1: Boot partition
  - /dev/sda2: Root filesystem
  - /dev/sda3: /storage (linux partition)
  
  <br>
  /dev/sda3 partition is created during first boot, formatted (ext4) and mounted as '/storage'. cloud-init configuration.

{{site.data.alerts.end}}

{{site.data.alerts.important}}: **About TLS Certificates configuration**

Default configuration, assumes the use of Letscrypt TLS certificates and IONOS DNS for DNS01 challenge.

As an alternative, a custom CA can be created and use it to sign all certificates.
The following changes need to be done:

- Modify Ansible variable `enable_letsencrypt` to false in `/ansible/picluster.yml` file
- Modify Kubernetes applications `ingress.tlsIssuer` (`/argocd/system/<app>/values.yaml`) to `ca` instead of `letsencrypt`.

{{site.data.alerts.end}}


### Vault credentials generation 

Generate ansible vault variable file (`var/vault.yml`) containing all credentials/passwords. Random generated passwords will be generated for all cluster services.

Execute the following command:
```shell
make ansible-credentials
```
Credentials for external cloud services (IONOS DNS API credentials) are asked during the execution of the playbook.

### Prepare PXE server

Get PXE boot files and ISO image to automate x86 nodes installation.

```shell
cd metal/x86
make get-kernel-files
make get-uefi-files
```


## Cluster nodes setup

### Update Raspberry Pi firmware

Update firmware in all Raspberry-PIs following the procedure described in ["Raspberry PI firmware update"](/docs/firmware/)

### Install gateway node

Install `gateway` Operating System on Rapberry PI.
   
The installation procedure followed is the described in ["Ubuntu OS Installation"](/docs/ubuntu/rpi/) using cloud-init configuration files (`user-data` and `network-config`) for `gateway`.

`user-data` depends on the storage architectural option selected::

| Dedicated Disks | Centralized SAN    |
|--------------------| ------------- |
|  [user-data]({{ site.git_edit_address }}/metal/rpi/cloud-init/gateway/user-data) | [user-data]({{ site.git_edit_address }}/metal/rpi/cloud-init/gateway/user-data-centralizedSAN) |
{: .table .table-white .border-dark }

`network-config` is the same in both architectures:


| Network configuration |
|---------------------- |
| [network-config]({{ site.git_edit_address }}/metal/rpi/cloud-init/gateway/network-config) |
{: .table .table-white .border-dark }


{{site.data.alerts.warning}}**About SSH keys**

Before applying the cloud-init files of the table above, remember to change the following

- `user-data` file:
  - UNIX privileged user, `ricsanfre`, can be changed. 
  - `ssh_authorized_keys` field for defaul user (`ricsanfre`). Your own ssh public keys, created during `pimaster` control node preparation, must be included.
  - `timezone` and `locale` can be changed as well to fit your environment.

- `network-config` file: to fit yor home wifi network
   - Replace <SSID_NAME> and <SSID_PASSWORD> by your home wifi credentials
   - IP address (192.168.0.11 in the sample file ), and your home network gateway (192.168.0.1 in the sample file)

{{site.data.alerts.end}}

### Configure gateway node

For automatically execute basic OS setup tasks and configuration of gateway's services (DNS, DHCP, NTP, Firewall, etc.), execute the command:

```shell
make gateway-setup
```

### Install cluster nodes.

Once `gateway` is up and running the rest of the nodes can be installed and connected to the LAN switch, so they can obtain automatic network configuration via DHCP.

#### Install Raspberry PI nodes

Install Operating System on Raspberry Pi nodes `node1-5`

Follow the installation procedure indicated in ["Ubuntu OS Installation"](/docs/ubuntu/rpi/) using the corresponding cloud-init configuration files (`user-data` and `network-config`) depending on the storage setup selected. Since DHCP is used there is no need to change default `/boot/network-config` file located in the ubuntu image.


| Dedicated Disks | Centralized SAN  |
|-----------------| ---------------- |
| [user-data]({{ site.git_edit_address }}/metal/rpi/cloud-init/nodes/user-data-SSD-partition) | [user-data]({{ site.git_edit_address }}/metal/rpi/cloud-init/nodes/user-data)| 
{: .table .table-white .border-dark }


In above user-data files, `hostname` field need to be changed for each node (node1-node5).


{{site.data.alerts.warning}}**About SSH keys**

Before applying the cloud-init files of the table above, remember to change the following

- `user-data` file:
  - UNIX privileged user, `ricsanfre`, can be changed.
  - `ssh_authorized_keys` field for default user (`ricsanfre`). Your own ssh public keys, created during `pimaster` control node preparation, must be included.
  - `timezone` and `locale` can be changed as well to fit your environment.

{{site.data.alerts.end}}

#### Install x86 nodes

Install Operating System on x86 nodes (`node-hp-1-2`). P

Follow the installation procedure indicated in ["OS Installation - X86 (PXE)"](/docs/ubuntu/x86/) and adapt the cloud-init files to your environment.

{{site.data.alerts.warning}}

PXE server is automatically configured in `gateway` node and cloud-init files are automatically created from [autoinstall jinja template]({{ site.git_edit_address }}/ansible/roles/pxe-server/templates/cloud-init-autoinstall.yml.j2).

This file and the corresponding host-variables files containing storage configuration, can be tweak to be adpated to your needs.

[autoinstall storage config node-hp-1]({{ site.git_edit_address }}/ansible/host_vars/node-hp-1.yml)

If the template or the storage config files are changed, in order to deploy the changes in the PXE server, `make gateway-setup` need to be executed.

{{site.data.alerts.end}}

### Configure cluster nodes

For automatically execute basic OS setup tasks (DNS, DHCP, NTP, etc.), execute the command:

```shell
make nodes-setup
```

## Configuring external services (Minio and Hashicorp Vault)

Install and configure S3 Storage server (Minio), and Secret Manager (Hashicorp Vault) running the command:

```shell
make external-services
```
Ansible Playbook assumes S3 server is installed in a external node `s3` and Hashicorp Vault in `gateway`.

{{site.data.alerts.note}}
All Ansible vault credentials (vault.yml) are also stored in Hashicorp Vault
{{site.data.alerts.end}}

## Configuring OS level backup (restic)

Automate backup tasks at OS level with restic in all nodes (`node1-node5` and `gateway`) running the command:

```shell
make configure-os-backup
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

To install K3S cluster, execute the command:

```shell
make k3s-install
```

### K3S Bootstrap

To bootstrap the cluster, run the command:

```shell
make k3s-bootstrap
```
Argo CD will be installed and it will automatically deploy all cluster applications automatically from git repo

- `argocd\bootstrap\root`: Containing root application (App of Apss ArgoCD pattern)
- `argocd\system\<app>`: Containing manifest files for application <app>

### K3s Cluster reset

If you mess anything up in your Kubernetes cluster, and want to start fresh, the K3s Ansible playbook includes a reset playbook, that you can use to remove the installation of K3S:

```shell
make k3s-reset
```

## Shutting down the Raspberry Pi Cluster

To automatically shut down the Raspberry PI cluster, Ansible can be used.

[Kubernetes graceful node shutdown feature](https://kubernetes.io/blog/2021/04/21/graceful-node-shutdown-beta/) is enabled in the culster. This feature is documented [here](https://kubernetes.io/docs/concepts/architecture/nodes/#graceful-node-shutdown). and it ensures that pods follow the normal [pod termination process](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination) during the node shutdown.

For doing a controlled shutdown of the cluster execute the following commands

- Step 1: Shutdown K3S workers nodes:

  ```shell
  make shutdown-k3s-worker
  ```

- Step 2: Shutdown K3S master nodes:

  ```shell
  make shutdown-k3s-master
  ```

- Step 3: Shutdown gateway node:
  ```shell
  make shutdown-gateway
  ```

`shutdown` commands connects to each Raspberry PI in the cluster and execute the command `sudo shutdown -h 1m`, commanding the raspberry-pi to shutdown in 1 minute.

After a few minutes, all raspberry pi will be shutdown. You can notice that when the Switch ethernet ports LEDs are off. Then it is safe to unplug the Raspberry PIs.

## Updating Ubuntu packages

To automatically update Ubuntu OS packages, run the following command:

```shell
make os-upgrade
```

This playbook automatically updates OS packages to the latest stable version and it performs a system reboot if needed.