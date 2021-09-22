# Node Configuration

4 Raspeberry Pi (4GB), `node1`, `node2`, `node3` and `node4`, will be used as nodes for the Kubernetes cluster.
`node1` will be acting as **master node** and `node2/3/4` as **worker nodes**


#### Table of contents

1. [Hardware](#hardware)
2. [Network Configuration](#network-configuration) 
3. [Ubuntu boot from USB](#unbuntu-boot-from-usb)
4. [Initial OS Configuration](#ubuntu-os-initital-configuration)
5. [NTP Server Configuration](#ntp-server-configuration)
6. [iSCSI Configuration](#iscsi-configuration)

## Hardware

`node1-4` are based on a Raspberry Pi 4B 4GB boot from a USB Flash Disk avoiding the use of SDCards.
A Samsung USB 3.1 32 GB Fit Plus Flash Disk will be used connected to one of the USB 3.0 ports of the Raspberry Pi.

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

## iSCSI configuration

`node1-node4` are configured as iSCSI Initiator to use iSCSI volumes exposed by `gateway`

iSCSI configuration in `node1-node4`and iSCSI LUN mount and format tasks have been automated with Ansible developing a couple of ansible roles: **ricsanfre.storage** for managing LVM and **ricsanfre.iscsi_initiator** for configuring a iSCSI initiator.

Further details about iSCSI configurations and step-by-step manual instructions are defined [here](./san_installation.md).

Each node add the iSCSI LUN exposed by `gateway` to a LVM Volume Group and create a unique Logical Volume which formatted (ext4) and mounted as `/storage`.

< NOTE: Open-iscsi is used by Longhorn as a mechanism to expose Volumes within Kuberentes cluster. Authentication default parameters should not be included in `iscsid.conf` file and per target authentication parameters need to be specified because Longhorn local iSCSI target is not using any authentication.