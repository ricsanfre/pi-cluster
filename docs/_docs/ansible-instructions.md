---
title: Quick Start Instructions
permalink: /docs/ansible/
description: Quick Start guide to deploy our Raspberry Pi Kuberentes Cluster using cloud-init, ansible playbooks and FluxCD
last_modified_at: "16-01-2025"
---

This are the instructions to quickly deploy Kuberentes Pi-cluster using the following tools:
- [cloud-init](https://cloudinit.readthedocs.io/en/latest/): to automate initial OS installation/configuration on each node of the cluster
- [Ansible](https://docs.ansible.com/): to automatically configure cluster nodes,  install and configure external services (DNS, DHCP, Firewall, S3 Storage server, Hashicorp Vautl) install K3S, and bootstraping cluster through installation and configuration of FluxCD
- [Flux CD](https://fluxcd.io/): to automatically deploy Applications to Kuberenetes cluster from manifest files in Git repository.

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

- Install `docker` and `docker compose`

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

Se the node, i.e `node1`, which is going to be used to install non-kubernetes services (dns server, pxe server, load balancer (ha-proxy), vault server). It has to be added to groups `dns`, `pxe`, `vault` and `haproxy`

{{site.data.alerts.tip}}

If you maintain the private network assigned to the cluster (10.0.0.0/24) and nodes' hostname and IP address, `mac` field (node's mac address) is the only that you need to change in `inventory.yml` file. MAC addresses are used by PXE server (automate installation of x86 servers).

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
| [ansible/group_vars/all.yml]({{ site.git_edit_address }}/ansible/group_vars/all.yml) | all nodes of cluster + pimaster |
| [ansible/group_vars/control.yml]({{ site.git_edit_address }}/ansible/group_vars/control.yml) | control group: pimaster |
| [ansible/group_vars/k3s_cluster.yml]({{ site.git_edit_address }}/ansible/group_vars/k3s_cluster.yml) | all kubernetes nodes (master and workers) of the cluster |
| [ansible/group_vars/k3s_master.yml]({{ site.git_edit_address }}/ansible/group_vars/k3s_master.yml) | K3s master nodes |
| [ansible/host_vars/node1.yml]({{ site.git_edit_address }}/ansible/host_vars/node1.yml) | external services node specific variables|
{: .table .border-dark }


The following table shows the variable files used for configuring the storage, backup server and K3S cluster and services.

| Specific Variable File | Configuration |
|----|----|
| [ansible/vars/picluster.yml]({{ site.git_edit_address }}/ansible/vars/picluster.yml) | K3S cluster and external services configuration variables |
| [ansible/vars/centralized_san/centralized_san_target.yml]({{ site.git_edit_address }}/ansible/vars/centralized_san/centralized_san_target.yml) | Configuration iSCSI target  local storage and LUNs: Centralized SAN setup|
| [ansible/vars/centralized_san/centralized_san_initiator.yml]({{ site.git_edit_address }}/ansible/vars/centralized_san/centralized_san_initiator.yml) | Configuration iSCSI Initiator: Centralized SAN setup|
{: .table .border-dark }


{{site.data.alerts.important}}: **About Raspberry PI storage configuration**

Ansible Playbook used for doing the basic OS configuration (`setup_picluster.yml`) is able to configure two different storage setups (dedicated disks or centralized SAN) depending on the value of the variable `centralized_san` located in [`ansible/group_vars/all.yml`]({{ site.git_edit_address }}/ansible/group_vars/all.yml). If `centralized_san` is `false` (default value) dedicated disk setup will be applied, otherwise centralized san setup will be configured.

- **Centralized SAN** setup assumes `node1` node has a SSD disk attached (`/dev/sda`) that has been partitioned during server first boot (part of the cloud-init configuration) reserving 30Gb for the root partition and the rest of available disk for hosting the LUNs

  Final `node1` disk configuration is:

  - /dev/sda1: Boot partition
  - /dev/sda2: Root Filesystem
  - /dev/sda3: For being used for creating LUNS (LVM partition)
  
  <br>
  LVM configuration is done by `setup_picluster.yml` Ansible's playbook and the variables used in the configuration can be found in `vars/centralized_san/centralized_san_target.yml`: `storage_volumegroups` and `storage_volumes` variables. Sizes of the different LUNs can be tweaked to fit the size of the SSD Disk used. I used a 480GB disk so, I was able to create LUNs of 100GB for each of the nodes.

- **Dedicated disks** setup assumes that all cluster nodes (`node1-6`) have a SSD disk attached that has been partitioned during server first boot (part of the cloud-init configuration) reserving 30Gb for the root partition and the rest of available disk for creating a Linux partition mounted as `/storage`

  Final `node1-6` disk configuration is:

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

- Modify Ansible variable `enable_letsencrypt` to false in `/ansible/vars/picluster.yml` file
- Modify Kubernetes ingress resources in all applications (`/kubernetes/platform` and `/kubernetes/apps`) so `cert-manager.io/cluster-issuer` annotation points to `ca-issuer` instead of `letsencrypt-issuer`.

{{site.data.alerts.end}}

{{site.data.alerts.important}}: **About GitOps Repository configuration**

Default configuration, assumes the Git Repository used by FluxCD is a public repository.

As an alternative, a private repository can be used.

- Modify Ansible variable `git_private_repo` to true in `/ansible/group_vars/all.yml` file

During Vault credentials generation process, see below, Github PAT will be required

{{site.data.alerts.end}}


### Vault credentials generation 

Generate ansible vault variable file (`var/vault.yml`) containing all credentials/passwords. Random generated passwords will be generated for all cluster services.

Execute the following command:
```shell
make ansible-credentials
```
Credentials for external cloud services (IONOS DNS API credentials) or Github PAT are asked during the execution of the playbook.

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

Install OpenWRT operating system on Raspberry PI or GL-Inet router, `gateway` node
The installation and configuration process is described in ["Cluster Gateway (OpenWRT)"](/docs/openwrt/)


#### Option 2:  Ubuntu OS 

`gateway` router/firewall can be implemented deploying Linux services on Ubuntu 22.04 OS
The installation and configuration process is described in ["Cluster Gateway (Ubuntu)"](/docs/gateway/)

### Install external services node

Once `gateway` node is up and running. External services node, `node1` can be configured.

`node1` is used to install common services: DNS server, PXE server, Vault, etc.

In crentralized SAN architecture `node1` can be configured as SAN server.

Install Ubuntu Operating System on `node1` (Rapberry PI-4B 4GB).
   
The installation procedure followed is the described in ["Ubuntu OS Installation"](/docs/ubuntu/rpi/) using cloud-init configuration files (`user-data` and `network-config`) for `node1`.

`user-data` depends on the storage architectural option selected:

| Dedicated Disks | Centralized SAN    |
|--------------------| ------------- |
|  [user-data]({{ site.git_edit_address }}/metal/rpi/cloud-init/node1/user-data) | [user-data]({{ site.git_edit_address }}/metal/rpi/cloud-init/node1/user-data-centralizedSAN) |
{: .table .border-dark }

`network-config` is the same in both architectures:


| Network configuration |
|---------------------- |
| [network-config]({{ site.git_edit_address }}/metal/rpi/cloud-init/node1/network-config) |
{: .table .border-dark }


{{site.data.alerts.warning}}**About SSH keys**

Before applying the cloud-init files of the table above, remember to change the following

- `user-data` file:
  - UNIX privileged user, `ricsanfre`, can be changed. 
  - `ssh_authorized_keys` field for defaul user (`ricsanfre`). Your own ssh public keys, created during `pimaster` control node preparation, must be included.
  - `timezone` and `locale` can be changed as well to fit your environment.

{{site.data.alerts.end}}

#### Configure external-services node

For automatically execute basic OS setup tasks and configuration of `node1`'s services (DNS, PXE Server, etc.), execute the command:

```shell
make external-setup
```

### Install cluster nodes.

Once `node1` is up and running the rest of the nodes can be installed and connected to the LAN switch.

#### Install Raspberry PI nodes

Install Operating System on Raspberry Pi nodes `node2-6`

Follow the installation procedure indicated in ["Ubuntu OS Installation"](/docs/ubuntu/rpi/) using the corresponding cloud-init configuration files (`user-data` and `network-config`) depending on the storage setup selected. Since DHCP is used there is no need to change default `/boot/network-config` file located in the ubuntu image.


| Dedicated Disks | Centralized SAN  |
|-----------------| ---------------- |
| [user-data]({{ site.git_edit_address }}/metal/rpi/cloud-init/nodes/user-data-SSD-partition) | [user-data]({{ site.git_edit_address }}/metal/rpi/cloud-init/nodes/user-data)| 
{: .table .border-dark }


In above user-data files, `hostname` field need to be changed for each node (node1-node6).

{{site.data.alerts.warning}}**About SSH keys**

Before applying the cloud-init files of the table above, remember to change the following

- `user-data` file:
  - UNIX privileged user, `ricsanfre`, can be changed.
  - `ssh_authorized_keys` field for default user (`ricsanfre`). Your own ssh public keys, created during `pimaster` control node preparation, must be included.
  - `timezone` and `locale` can be changed as well to fit your environment.

{{site.data.alerts.end}}

#### Install x86 nodes

Install Operating System on x86 nodes (`node-hp-x`).

Follow the installation procedure indicated in ["OS Installation - X86 (PXE)"](/docs/ubuntu/x86/) and adapt the cloud-init files to your environment.

To automate deployment of PXE server execute the following command

```shell
make pxe-setup
```

PXE server is automatically deployed in `node1` node (host belonging to `pxe` hosts group in Ansible's inventory file). `cloud-init` files are automatically created from [autoinstall jinja template]({{ site.git_edit_address }}/ansible/roles/pxe-server/templates/cloud-init-autoinstall.yml.j2). for every single host belonging to `x86` hosts group

This file and the corresponding host-variables files containing storage configuration, can be tweak to be adpated to your needs.

[autoinstall storage config node-hp-1]({{ site.git_edit_address }}/ansible/host_vars/node-hp-1.yml)

If the template or the storage config files are changed, in order to deploy the changes in the PXE server, `make pxe-setup` need to be re-executed.

### Configure cluster nodes

For automatically execute basic OS setup tasks (DNS, DHCP, NTP, etc.), execute the command:

```shell
make nodes-setup
```

## Configure External Services

### DNS server

Install and configure DNS authoritative server, Bind9, for homelab subdomain in `node1` (node belonging to Ansible's host group `dns`).

Homelab subdomain is specified in variable `dns_domain` configured in [ansible/group_vars/all.yml]({{ site.git_edit_address }}/ansible/group_vars/all.yml) and DNS server configuration in [ansible/host_vars/node1.yml]({{ site.git_edit_address }}/ansible/host_vars/node1.yml). Update both files to meet your cluster requirements.

```shell
make dns-setup
```

### Minio and Hashicorp Vault 

Install and configure S3 Storage server (Minio), and Secret Manager (Hashicorp Vault) running the command:

```shell
make external-services
```
Ansible Playbook assumes S3 server is installed in a external node `s3` and Hashicorp Vault in `node1` (node belonging to Ansible's host group `vault`).

{{site.data.alerts.note}}
All Ansible vault credentials (vault.yml) are also stored in Hashicorp Vault
{{site.data.alerts.end}}

## Configuring OS level backup (restic)

Automate backup tasks at OS level with restic in all nodes (`node1-node6`) running the command:

```shell
make configure-os-backup
```
Minio S3 server VM, `s3`, hosted in Public Cloud (Oracle Cloud Infrastructure), will be used as backup backend.

{{site.data.alerts.note}}

List of directories to be backed up by restic in each node can be found in variables file `var/all.yml`: `restic_backups_dirs`

Variable `restic_clean_service` which configure and schedule restic's purging activities need to be set to "true" only in one of the nodes. Defaul configuration set `node1` as the node for executing these tasks.

{{site.data.alerts.end}}

## Kubernetes Applications (GitOps)

FluxCD is used to deploy automatically packaged applications contained in the repository. These applications are located in [`/kubernetes`]({{site.git_address}}/tree/master/kubernetes) directory.

- Modify cluster configuration to point to your own repository

  Edit [`kubernetes/clusters/prod/config/cluster.yaml`]({{ site.git_edit_address }}/kubernetes/prod/config/cluster.yam).

  In `GitRepository` resource definition, set `spec.url` to the URL of your repository

- In case of using a private Git repository

  Add following configuration to `GitRepository` resource

  ```yaml
  spec:
    secretRef:
      name: flux-system
  ```

- Modify cluster global variables

  Edit [`kubernetes/clusters/prod/config/cluster-settings.yaml`]({{ site.git_edit_address }}/kubernetes/prod/config/cluster-settings.yam) to use your own configuration. Own DNS domain, External Services DNS names, etc.

- Tune parameters of the different packaged Applications to meet your specific configuration

  Edit helm chart `values.yaml` file and other kubernetes manifest files file of the different applications located in [`/kubernetes`]({{site.git_address}}/tree/master/kubernetes) directory.

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

Flux CD will be installed and it will automatically deploy all cluster applications automatically from git repo.


### K3s Cluster reset

If you mess anything up in your Kubernetes cluster, and want to start fresh, the K3s Ansible playbook includes a reset playbook, that you can use to remove the installation of K3S:

```shell
make k3s-reset
```

## Shutting down the Pi Cluster

To automatically shut down the cluster, Ansible can be used.

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


`shutdown` commands connects to each node in the cluster and execute the command `sudo shutdown -h 1m`, commanding the node to shutdown in 1 minute.

After a few minutes, all nodes will be shutdown. You can notice that when the Switch ethernet ports LEDs are off. Then it is safe to unplug all nodes.

## Updating Ubuntu packages

To automatically update Ubuntu OS packages, run the following command:

```shell
make os-upgrade
```

This playbook automatically updates OS packages to the latest stable version and it performs a system reboot if needed.