---
title: Cluster Nodes
permalink: /docs/node/
description: How to configure the nodes of our Pi Kubernetes Cluster. Ubuntu cloud-init configuration files, and basic OS configuration.
last_modified_at: "03-02-2024"
---

A K3S cluster is composed of:

- 1 **external services node** (`node1`), running on Raspberry Pi 4B (4GB)
- 3 **master nodes** (`node2`, `node3`, `node4`), running on Raspberry Pi 4B (4GB)
- 5 **worker nodes**:
  - `node5`and `node6` running on Raspberry Pi 4B (8GB)
  - `node-hp-1`,`node-hp-2` and `node-hp-3` running on HP Elitedesk 800 G3 (16GB)


## Raspberry PI nodes

### Storage Configuration

`node1-6` are based on a Raspberry Pi 4B booting from a USB Flash Disk or SSD Disk depending on storage architectural option selected.

- **Dedicated disks storage architecture**: Kingston A400 480GB SSD Disk and a USB3.0 to SATA adapter will be used connected to `node1`. Kingston A400 240GB SSD Disk and USB3.0 to SATA adapter will be used connected to `node2-node6`.

  SSD disk is partitioned to separate  root filesystem (mountpoit '/') from data storage destinated for Longhorn data (mountpoint '/storage')

- **Centralized SAN architecture**: A Samsung USB 3.1 32 GB Fit Plus Flash Disk will be used connected to one of the USB 3.0 ports of the Raspberry Pi.

### Network Configuration

Only ethernet interface (eth0) will be used connected to the lan switch. Wifi interface won't be used. Ethernet interface will be configured through DHCP using `gateway` DHCP server.

### Unbuntu OS Installation

Ubuntu can be installed on Raspbery PI using a preconfigurad cloud image that need to be copied to SDCard or USB Flashdisk/SSD.

Raspberry Pis will be configured to boot Ubuntu OS from USB conected disk (Flash Disk or SSD disk). The initial Ubuntu 22.04 LTS configuration on a Raspberry Pi 4 will be automated using cloud-init.

In order to enable boot from USB, Raspberry PI firmware might need to be updated. Follow the producedure indicated in ["Raspberry PI - Firmware Update"](/docs/firmware/).

Follow the procedure indicated in ["Ubuntu OS Installation - Raspberry PI"](/docs/ubuntu/rpi/) using cloud-init configuration files (`user-data` and `network-config`) described in the table below.

`user-data` file to be used depends on the storage architectural option selected. Since DHCP is used to configure network interfaces, it is not needed to change default `/boot/network-config` file.


| Dedicated Disks | Centralized SAN  |
|-----------------| ---------------- |
| [user-data]({{ site.git_edit_address }}/metal/rpi/cloud-init/nodes/user-data-SSD-partition) | [user-data]({{ site.git_edit_address }}/metal/rpi/cloud-init/nodes/user-data)| 
{: .table .table-white .border-dark }

{{site.data.alerts.note}}

In user-data file `hostname` field need to be changed for each node (node1-node6).

{{site.data.alerts.end}}


#### cloud-init partitioning configuration (SSD Disks)

By default, during first boot, cloud image partitions grow to fill the whole capacity of the SDCard/USB Flash Disk or SSD disk). So root partition (/) will grow to fill the full capacity of the disk.

{{site.data.alerts.note}}

As a reference of how cloud images partitions grow in boot time check this blog [entry](https://elastisys.com/how-do-virtual-images-grow/).

{{site.data.alerts.end}}

cloud-init partition SSD Disk will be partitioned during firt boot. cloud-init will be configured to reserve 30 GB for root filesystem (OS installation) and the rest will be used for creating a Linux partition (ext4) mounted as `/storage`. This will provide local storage capacity in each node of the cluster, used mainly by Kuberentes distributed storage solution and by backup solution.


`cloud-init` configuration (`user-data` file) includes commands to be executed once in boot time changing partition table and creating a new partition before the automatic growth of root partitions to fill the entire disk happens.


```yml
bootcmd:
  # Create second Linux partition. Leaving 30GB for root partition
  # sgdisk /dev/sda -g -e -n=0:30G:0 -t 0:8300
  # First convert MBR partition to GPT (-g option)
  # Second moves the GPT backup block to the end of the disk where it belongs (-e option)
  # Then creates a new partition starting 10GiB into the disk filling the rest of the disk (-n=0:10G:0 option)
  # And labels it as a Linux partition (-t option)
  - [cloud-init-per, once, addpartition, sgdisk, /dev/sda, "-g", "-e", "-n=0:30G:0", -t, "0:8300"]

runcmd:
  # reload partition table
  - "sudo partprobe /dev/sda"
  # configure new partition
  - "mkfs.ext4 /dev/sda3"
  - "e2label /dev/sda3 DATA"
  - "mkdir -p /storage"
  - "mount -t ext4 /dev/sda3 /storage"
  - "echo LABEL=DATA /storage ext4 defaults 0 0 | sudo tee -a /etc/fstab"
```

Command executed in boot time (cloud-init's bootcmd section) is:

```shell
sgdisk /dev/sda -e .g -n=0:30G:0 -t 0:8300
```

This command:
  - First convert MBR partition to GPT (-g option)
  - Second moves the GPT backup block to the end of the disk  (-e option)
  - then creates a new partition starting 30GiB into the disk filling the rest of the disk (-n=0:10G:0 option)
  - And labels it as an Linux partition (-t option)

For `node1-node6`, the new partition created in boot time, `/dev/sda3`, uses most of the disk space leaving just 30GB for the root filesystem, `/dev/sda2`.

Then cloud-init executes the commands (cloud-init's runcmd section) to format (`ext4`) and mounted the new partition as `/storage`.


## x86 mini PC nodes


### Storage Configuration

`hp-node1-3` are based on HP EliteDesk 800 G3 mini PCs. This model, is able to have two types of integrated disk:

- 2.5 SSD SATA disk
- NvME disk via M2.PCIe interface

Partitioning to be performed on the servers is the following:

For nodes having only SATA disk (hp-node-1)

| Partition | Description  | Mount Point | Format | Size |
|---| --- | --- | --- | --- |
| /dev/sda1 |  EFI system Partition (ESP) | /boot/efi | fat32 | 1075 MB |
| /dev/sda2 | Boot partition  | /boot | ext4 | 2GB |
| /dev/sda3 | LVM Volume Group: ubuntu-vg| | Rest of space available |
{: .table .table-white .border-dark }

For nodes having NvME disks (hp-node-2 and hp-node-3)

| Partition | Description  | Mount Point | Format | Size |
|---| --- | --- | --- | --- |
| /dev/nvme0n1p1 |  EFI system Partition (ESP) | /boot/efi | fat32 | 1075 MB |
| /dev/nvme0n1p2 | Boot partition  | /boot | ext4 | 2GB |
| /dev/nvme0n1p3 | LVM Volume Group: ubuntu-vg| | Rest of space available |
{: .table .table-white .border-dark }


LVM logical volumes configuration is the same in both cases:

| LVM Logical Volueme | Description  | Mount Point | Format | Size |
|---| --- | --- | --- | --- |
| ubuntu-lv |  Root filesystem | / | ext4 | 30 GB |
| lv-data | Storage filesystem | /storage | ext4 | Rest of space available in ubuntu-vg|
{: .table .table-white .border-dark }

This partitioning scheme in installer GUI, will looks like

![partition](/assets/img/ubuntu-partitioning-schema.png)


### Network Configuration

Ethernet interface (eth0) will be used connected to the lan switch. Ethernet interface will be configured through DHCP using `gateway` DHCP server.

### Unbuntu OS Installation

Since version 20.04, the server installer supports automated unattended installation mode ([autoinstallation mode](https://ubuntu.com/server/docs/install/autoinstall)).

The autoinstall config is provided via cloud-init configuration file:

```yml
#cloud-config
autoinstall:
  version: 1
  ...
```

{{site.data.alerts.note}}

When any system is installed using the server installer, an autoinstall file for repeating the install is created at /var/log/installer/autoinstall-user-data.

{{site.data.alerts.end}}


Server autoinstallation can be done through network using PXE ([Preboot eXecution Environment](https://en.wikipedia.org/wiki/Preboot_Execution_Environment)). x86-64 systems boot in either UEFI or legacy (“BIOS”) mode (many systems can be configured to boot in either mode). The precise details depend on the system firmware, but both modes supports the PXE specification, which allows the provisioning of a bootloader over the network.

See details in Ubuntu's documentation: ["Ubuntu Advance Installation - Netbooting the server installer in amd64"](https://ubuntu.com/server/docs/install/netboot-amd64)

A PXE server need to be deployed in the Cluster for automatically autoinstall Ubuntu 22.04 in x86 nodes. To install PXE server follow the producedure indicated in ["PXE Server"](/docs/pxe-server/).

Follow the procedure indicated in ["Ubuntu OS Installation - x86 (PXE Server)"](/docs/ubuntu/x86/) to install Ubuntu on HP Elitedesk 800 G3 mini PCs.


#### cloud-init autoinstall configuration

For the x86 servers the cloud-init autoinstall configuration to be served from PXE server are similar to the sample provided here:


```yml
#cloud-config
autoinstall:
  version: 1
  keyboard:
    layout: es
  ssh:
    allow-pw: false
    install-server: true
  storage:
    config:
    - ptable: gpt
      path: /dev/sda
      wipe: superblock-recursive
      preserve: false
      name: ''
      grub_device: false
      type: disk
      id: disk-sda
    - device: disk-sda
      size: 1075M
      wipe: superblock
      flag: boot
      number: 1
      preserve: false
      grub_device: true
      path: /dev/sda1
      type: partition
      id: partition-0
    - fstype: fat32
      volume: partition-0
      preserve: false
      type: format
      id: format-0
    - device: disk-sda
      size: 2G
      wipe: superblock
      number: 2
      preserve: false
      grub_device: false
      path: /dev/sda2
      type: partition
      id: partition-1
    - fstype: ext4
      volume: partition-1
      preserve: false
      type: format
      id: format-1
    - device: disk-sda
      size: -1
      wipe: superblock
      number: 3
      preserve: false
      grub_device: false
      path: /dev/sda3
      type: partition
      id: partition-2
    - name: ubuntu-vg
      devices:
      - partition-2
      preserve: false
      type: lvm_volgroup
      id: lvm_volgroup-0
    - name: ubuntu-lv
      volgroup: lvm_volgroup-0
      size: 100G
      wipe: superblock
      preserve: false
      path: /dev/ubuntu-vg/ubuntu-lv
      type: lvm_partition
      id: lvm_partition-0
    - fstype: ext4
      volume: lvm_partition-0
      preserve: false
      type: format
      id: format-3
    - path: /
      device: format-3
      type: mount
      id: mount-3
    - name: lv-data
      volgroup: lvm_volgroup-0
      size: -1
      wipe: superblock
      preserve: false
      path: /dev/ubuntu-vg/lv-data
      type: lvm_partition
      id: lvm_partition-1
    - fstype: ext4
      volume: lvm_partition-1
      preserve: false
      type: format
      id: format-4
    - path: /storage
      device: format-4
      type: mount
      id: mount-4
    - path: /boot
      device: format-1
      type: mount
      id: mount-1
    - path: /boot/efi
      device: format-0
      type: mount
      id: mount-0
  user-data:
    # Set TimeZone and Locale
    timezone: UTC
    locale: es_ES.UTF-8

    # Hostname
    hostname: server_name

    # cloud-init not managing hosts file. only hostname is added
    manage_etc_hosts: localhost

    users:
      - name: ricsanfre
        primary_group: users
        groups: [adm, admin]
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: true
        ssh_authorized_keys:
          - ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAusTXKfFoy6p3G4QAHvqoBK+9Vn2+cx2G5AY89WmjMikmeTG9KUseOCIAx22BCrFTNryMZ0oLx4u3M+Ibm1nX76R3Gs4b+gBsgf0TFENzztST++n9/bHYWeMVXddeV9RFbvPnQZv/TfLfPUejIMjFt26JCfhZdw3Ukpx9FKYhFDxr2jG9hXzCY9Ja2IkVwHuBcO4gvWV5xtI1nS/LvMw44Okmlpqos/ETjkd12PLCxZU6GQDslUgGZGuWsvOKbf51sR+cvBppEAG3ujIDySZkVhXqH1SSaGQbxF0pO6N5d4PWus0xsafy5z1AJdTeXZdBXPVvUSNVOUw8lbL+RTWI2Q== ricardo@dol-guldur
          - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDsVSvxBitgaOiqeX4foCfhIe4yZj+OOaWP+wFuoUOBCZMWQ3cW188nSyXhXKfwYK50oo44O6UVEb2GZiU9bLOoy1fjfiGMOnmp3AUVG+e6Vh5aXOeLCEKKxV3I8LjMXr4ack6vtOqOVFBGFSN0ThaRTZwKpoxQ+pEzh+Q4cMJTXBHXYH0eP7WEuQlPIM/hmhGa4kIw/A92Rm0ZlF2H6L2QzxdLV/2LmnLAkt9C+6tH62hepcMCIQFPvHVUqj93hpmNm9MQI4hM7uK5qyH8wGi3nmPuX311km3hkd5O6XT5KNZq9Nk1HTC2GHqYzwha/cAka5pRUfZmWkJrEuV3sNAl ansible@pimaster
```


{{site.data.alerts.note}}

PXE server and nodes autoinstall configuration is automatically created by Ansible for all nodes in group 'x86' (inventory file)

{{site.data.alerts.end}}

## Ubuntu OS configuration

After booting for the first time, cluster nodes will have SSH connectivity and it will be ready to be automatically configured from the ansible control node `pimaster`.

### Basic configuration

Initial configuration tasks includes removal of snap package, and Raspberry PI specific configurations tasks such as: intallation of fake hardware clock, installation of some utility packages scripts and change default GPU Memory Split configuration. See instructions in ["Ubuntu OS initial configurations"](/docs/os-basic/).

For automating all this initial configuration tasks, ansible role **basic_setup** has been developed.

### NTP Server Configuration

Cluster nodes will be configured as NTP clients using NTP server running in `gateway`
See ["NTP Configuration instructions"](/docs/gateway/#ntp-server-configuration).

NTP configuration in cluster nodes has been automated using ansible role **ricsanfre.ntp**

### iSCSI configuration. 

#### Raspberry Pi Dedicated Disks and x86 nodes

Open-iscsi is used by Longhorn as a mechanism to expose Volumes within Kuberentes cluster. All nodes of the cluster need to be configured as iSCSI initiators, When configurin iSCSI initiator, authentication default parameters should not be included in `iscsid.conf` file and per target authentication parameters need to be specified because Longhorn local iSCSI target is not using any authentication.

iSCSI initiator configuration in cluster nodes has been automated with Ansible developing the ansible role: **ricsanfre.iscsi_initiator**.

#### Raspberry PI Centralized SAN

In case of Raspberry PI nodes not using dedicated disks,`node1-node6` are configured as iSCSI Initiator to use iSCSI volumes exposed by `gateway`

iSCSI configuration in `node1-node6`and iSCSI LUN mount and format tasks have been automated with Ansible developing a couple of ansible roles: **ricsanfre.storage** for managing LVM and **ricsanfre.iscsi_initiator** for configuring a iSCSI initiator.

Further details about iSCSI configurations and step-by-step manual instructions are defined in ["Cluster SAN installation"](/docs/san/).

Each node add the iSCSI LUN exposed by `gateway` to a LVM Volume Group and create a unique Logical Volume which formatted (ext4) and mounted as `/storage`.

Specific `node1-node6` ansible variables to be used by these roles are stored in [`ansible/vars/centralized_san/centralized_san_initiator.yml`]({{ site.git_edit_address }}/ansible/vars/centralized_san/centralized_san_initiator.yml)

{{site.data.alerts.important}}

`open-iscsi` is used by Longhorn as a mechanism to expose Volumes within Kuberentes cluster. Authentication default parameters should not be included in `iscsid.conf` file and per target authentication parameters need to be specified because Longhorn local iSCSI target is not using any authentication.

{{site.data.alerts.end}}
