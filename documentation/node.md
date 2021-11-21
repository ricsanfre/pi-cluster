# Node Configuration

4 Raspeberry Pi (4GB), `node1`, `node2`, `node3` and `node4`, will be used as nodes for the Kubernetes cluster.
`node1` will be acting as **master node** and `node2/3/4` as **worker nodes**


#### Table of contents

1. [Hardware](#hardware)
2. [Network Configuration](#network-configuration) 
3. [Ubuntu boot from USB](#unbuntu-boot-from-usb)
4. [Initial OS Configuration](#ubuntu-os-initital-configuration)
5. [NTP Server Configuration](#ntp-server-configuration)
6. [Storage configuration](#storage-configuration)
7. [iSCSI Configuration](#iscsi-configuration)

## Hardware

`node1-4` are based on a Raspberry Pi 4B 4GB booting from a SSD Disk.
A Kingston A400 480GB SSD Disk and a USB3.0 to SATA adapter will be used connected to `node1`. Kingston A400 240GB SSD Disk and USB3.0 to SATA adapter will be used connected to `node2-node4`.

## Storage configuration

SSD Disk will be partitioned in boot time reserving 30 GB for root filesystem (OS installation) and the rest will be used for creating a logical volumes (LVM) mounted as `/storage`. This will provide local storage capacity in each node of the cluster, used mainly by Kuberentes distributed storage solution and by backup solution.

cloud-init configuration `user-data` includes commands to be executed once in boot time, executing a command that changes partition table and creates a new partition before the automatic growth of root partitions to fill the entire disk happens.

> NOTE: As a reference of how cloud images partitions grow in boot time check this blog [entry](https://elastisys.com/how-do-virtual-images-grow/)

Command executed in boot time is

    sgdisk /dev/sda -e .g -n=0:30G:0 -t 0:8e00

This command:
  - First convert MBR partition to GPT (-g option)
  - Second moves the GPT backup block to the end of the disk  (-e option)
  - then creates a new partition starting 30GiB into the disk filling the rest of the disk (-n=0:10G:0 option)
  - And labels it as an LVM partition (-t option)

## Network Configuration

Only ethernet interface (eth0) will be used connected to the lan switch. Interface will be configured through  DHCP using `gateway` DHCP server.


## Unbuntu boot from USB

Follow the procedure indicated [here](./installing_ubuntu.md) but updating cloud-init configuration files (`user-data`) with the `node1-4` OS initial configuration. Since DHCP is used no need to change default `/boot/network-config` file.


| node1   | node2 | node3 | node 4 |
| ------- |-------|-------|--------|
| [user-data](../cloud-init-ubuntu-images/node1/user-data) | [user-data](../cloud-init-ubuntu-images/node2/user-data)| [user-data](../cloud-init-ubuntu-images/node3/user-data) | [user-data](../cloud-init-ubuntu-images/node4/user-data) |


## Ubuntu OS Initital Configuration

After booting from the USB3.0 external storage for the first time, the Raspberry Pi will have SSH connectivity and it will be ready to be automatically configured from the ansible control node `pimaster`.

Initial configuration tasks includes removal of snap package, and Raspberry PI specific configurations tasks such as: intallation of fake hardware clock, installation of some utility packages scripts and change default GPU Memory plit configuration. See instructions [here](./basic_os_configuration.md).

For automating all this initial configuration tasks, ansible role **basic_setup** has been developed.

## NTP Server Configuration

`node1-node4` will be configured as NTP clients using NTP server running in `gateway`
See NTP Configuration instructions [here](document/gateway.md#ntp-server-configuration)

NTP configuration in `node1-node4` has been automated using ansible role **ricsanfre.ntp**

## Storage configuration

For `node1-node4` the partition created in boot time using most of the disk space (reserving just 30GB for the root filesystem),`/dev/sda2`, is added to a LVM Volume Group and create a unique Logical Volume which is formatted (ext4) and mounted as `/storage`.

LVM partition and formatting tasks have been automated with Ansible developing the ansible role: **ricsanfre.storage** for managing LVM.
` 

## iSCSI configuration

Open-iscsi is used by Longhorn as a mechanism to expose Volumes within Kuberentes cluster. All nodes of the cluster need to be configured as iSCSI initiators, When configurin iSCSI initiator, authentication default parameters should not be included in `iscsid.conf` file and per target authentication parameters need to be specified because Longhorn local iSCSI target is not using any authentication.

iSCSI initiator configuration in `node1-node4` have been automated with Ansible developing the ansible role: **ricsanfre.iscsi_initiator**.