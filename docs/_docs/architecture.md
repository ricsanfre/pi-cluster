---
title: Lab Architecture
permalink: /docs/architecture/
description: Homelab architecture of our Pi Kuberentes cluster. Cluster nodes, firewall, and Ansible control node. Networking and cluster storage design.
last_modified_at: "10-06-2023"
---


The home lab I am building is shown in the following picture

![Cluster-lab](/assets/img/RaspberryPiCluster_architecture.png)


## Cluster Nodes

For building the K3S cluster, using bare metal servers instead of virtual machines, low cost servers are being used:
- ARM-based SBC (Single Board Computer): 
  - [Raspberry Pi 4B](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/)
    CPU: ARM Cortex-A72. Quadcore 1.5GHz
    RAM: 2GB/4GB/8GB
- x86-based old refurbished mini PC
  - [HP Elitedesk 800 G3 Desktop mini PC](https://support.hp.com/us-en/product/hp-elitedesk-800-65w-g3-desktop-mini-pc/15497277/manuals)
    CPU: Intel i5 6500T. Quadcore 2.5 GHz
    RAM: 16 GB

{{site.data.alerts.note}}

This project initilly was built using only Raspberry PI nodes, but due to Raspberry shortage during last 2 years which makes impossible to buy them at reasonable prices, I decided to look for alternatives to be able to scale up my cluster.

Old x86 refurbished mini PCs, with Intel i5 processors was the answer. These mini PCs provide similar performance to RaspberryPi's ARM Cortex-A72, but its memory can be expanded up to 32GB of RAM (Raspberry PI higher model only supports 8GB RAM). As a drawback power consumption of those mini PCs are higher that Raspberry PIs.

The overall price of a mini PC, intel i5 + 8 GB RAM + 256 GB SSD disk + power supply, ([aprox 130 €](https://www.amazon.es/HP-EliteDesk-800-G3-reacondicionado/dp/B09TL2N2M8/)) is cheaper than the overal cost of building a cluster node using a Rasbperry PI: cost of Raspberry PI 8GB (100€) + Power Adapter (aprox 10 €) + SSD Disk ([aprox 20 €](https://www.amazon.es/Kingston-SSD-A400-Disco-s%C3%B3lido/dp/B01N5IB20Q)) + USB3.0 to SATA converter ([aprox 20€](https://www.amazon.es/Startech-USB3S2SAT3CB-Adaptador-3-0-2-5-negro/dp/B00HJZJI84))

{{site.data.alerts.end}}
 

### K3S Nodes

A K3S cluster composed of:
- One master node (`node1`), running on Raspberry Pi 4B (4GB)
- Six worker nodes:
  - `node2`, `node3` , `node4` running on Raspberry Pi 4B (4GB)
  - `node5` running on Raspberry Pi 4B (8GB)
  - `node-hp-1` and `node-hp-2` running on HP Elitedesk 800 G3 (16GB)
 
### Firewall

A Raspberry PI 4B-2GB, `gateway`, is used as Router/Firewall to isolate lab network from my home network. It also provides networking services to my lab network: Internet Access, DNS, NTP and DHCP services.

### Control Node

As Ansible control node, `pimaster`, a VM running on my laptop will be used. Its required SSH connectivity to cluster nodes will be routed through the cluster firewall, `gateway`.

## Networking

A 8 GE ports LAN switch, NetGear GS108-300PES, supporting VLAN configuration and remote management, is used to provide connectivity to all nodes (Raspberry Pis and x86 mini PCs). All nodes are connected to the switch with Cat6 eth cables using their Gigabit Ethernet port.

`gateway`, cluster firewall/router, is also connected to my home network using its WIFI interface in order to route and filter traffic comming in/out the cluster.

## Raspberry PI Storage

x86 mini PCs has their own integrated disk (SSD disk or NVME). For Raspberry PIs different storage alternatives can be applied:

- Dedicated Disks: Each node has its SSD disks attached to one of its USB 3.0 ports. SSD disk + SATA to USB 3.0 adapter is needed for each node.
- Centralized SAN: Each node has Flash Disk (USB3.0) for running OS and additional storage capacity is provide via iSCSI from a SAN (Storage Area Network). One of the cluster nodes, gateway, is configured as SAN server, and it needs to have SSD disk attached to its USB3.0 port.

![cluster-HW-storage](/assets/img/RaspberryPiCluster_HW_storage.png)


### Dedicated Disks

`gateway` uses local storage attached directly to USB 3.0 port (Flash Disk) for hosting the OS, avoiding the use of less reliable SDCards.

For having better cluster performance `node1-node5` will use SSDs attached to USB 3.0 port. SSD disk will be used to host OS (boot from USB) and to provide the additional storage required per node for deploying the Kubernetes distributed storage solution (Ceph or Longhorn).

![pi-cluster-HW-2.0](/assets/img/pi-cluster-2.0.png)


### Centralized SAN

A cheaper alternative architecture, instead of using dedicated SSD disks for each cluster node, one single SSD disk can be used for configuring a SAN service.

Each cluster node `node1-node5` can use local storage attached directly to USB 3.0 port (USB Flash Disk) for hosting the OS, avoiding the use of less reliable SDCards.
 
As additional storage (required by distributed storage solution), iSCSI SAN can be deployed instead of attaching an additional USB Flash Disks to each of the nodes.

A SAN (Storage Access Network) can be configured using `gateway` as iSCSI Storage Server, providing additional storage (LUNs) to `node1-node5`.

As storage device, a SSD disk was attached to `gateway` node. This SSD disk was used as well to host the OS.

![pi-cluster-HW-1.0](/assets/img/pi-cluster.png)

This alternative setup is worth it from educational point of view, to test the different storage options for RaspberryPI and to learn about iSCSI configuration and deployment on bare-metal environments. As well it can be used as a cheaper solution for deploying centralized storage solution.

See [SAN configuration document](/docs/san/) further details about the configuration of SAN using a Raspeberry PIs, `gateway`, as iSCSI Target exposing LUNs to cluster nodes.

