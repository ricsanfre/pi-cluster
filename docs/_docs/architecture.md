---
title: Lab Architecture
permalink: /docs/architecture/
description: Homelab architecture of our Pi Kuberentes cluster. Cluster nodes, firewall, and Ansible control node. Networking and cluster storage design.
last_modified_at: "03-02-2024"
---


The home lab I am building is shown in the following picture

![Cluster-lab](/assets/img/picluster-architecture.png)


A K3S cluster is composed of the following **cluster nodes**:
- 3 master nodes (`node2`, `node3` and `node4`), running on Raspberry Pi 4B (4GB)
- 5 worker nodes:
  - `node5` and `node6`running on Raspberry Pi 4B (8GB)
  - `node-hp-1`, `node-hp-2` and `node-hp-3` running on HP Elitedesk 800 G3 (16GB)

A couple of **LAN switches** (8 Gigabit ports + 5 Gigabit ports) used to provide L2 connectivity to the cluster nodes. L3 connectivity and internet access is provided by a router/firewall (`gateway`) running on Raspberry Pi 4B (2GB). 

`gateway`, **cluster firewall/router**, is connected to LAN Switch using its Gigabit Ethernet port. It is also connected to my home network using its WIFI interface, so it can route and filter traffic comming in/out the cluster. With this architecture my lab network can be isolated from my home network.

`gateway` also provides networking services to my lab network:
 - Internet Access
 - DNS
 - NTP
 - DHCP

`node1`, running on Raspberry Pi 4B (4GB), for providing **kubernetes external services**:
  - Secret Management (Vault)
  - Kuberentes API Load Balancer
  - Backup server

A load balancer is needed for providing Hight availability to Kubernetes API. In this cases a network load balancer, [HAProxy](https://www.haproxy.org/), will be deployed in `node1` server.

For automating the OS installation of x86 nodes, a **PXE server** will be deployed in `gateway` node.

**Ansible control node**, `pimaster` is deployed in a Linux VM or Linux Laptop, so from this node the whole cluster configuration can be managed. `pimaster` is connected to my home network (ip in  192.168.1.0/24 network). In `pimaster`, a IP route to 10.0.0.0/24 network through `gateway` (192.168.1.11) need to be configured, so it can have connectivity to cluster nodes.


## Hardware

### Nodes

For building the cluster, using bare metal servers instead of virtual machines, low cost servers are used:

#### ARM-based SBC (Single Board Computer)

- [Raspberry Pi 4B](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/)

  - CPU: Broadcom BCM2711, Quad core Cortex-A72 (ARM v8). 4 cores/4 threads at 1.5GHz
  - RAM: 2GB/4GB/8GB
  - Disk: SDCard or USB disk (Flash Disk or SSD disk through USB to SATA adapter)


  ![raspberry-pi-4b](/assets/img/raspberrypi4b.png)

  I have used the following hardware components to assemble Raspberry PI components of the cluster.

  - [4 x Raspberry Pi 4 - Model B (4 GB)](https://www.tiendatec.es/raspberry-pi/gama-raspberry-pi/1100-raspberry-pi-4-modelo-b-4gb-765756931182.html) and [1 x Raspberry Pi 4 - Model B (8 GB)](https://www.tiendatec.es/raspberry-pi/gama-raspberry-pi/1231-raspberry-pi-4-modelo-b-8gb-765756931199.html) as ARM-based cluster nodes (1 master node and 5 worker nodes).
  - [2 x Raspberry Pi 4 - Model B (2 GB)](https://www.tiendatec.es/raspberry-pi/gama-raspberry-pi/1099-raspberry-pi-4-modelo-b-2gb-765756931175.html) as router/firewall for the lab environment connected via wifi to my home network and securing the access to my lab network.
  - [4 x SanDisk Ultra 32 GB microSDHC Memory Cards](https://www.amazon.es/SanDisk-SDSQUA4-064G-GN6MA-microSDXC-Adaptador-Rendimiento-dp-B08GY9NYRM/dp/B08GY9NYRM) (Class 10) for installing Raspberry Pi OS for enabling booting from USB (update Raspberry PI firmware and modify USB partition)
  - [4 x Samsung USB 3.1 32 GB Fit Plus Flash Disk](https://www.amazon.es/Samsung-FIT-Plus-Memoria-MUF-32AB/dp/B07HPWKS3C) 
  - [1 x Kingston A400 SSD Disk 480GB](https://www.amazon.es/Kingston-SSD-A400-Disco-s%C3%B3lido/dp/B01N0TQPQB)
  - [5 x Kingston A400 SSD Disk 240GB](https://www.amazon.es/Kingston-SSD-A400-Disco-s%C3%B3lido/dp/B01N5IB20Q)
  - [6 x Startech USB 3.0 to SATA III Adapter](https://www.amazon.es/Startech-USB3S2SAT3CB-Adaptador-3-0-2-5-negro/dp/B00HJZJI84) for connecting SSD disk to USB 3.0 ports.
  - [1 x GeeekPi Pi Rack Case](https://www.amazon.es/GeeekPi-Raspberry-Ventilador-refrigeraci%C3%B3n-disipador/dp/B07Z4GRQGH/ref=sr_1_11). It comes with a stack for 4 x Raspberry Pi’s, plus heatsinks and fans)
  - [1 x SSD Rack Case](https://www.aliexpress.com/i/33008511822.html)
  - [1 x ANIDEES AI CHARGER 6+](https://www.tiendatec.es/raspberry-pi/raspberry-pi-alimentacion/796-anidees-ai-charger-6-cargador-usb-6-puertos-5v-60w-12a-raspberry-pi-4712909320214.html). 6 port USB power supply (60 W and max 12 A)
  - [1 x ANKER USB Charging Hub](https://www.amazon.es/Anker-Cargador-USB-6-Puertos/dp/B00PTLSH9G/). 6 port USB power supply (60 w and max 12 A)
  - [7 x USB-C charging cable with ON/OFF switch](https://www.aliexpress.com/item/33049198504.html).


#### x86-based old refurbished mini PC

- [HP Elitedesk 800 G3 Desktop mini PC](https://support.hp.com/us-en/product/hp-elitedesk-800-65w-g3-desktop-mini-pc/15497277/manuals)
  - CPU: Intel i5 6500T. 4 cores(4 threads) at 2.5 GHz
  - RAM: 16 GB
  - Disk: Integrated SSD disk (SATA or NVMe)

  ![hp-elitedesk-800](/assets/img/hpelitedesk800g3mini.png)

  I have used the following hardware components

    - [3 x HP EliteDesk 800 G3 i5 6500T 2,5 GHz, 8 GB de RAM, SSD de 256 GB](https://www.amazon.es/HP-EliteDesk-800-G3-reacondicionado/dp/B09TL2N2M8) as x86 cluster nodes.
      One of the nodes `node-hp-2` has a SSD M.2 NVMe 256 GB. The other, `node-hp-1` has a SATA SSD Kingston 240 GB
    - [3 x Crucial RAM 8GB DDR4 2400MHz CL17 Memoria](https://www.amazon.es/dp/B01BIWKP58) as RAM expansion for mini PCs. Total memmory 16 GB 

{{site.data.alerts.note}}

Initially the intent of this project was to build a kuberentes cluster using only Raspberry PI nodes. Due to Raspberry shortage during last 2 years, which makes impossible to buy them at reasonable prices, I have decided to look for alternatives to be able to scale up my cluster.

Use old x86 refurbished mini PCs, with Intel i5 processors, has been the solution. These mini PCs provide similar performance to RaspberryPi's Quadcore ARM Cortex-A72, but its memory can be expanded up to 32GB of RAM (Raspberry PI higher model only supports 8GB RAM). As a drawback power consumption of those mini PCs are higher that Raspberry PIs.

The overall price of a mini PC, intel i5 + 8 GB RAM + 256 GB SSD disk + power supply, ([aprox 130 €](https://www.amazon.es/HP-EliteDesk-800-G3-reacondicionado/dp/B09TL2N2M8/)) is cheaper than the overal cost of building a cluster node using a Rasbperry PI: cost of Raspberry PI 8GB (100€) + Power Adapter (aprox 10 €) + SSD Disk ([aprox 20 €](https://www.amazon.es/Kingston-SSD-A400-Disco-s%C3%B3lido/dp/B01N5IB20Q)) + USB3.0 to SATA converter ([aprox 20€](https://www.amazon.es/Startech-USB3S2SAT3CB-Adaptador-3-0-2-5-negro/dp/B00HJZJI84))

{{site.data.alerts.end}}


### Networking

A 8 GE ports LAN switch, [NetGear GS108S](https://www.netgear.com/business/wired/switches/plus/gs108e/), and 5 GE ports LAN switch, [NetGear GS105E](https://www.netgear.es/support/product/gs105e), supporting VLAN configuration and remote management, are used to provide connectivity to all cluster nodes (Raspberry Pis and x86 mini PCs).

All nodes are connected to the switch with Cat6 eth cables, using their Gigabit Ethernet port.

![netgear-gs108s](/assets/img/netgear-gs108e.jpg)


![netgear-gs105e](/assets/img/netgear-gs105E.png)

For networking, I have used the following hardware components:

- [1 x Netgear GS108-300PES](https://www.amazon.es/Netgear-GS108E-300PES-conmutador-gestionable-met%C3%A1lica/dp/B00MYYTP3S). 8 ports GE ethernet managed switch (QoS and VLAN support)

- [1 x Netgear GS105E](https://www.amazon.es/Netgear-GS105E-200PES-gestionable-puertos-Gigabit/dp/B00GWKN1Q2), 5 ports GE ehternet managed switch
- [10 x Ethernet Cable](https://www.aliexpress.com/item/32821735352.html). Flat Cat 6,  15 cm length

## Raspberry PI Storage

x86 mini PCs has their own integrated disk (SSD disk or NVME). For Raspberry PIs different storage alternatives can be applied:

- Dedicated Disks: Each node has its SSD disks attached to one of its USB 3.0 ports. SSD disk + SATA to USB 3.0 adapter is needed for each node.
- Centralized SAN: Each node has Flash Disk (USB3.0) for running OS and additional storage capacity is provide via iSCSI from a SAN (Storage Area Network). One of the cluster nodes, gateway, is configured as SAN server, and it needs to have SSD disk attached to its USB3.0 port.

![cluster-HW-storage](/assets/img/RaspberryPiCluster_HW_storage.png)


### Dedicated Disks

`gateway` uses local storage attached directly to USB 3.0 port (Flash Disk) for hosting the OS, avoiding the use of less reliable SDCards.

For having better cluster performance `node1-node6` will use SSDs attached to USB 3.0 port. SSD disk will be used to host OS (boot from USB) and to provide the additional storage required per node for deploying the Kubernetes distributed storage solution (Ceph or Longhorn).

![pi-cluster-HW-2.0](/assets/img/pi-cluster-2.0.png)


### Centralized SAN

A cheaper alternative architecture, instead of using dedicated SSD disks for each cluster node, one single SSD disk can be used for configuring a SAN service.

Each cluster node `node1-node6` can use local storage attached directly to USB 3.0 port (USB Flash Disk) for hosting the OS, avoiding the use of less reliable SDCards.
 
As additional storage (required by distributed storage solution), iSCSI SAN can be deployed instead of attaching an additional USB Flash Disks to each of the nodes.

A SAN (Storage Access Network) can be configured using `gateway` as iSCSI Storage Server, providing additional storage (LUNs) to `node1-node6`.

As storage device, a SSD disk was attached to `gateway` node. This SSD disk was used as well to host the OS.

![pi-cluster-HW-1.0](/assets/img/pi-cluster.png)

This alternative setup is worth it from educational point of view, to test the different storage options for RaspberryPI and to learn about iSCSI configuration and deployment on bare-metal environments. As well it can be used as a cheaper solution for deploying centralized storage solution.

See [SAN configuration document](/docs/san/) further details about the configuration of SAN using a Raspeberry PIs, `gateway`, as iSCSI Target exposing LUNs to cluster nodes.


### Raspberry PI Storage benchmarking

Different Raspberry PI storage configurations have been tested:

1. Internal SDCard: [SanDisk Ultra 32 GB microSDHC Memory Cards](https://www.amazon.es/SanDisk-SDSQUA4-064G-GN6MA-microSDXC-Adaptador-Rendimiento-dp-B08GY9NYRM/dp/B08GY9NYRM) (Class 10)

2. Flash Disk USB 3.0: [Samsung USB 3.1 32 GB Fit Plus Flash Disk](https://www.amazon.es/Samsung-FIT-Plus-Memoria-MUF-32AB/dp/B07HPWKS3C)

3. SSD Disk [Kingston A400 480GB](https://www.amazon.es/Kingston-SSD-A400-Disco-s%C3%B3lido/dp/B01N0TQPQB) + USB3 to SATA Adapter [Startech USB 3.0 to SATA III](https://www.amazon.es/Startech-USB3S2SAT3CB-Adaptador-3-0-2-5-negro/dp/B00HJZJI84)

4. iSCSI Volumes. Using another Raspberry PI as storage server, configured as iSCSI Target, using a SSD disk attached.

#### Testing procedure

Sequential and random I/O tests have been executed with the different storage configurations. 

For the testing a tweaked version of the script provided by James A. Chambers (https://jamesachambers.com/) has been used

Tests execution has been automated with Ansible. See `pi-storage-benchmark` [repository](https://github.com/ricsanfre/pi-storage-benchmark) for the details of the testing procedure and the results.

##### Sequential I/O performance

Test sequential I/O with `dd` and `hdparam` tools. `hdparm` can be installed through `sudo apt install -y hdparm`


- Read speed (Use `hdparm` command)
    
  ```shell
  sudo hdparm -t /dev/sda1
    
  Timing buffered disk reads:  72 MB in  3.05 seconds =  23.59 MB/sec

  sudo hdparm -T /dev/sda1
  Timing cached reads:   464 MB in  2.01 seconds = 231.31 MB/sec
  ```

  It can be combined in just one command:

  ```shell
  sudo hdparm -tT --direct /dev/sda1

  Timing O_DIRECT cached reads:   724 MB in  2.00 seconds = 361.84 MB/sec
  Timing O_DIRECT disk reads: 406 MB in  3.01 seconds = 134.99 MB/sec
  ```

- Write Speed (use `dd` command)

  ```shell
  sudo dd if=/dev/zero of=test bs=4k count=80k conv=fsync

  81920+0 records in
  81920+0 records out
  335544320 bytes (336 MB, 320 MiB) copied, 1,86384 s, 180 MB/s
  ```

##### Random I/O Performance

Tools used `fio` and `iozone`.

- Install required packages with:

  ```shell
  sudo apt install iozone3 fio
  ```

- Check random I/O with `fio`

  Random Write

  ```shell
  sudo fio --minimal --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --filename=test --bs=4k --iodepth=64 --size=80M --readwrite=randwrite
   ```

  Random Read

  ```shell
  sudo fio --minimal --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=test --filename=test --bs=4k --iodepth=64 --size=80M --readwrite=randread
   ```

- Check random I/O with `iozone`

  ```shell
  sudo iozone -a -e -I -i 0 -i 1 -i 2 -s 80M -r 4k
  ```

#### Performance Results

Average-metrics obtained during the tests removing the worst and the best result can be found in the next table and the following graphs:

<div class="table-responsive">
|           | Disk Read (MB/s) | Cache Disk Read (MB/s) | Disk Write (MB/s) | 4K Random Read (IOPS) | 4K Random Read (KB/s) | 4K Random Write (IOPS) | 4K Random Write (KB/s) | 4k read (KB/s) | 4k write (KB/s) | 4k random read (KB/s) | 4k random write (KB/s) | Global Score   |
| --------- | ---------------- | ---------------------- | ----------------- | --------------------- | --------------------- | ---------------------- | ---------------------- | -------------- | --------------- | --------------------- | ---------------------- | ------- |
| SDCard    | 41.89            | 39.02                  | 19.23             | 2767.33               | 11071.00              | 974.33                 | 3899.33                | 8846.33        | 2230.33         | 7368.67               | 3442.33                | 1169.67 |
| FlashDisk | 55.39            | 50.51                  | 21.30             | 3168.40               | 12675.00              | 2700.20                | 10802.40               | 14842.20       | 11561.80        | 11429.60              | 10780.60               | 2413.60 |
| SSD       | 335.10           | 304.67                 | 125.67            | 22025.67              | 88103.33              | 18731.33               | 74927.00               | 31834.33       | 26213.33        | 17064.33              | 29884.00               | 8295.67 |
| iSCSI     | 70.99            | 71.46                  | 54.07             | 5104.00               | 20417.00              | 5349.67                | 21400.00               | 7954.33        | 7421.33         | 6177.00               | 7788.33                | 2473.00 |
{: .table .table-white .table-borderer .border-dark }
</div>

- Sequential I/O

  ![sequential_i_o](/assets/img/benchmarking_sequential_i_o.png)


- Random I/O (FIO)

  ![random_i_o](/assets/img/benchmarking_random_i_o.png)

- Random I/O (IOZONE)

  ![random_i_o_iozone](/assets/img/benchmarking_random_i_o_iozone.png)


- Global Score

  ![global_score](/assets/img/benchmarking_score.png)

Conclusions:

1. Clearly `SSD` with USB3.0 to SATA adapter beats the rest in all performance tests.
2. `SDCard` obtains worst metrics than `FlashDisk` and `iSCSI`
3. `FlashDisk` and `iSCSI` get similar performance metrics

The performace obtained using local attached USB3.0 Flash Disk is quite similar to the one obtained using iSCSI with RaspberryPI+SSD Disk as central storage.


