# Lab Architecture and Hardware used

## Lab Architecture

The home lab I am building is shown in the following picture

![Cluster-lab](images/RaspberryPiCluster_architecture.png)

A K3S cluster composed of 4 Raspberry Pi 4 (4GB), one master node `node1` and three worker nodes `node2`, `node3` and `node4` connected to a dedicated LAN switch.

A Raspberry PI 4 (2GB), `gateway` will be used as Router/Firewall to isolate lab network from my home network,. It will also provide networking services to my lab network: Internet Access, DNS, NTP and DHCP services. 

As Ansible control node, `pimaster`, a VM running on my laptop will be used. Required SSH connectivity from control node to cluster nodes will be routed through `gateway`.

## Networking

A 8 GE ports LAN switch, NetGear GS108-300PES, supporting VLAN configuration and remote management, is used to provide connectivity to all Raspberry Pis (`gateway` and `node1-node4`), using Raspeberry PI Gigabit Ethernet port.

`gateway` will be also connected to my home network using its WIFI interface in order to route and filter traffic comming in/out the cluster.

## Storage: Two architecture alternatives

Two different storage alternatives:

- Dedicated Disks: SSD disks for each cluster node. 4 SSD disk, and their SATA to USB adpaters, are required
- Centralized SAN: SAN Storage configuration using only one SSD disk is required

![cluster-HW-storage](images/RaspberryPiCluster_HW_storage.png)


### Dedicated Disks

`gateway` uses local storage attached directly to USB 3.0 port (Fash Disk) for hosting the OS, avoiding the use of less reliable SDCards.

For having better cluster performance `node1-node4` will use SSDs attached to USB 3.0 port. SSD disk will be used to host OS (boot from USB) and to provide the additional storage required per node for deploying the Kubernetes distributed storage solution (Ceph or Longhorn).

### Centralized SAN

A cheaper alternative architecture, instead of using dedicated SSD disks for each cluster node, one single SSD disk can be used for configuring a SAN service.

Each cluster node `node1-node4` can use local storage attached directly to USB 3.0 port (USB Flash Disk) for hosting the OS, avoiding the use of less reliable SDCards.
 
As additional storage (required by distributed storage solution), iSCSI SAN was deployed instead of attaching an additional USB Flash Disks to each of the nodes.

A SAN (Storage Access Network) was configured using `gateway` as iSCSI Storage Server, providing additional storage (LUNs) to `node1-node4`.

As storage device, a SSD disk was attached to `gateway` node. This SSD disk was used as well to host the OS.

This alternative setup is worth it from educational point of view, to test the different storage options for RaspberryPI and to learn about iSCSI configuration and deployment on bare-metal environments. As well can be used a a cheaper solution for deploying centralized storage solution.

After testing the performance of the different storage options for the Raspberry Pi, the performace obtained using local attached USB3.0 Flash Disk is quite simillar to the one obtained using iSCSI with a SSD Disk as central storage.

See this [repository](https://github.com/ricsanfre/pi-storage-benchmark) for the details of the testing procedure and the results.

See [here](./san_installation.md) further details about the configuration of SAN using a Raspeberry PIs, `gateway`, as iSCSI Target exposing LUNs to cluster nodes.


## Hardware used

This is the hardware I'm using to create the cluster:

- [4 x Raspberry Pi 4 - Model B (4 GB)](https://www.tiendatec.es/raspberry-pi/gama-raspberry-pi/1100-raspberry-pi-4-modelo-b-4gb-765756931182.html) for the kuberenetes cluster (1 master node and 3 workers).
- [1 x Raspberry Pi 4 - Model B (2 GB)](https://www.tiendatec.es/raspberry-pi/gama-raspberry-pi/1099-raspberry-pi-4-modelo-b-2gb-765756931175.html) for creating a router for the lab environment connected via wifi to my home network and securing the access to my lab network.
- [4 x SanDisk Ultra 32 GB microSDHC Memory Cards](https://www.amazon.es/SanDisk-SDSQUA4-064G-GN6MA-microSDXC-Adaptador-Rendimiento-dp-B08GY9NYRM/dp/B08GY9NYRM) (Class 10) for installing Raspberry Pi OS for enabling booting from USB (update Raspberry PI firmware and modify USB partition)
- [4 x Samsung USB 3.1 32 GB Fit Plus Flash Disk](https://www.amazon.es/Samsung-FIT-Plus-Memoria-MUF-32AB/dp/B07HPWKS3C) 
- [1 x Kingston A400 SSD Disk 480GB](https://www.amazon.es/Kingston-SSD-A400-Disco-s%C3%B3lido/dp/B01N0TQPQB)
- [3 x Kingston A400 SSD Disk 240GB](https://www.amazon.es/Kingston-SSD-A400-Disco-s%C3%B3lido/dp/B01N5IB20Q)
- [4 x Startech USB 3.0 to SATA III Adapter](https://www.amazon.es/Startech-USB3S2SAT3CB-Adaptador-3-0-2-5-negro) for connecting SSD disk to USB 3.0 ports.
- [1 x GeeekPi Pi Rack Case](https://www.amazon.es/GeeekPi-Raspberry-Ventilador-refrigeraci%C3%B3n-disipador/dp/B07Z4GRQGH/ref=sr_1_11). It comes with a stack for 4 x Raspberry Pi’s, plus heatsinks and fans)
- [1 x SSD Rack Case](https://www.aliexpress.com/i/33008511822.html)
- [1 x Negear GS108-300PES](https://www.amazon.es/Netgear-GS108E-300PES-conmutador-gestionable-met%C3%A1lica/dp/B00MYYTP3S). 8 ports GE ethernet manageable switch (QoS and VLAN support)
- [1 x ANIDEES AI CHARGER 6+](https://www.tiendatec.es/raspberry-pi/raspberry-pi-alimentacion/796-anidees-ai-charger-6-cargador-usb-6-puertos-5v-60w-12a-raspberry-pi-4712909320214.html). 6 port USB power supply (60 W and max 12 A)
- [5 x Ethernet Cable](https://www.aliexpress.com/item/32821735352.html). Flat Cat 6,  15 cm length
- [5 x USB-C charging cable with ON/OFF switch](https://www.aliexpress.com/item/33049198504.html).
