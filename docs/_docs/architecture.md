---
title: Lab Architecture
permalink: /docs/architecture/
redirect_from: /docs/architecture.md
description: Homelab architecture of our Raspberry Pi Kuberentes cluster. Cluster nodes, firewall, and Ansible control node. Networking and cluster storage design.
last_modified_at: "25-02-2022"
---


The home lab I am building is shown in the following picture

![Cluster-lab](/assets/img/RaspberryPiCluster_architecture.png)


## Cluster Nodes

For building the K3S cluster, using bare metal servers instead of virtual machines, ARM-based low cost SBC (Single Board Computer), like Raspeberry Pi-4 are used. Raspberry PI 4 is used for each node of the K3S cluster and for building a cluster firewall. 

### K3S Nodes

A K3S cluster composed of 4 Raspberry Pi 4 (4GB), one master node `node1` and three worker nodes `node2`, `node3` and `node4` connected to a dedicated LAN switch.
 
### Firewall

A Raspberry PI 4 (2GB), `gateway` will be used as Router/Firewall to isolate lab network from my home network,. It will also provide networking services to my lab network: Internet Access, DNS, NTP and DHCP services.

### Control Node

As Ansible control node, `pimaster`, a VM running on my laptop will be used. Its required SSH connectivity to cluster nodes will be routed through the cluster firewall, `gateway`.

## Networking

A 8 GE ports LAN switch, NetGear GS108-300PES, supporting VLAN configuration and remote management, is used to provide connectivity to all Raspberry Pis (`gateway` and `node1-node4`), using Raspeberry PI Gigabit Ethernet port.

`gateway` will be also connected to my home network using its WIFI interface in order to route and filter traffic comming in/out the cluster.

## Cluster Storage

Two different storage alternatives can be appied:

- Dedicated Disks: SSD disks for each cluster node. 4 SSD disk, and their SATA to USB adpaters, are required
- Centralized SAN: SAN Storage configuration using only one SSD disk is required

![cluster-HW-storage](/assets/img/RaspberryPiCluster_HW_storage.png)


### Dedicated Disks

`gateway` uses local storage attached directly to USB 3.0 port (Fash Disk) for hosting the OS, avoiding the use of less reliable SDCards.

For having better cluster performance `node1-node4` will use SSDs attached to USB 3.0 port. SSD disk will be used to host OS (boot from USB) and to provide the additional storage required per node for deploying the Kubernetes distributed storage solution (Ceph or Longhorn).

![pi-cluster-HW-2.0](/assets/img/pi-cluster-2.0.png)


### Centralized SAN

A cheaper alternative architecture, instead of using dedicated SSD disks for each cluster node, one single SSD disk can be used for configuring a SAN service.

Each cluster node `node1-node4` can use local storage attached directly to USB 3.0 port (USB Flash Disk) for hosting the OS, avoiding the use of less reliable SDCards.
 
As additional storage (required by distributed storage solution), iSCSI SAN can be deployed instead of attaching an additional USB Flash Disks to each of the nodes.

A SAN (Storage Access Network) can be configured using `gateway` as iSCSI Storage Server, providing additional storage (LUNs) to `node1-node4`.

As storage device, a SSD disk was attached to `gateway` node. This SSD disk was used as well to host the OS.

![pi-cluster-HW-1.0](/assets/img/pi-cluster.png)

This alternative setup is worth it from educational point of view, to test the different storage options for RaspberryPI and to learn about iSCSI configuration and deployment on bare-metal environments. As well it can be used as a cheaper solution for deploying centralized storage solution.

See [SAN configuration document](/docs/san/) further details about the configuration of SAN using a Raspeberry PIs, `gateway`, as iSCSI Target exposing LUNs to cluster nodes.

