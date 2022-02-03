---
title: Quick Start Instructions
permalink: /docs/ansible/
redirect_from: /docs/ansible_instructions.md
last_modified_at: "01-02-2022"
---

This are the instructions to quickly deploy Kuberentes Pi-cluster using cloud-init and Ansible Playbooks

{{site.data.alerts.note}}

Step-by-step manual process is also described in this documentation.

{{site.data.alerts.end}}

## Preparing the Ansible Control node

- Set-up a Ubuntu Server VM in your laptop to become ansible control node `pimaster`  and create the SSH public/private keys needed for connecting remotely to the servers

  Follow these [instructions](/docs/pimaster/).

- Clone [Pi-Cluster Git repo](https://github.com/ricsanfre/pi-cluster) or download using the 'Download ZIP' link on GitHub.

  ```shell
  git clone https://github.com/ricsanfre/pi-cluster.git
  ```

- Install Ansible requirements:

   Developed Ansible playbooks depend on external roles that need to be installed.

   ```shell
   ansible-galaxy install -r requirements.yml
   ```

## Ansible playbooks configuration

### Inventory file

Adjust [`inventory.yml`]({{ site.git_edit_address }}/inventory.yml) inventory file to meet your cluster configuration: IPs, hostnames, number of nodes, etc.

{{site.data.alerts.tip}}

If you maintain the private network assigned to the cluster (10.0.0.0/24) and the hostnames and IP addresses. The only field that you must change in `inventory.yml` file is the field `mac` containing the node's mac address. This information will be used to configure automatically DHCP server and assign the proper IP to each node.

This information can be taken when Raspberry PI is booted for first time during the firmware update step (see below).

{{site.data.alerts.end}}

### Configuring ansible remote access 

The UNIX user to be used in remote connection (i.e.: `ansible`) user and its SSH key file location need to be specified

- Set in [`group_vars/all.yml`]({{ site.git_edit_address }}/group_vars/all.yml) file the UNIX user to be used by Ansible in the remote connection (default value `ansible`)

- Modify [`ansible.cfg`]({{ site.git_edit_address }}/ansible.cfg) file to include the path to the SSH key of the `ansible` user used in remote connections (`private-file-key` variable)

  ```
  # SSH key
  private_key_file = $HOME/ansible-ssh-key.pem
  ```

- Modify [`all.yml`]({{ site.git_edit_address }}/group_vars/all.yml) file to include your ansible remote UNIX user (`ansible_user` variable) and 
  

### Modify Ansible Playbook variables

Adjust ansible playbooks/roles variables defined within `group_vars`, `host_vars` and `vars`directories to meet your specific configuration.

The following table shows the variable files defined at ansible`s group and host levels

| Group/Host Variable file | Nodes affected |
|----|----|
| [`group_vars/all.yml`]({{ site.git_edit_address }}/group_vars/all.yml) | all nodes of cluster + gateway node + pimaster |
| [`group_vars/control.yml`]({{ site.git_edit_address }}/group_vars/control.yml) | control group: gateway node + pimaster |
| [`group_vars/k3s_cluster.yml`]({{ site.git_edit_address }}/group_vars/picluster.yml) | all nodes of the k3s cluster |
| [`group_vars/k3s_master.yml`]({{ site.git_edit_address }}/group_vars/k3s_master.yml) | K3s master nodes |
| [`host_vars/gateway.yml`]({{ site.git_edit_address }}/host_vars/gateway.yml) | gateway node specific variables|
{: .table }

The following table shows the variable files used for configuring the storage and the backup server

| Specific Variable File | Configuration |
|----|----|
| [`vars/dedicated_disks/local_storage.yml`]({{ site.git_edit_address }}/vars/dedicated_disks/local_storage.yml) | Configuration nodes local storage: Dedicated disks setup|
| [`vars/centralized_san/centralized_san_target.yml`]({{ site.git_edit_address }}/vars/centralized_san/centralized_san_target.yml) | Configuration iSCSI target  local storage and LUNs: Centralized SAN setup|
| [`vars/centralized_san/centralized_san_initiator.yml`]({{ site.git_edit_address }}/vars/centralized_san/centralized_san_initiator.yml) | Configuration iSCSI Initiator: Centralized SAN setup|
| [`vars/backup/s3_minio.yml`]({{ site.git_edit_address }}/vars/backup/s3_minio.yml) | Configuration S3 Minio server |
{: .table }


{{site.data.alerts.important}}: **About storage configuration**

Ansible Playbook used for doing the basic OS configuration (`setup_picluster.yml`) is able to configure two different storage setups (dedicated disks or centralized SAN) depending on the value of the variable `centralized_san` located in [`group_vars/all.yml`]({{ site.git_edit_address }}/group_vars/all.yml). If `centralized_san` is `false` (default value) dedicated disk setup will be applied, otherwise centralized san setup will be configured.

- **Centralized SAN** setup assumes `gateway` node has a SSD disk attached (`/dev/sda`) that it is partitioned the first time the server is booted (part of the cloud-init configuration) reserving 30Gb for the root partition and the rest of available disk for hosting the LUNs

  Final `gateway` disk configuration is:

  - /dev/sda1: Boot partition
  - /dev/sda2: Root Filesystem
  - /dev/sda3: For being used for creating LUNS using LVM.
  
  <br>
  LVM configuration is done by `setup_picluster.yml` Ansible's playbook and the variables used in the configuration can be found in `vars/centralized_san/centralized_san_target.yml`: `storage_volumegroups` and `storage_volumes` variables. Sizes of the different LUNs can be tweaked to fit the size of the SSD Disk used. I used a 480GB disk so, I was able to create LUNs of 100GB for each of the nodes.

- **Dedicated disks** setup assumes that all cluster nodes (`node1-4`) have a SSD disk attached that it is partitioned the first time the server is booted (part of the cloud-init configuration) reserving 30Gb for the root partition and the rest of available disk for creating a logical volume (LVM) mounted as `/storage`

  Final `node1-4` disk configuration is:

  - /dev/sda1: Boot partition
  - /dev/sda2: Root filesystem
  - /dev/sda3: /storage partition
  
  <br>
  LVM configuration is done by `setup_picluster.yml` Ansible's playbook and the variables used in the configuration can be found in `vars/dedicated_disks/local_storage.yml`: `storage_volumegroups`, `storage_volumes`, `storage_filesystems` and `storage_mounts` variables. The default configuration assings all available space in sda3 to a new logical volume formatted with ext4 and mounted as `/storage`

{{site.data.alerts.end}}

## Installing the nodes

### Update Raspberry Pi firmware

Update firmware in all Raspberry-PIs following the procedure described [here](/docs/firmware/)

### Install gateway node

Install `gateway` Operating System on Rapberry PI.
   
The installation procedure followed is the described [here](/docs/ubuntu/) using cloud-init configuration files (`user-data` and `network-config`) for `gateway`, depending on the storage setup selected:

| Storage Configuration | User data    | Network configuration |
|--------------------| ------------- |-------------|
|  Dedicated Disks |[user-data]({{ site.git_edit_address }}/cloud-init/dedicated_disks/gateway/user-data) | [network-config]({{ site.git_edit_address }}/cloud-init/dedicated_disks/gateway/network-config)|
| Centralized SAN | [user-data]({{ site.git_edit_address }}/cloud-init/centralized_san/gateway/user-data) | [network-config]({{ site.git_edit_address }}/cloud-init/centralized_san/gateway/network-config) |
{: .table }

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

Install `node1-4` Operating System on Raspberry Pi

Follow the installation procedure indicated [here](/docs/ubuntu/) using the corresponding cloud-init configuration files (`user-data` and `network-config`) depending on the storage setup selected. Since DHCP is used there is no need to change default `/boot/network-config` file located in the ubuntu image.

| Storage Architeture | node1   | node2 | node3 | node 4 |
|-----------| ------- |-------|-------|--------|
| Dedicated Disks | [user-data]({{ site.git_edit_address }}/cloud-init/dedicated_disks/node1/user-data) | [user-data]({{ site.git_edit_address }}/cloud-init/dedicated_disks/node2/user-data)| [user-data]({{ site.git_edit_address }}/cloud-init/dedicated_disks/node3/user-data) | [user-data]({{ site.git_edit_address }}/cloud-init/dedicated_disks/node4/user-data) |
| Centralized SAN | [user-data]({{ site.git_edit_address }}/cloud-init/centralized_san/node1/user-data) | [user-data]({{ site.git_edit_address }}/cloud-init/centralized_san/node2/user-data)| [user-data]({{ site.git_edit_address }}/cloud-init/centralized_san/node3/user-data) | [user-data]({{ site.git_edit_address }}/cloud-init/centralized_san/node4/user-data) |
{: .table }

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

### Configuring backup server (S3) and OS level backup

Configure backup server (Playbook assumes S3 server is installed in `node1`) and automated backup tasks at OS level with restic in all nodes (`node1-node4` and `gateway`) running the playbook:

```shell
ansible-playbook backup_configuration.yml
```

{{site.data.alerts.note}}

List of directories to be backed up by restic in each node can be found in variables file `var/all.yml`: `restic_backups_dirs`

Variable `restic_clean_service` which configure and schedule restic's purging activities need to be set to "true" only in one of the nodes. Defaul configuration set `gateway` as the node for executing these tasks.

{{site.data.alerts.end}}

## K3S

### K3S Installation

To install K3S cluster execute the playbook:

```shell
ansible-playbook k3s_install.yml
```

### K3S basic services deployment

To deploy and configure basic services (metallb, traefik, certmanager, longhorn, EFK, Prometheus, Velero) run the playbook:

```shell
ansible-playbook k3s_deploy.yml
```

Different ansible tags can be used to select the componentes to deploy:

```shell
ansible-playbook k3s_deploy.yml --tags <ansible_tag>
```

| Ansible Tag | Component to configure/deploy |
|---|---|
| `metallb` | Metal LB |
| `traefik` | Traefik | 
| `certmanager` | Cert-manager |
| `longhorn` | Longhorn |
| `logging` | EFK Stack |
| `monitoring` | Prometheus Stack |
| `backup` | Velero |
{: .table }

### K3s Cluster reset

If you mess anything up in your Kubernetes cluster, and want to start fresh, the K3s Ansible playbook includes a reset playbook, that you can use to remove the installation of K3S:

```shell
ansible-playbook k3s_reset.yml
```

{{site.data.alerts.note}}

Reset can be used as well whenever we want to test the latest stable software version of the components of the cluster (K3S, Cert-manager, Longhorn, EFK, Prometheus, etc.).
After a cluster reset:
  - Execution of `k3s_install.yml` playbook will install latest stable version of K3S
  - Execution of `k3s_deploy.yml` playbook will install latest Helm Chart version of the different components.

{{site.data.alerts.end}}

## Shutting down the Raspeberry Pi Cluster

To automatically shut down the Raspberry PI cluster, Ansible can be used.

For shutting down the cluster run this command:

```shell
ansible-playbook shutdown.yml
```

This playbook will connect to each Raspberry PI in the cluster (including `gateway` node) and execute the command `sudo shutdown -h 1m`, commanding the raspberry-pi to shutdown in 1 minute.

After a couple of minutes all raspberry pi will be shutdown. You can notice that when the Switch ethernet ports LEDs are off. Then it is safe to unplug the Raspberry PIs.

## Updating Ubuntu packages

To automatically update Ubuntu OS packages run the following playbook:

```shell
ansible-playbook update.yml
```

This playbook automatically updates OS packages to the latest stable version and it performs a system reboot if needed. 