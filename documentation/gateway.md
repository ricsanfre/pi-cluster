# Gateway Configuration

One of the Raspeberry Pi (2GB), **gateway**, is used as Router and Firewall for the home lab, isolating the raspberry pi cluster from my home network.
It will also provide DNS, NTP and DHCP, and SAN services to my lab network.
This Raspberry Pi (gateway), is connected to my home network using its WIFI interface (wlan0) and to the LAN Switch using the eth interface (eth0).

In order to ease the automation with Ansible, OS installed on **gateway** is the same as the one installed in the nodes of the cluster (**node1-node4**): Ubuntu 20.04.2 64 bits.


#### Table of contents

1. [Hardware](#hardware)
2. [Network Configuration](#network-configuration)
3. [Ubuntu boot from SSD](#unbuntu-boot-from-ssd)
4. [Initial OS Configuration](#ubuntu-os-initital-configuration)
5. [Router/Firewall Configuration](#routerfirewall-configuration)
6. [DHCP/DNS Configuration](#dhcpdns-configuration)
7. [NTP Server Configuration](#ntp-server-configuration)
8. [iSCSI SAN Configuration](#iscsi-configuration)


## Hardware

`gateway` node is based on a Raspberry Pi 4B 2GB boot from a SSD Disk.
A Kingston A400 480GB SSD Disk and a USB3.0 to SATA adapter will be used connected to `gateway` for building for providing iSCSI storage to the Raspberry PI cluster.

## Network Configuration

The WIFI interface (wlan0) will be used to be connected to my home network using static IP address (192.168.1.11/24), while ethernet interface (eth0) will be connected to the lan switch, lab network, using static IP address (10.0.0.1/24)
Static IP addres in home network, will enable the configuration of static routes in my labtop and VM running on it (`pimaster`) to access the cluster nodes without fisically connect the laptop to the lan switch with an ethernet cable. 

Ubuntu's netplan yaml configuration file used, part of cloud-init boot `/boot/network-config` is like:

```yml
version: 2
ethernets:
  eth0:
    dhcp4: false
    addresses: [10.0.0.1/24]
wifis:
  wlan0:
    dhcp4: false
    optional: true
    access-points:
      "<SSID_NAME>":
        password: "<SSID_PASSWD>"
    addresses: [192.168.1.11/24]
    gateway4: 192.168.1.1
    nameservers:
      addresses: [80.58.61.250,80.58.61.254]
```
 
## Unbuntu boot from SSD

`gateway` node will be acting as SAN server and to enhace its performance it will boot from USB using the same SSD disk that will be used for LUNs storage

SSD Disk will be partitioned reserving the biggest partition for the iSCSI LUNS: 32 GB will be reserved for the OS and the rest of the disk will be used for LUNs.

Initial partitions (boot and OS) will be created during initial image burning process. Partitions need to be reconfigured before the first boot.

The procedure followed is the described [here](./installing_ubuntu.md), but modifying the disks partitions before booting from USB for the first time for creating a partition disk for iSCSI LUNs

### Step 1. Burn Ubuntu 20.04 server to SSD disk using Balena Etcher

Update cloud-init configuration files (`user-data` and `network-config`) with the `gateway` network configuration and OS initial configuration.


| User data file   | Network configuration |
| ------------- |-------------|
| [user-data](../cloud-init-ubuntu-images/gateway/user-data) | [network-config](../cloud-init-ubuntu-images/gateway/network-config)|

### Step 2. Boot Raspberry PI with Raspberry OS

Use a SD with Raspberry PI OS to boot for the first time.

### Step 3. Connect SSD Disk to USB 3.0 port.

Check the disk

   sudo fdisk -l

```
sudo fdisk -l

Disk /dev/mmcblk0: 29.7 GiB, 31914983424 bytes, 62333952 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0x9c46674d

Device         Boot  Start      End  Sectors  Size Id Type
/dev/mmcblk0p1        8192   532479   524288  256M  c W95 FAT32 (LBA)
/dev/mmcblk0p2      532480 62333951 61801472 29.5G 83 Linux


Disk /dev/sda: 447.1 GiB, 480103981056 bytes, 937703088 sectors
Disk model: Generic
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 4096 bytes
I/O size (minimum/optimal): 4096 bytes / 4096 bytes
Disklabel type: dos
Disk identifier: 0x4ec8ea53

Device     Boot  Start     End Sectors  Size Id Type
/dev/sda1  *      2048  526335  524288  256M  c W95 FAT32 (LBA)
/dev/sda2       526336 6366175 5839840  2.8G 83 Linux
```

### Step 4. Repartition with parted

After flashing the disk the root partion size is less than 3 GB. On first boot this partition is automatically extended to occupy 100% of the available disk space.
Since I want to use the SSD disk not only for the Ubuntu OS, but providing iSCSI LUNS. Before the first boot, I will repartition the SSD disk.

- Extending the root partition to 32 GB Size
- Create a new partition for storing iSCSI LVM LUNS

```shell
pi@gateway:~ $ sudo parted /dev/sda
GNU Parted 3.2
Using /dev/sda
Welcome to GNU Parted! Type 'help' to view a list of commands.
(parted) print
Model: JMicron Generic (scsi)
Disk /dev/sda: 480GB
Sector size (logical/physical): 512B/4096B
Partition Table: msdos
Disk Flags:

Number  Start   End     Size    Type     File system  Flags
 1      1049kB  269MB   268MB   primary  fat32        boot, lba
 2      269MB   3259MB  2990MB  primary  ext4

(parted) resizepart
Partition number? 2
End?  [3259MB]? 32500
(parted) print
Model: JMicron Generic (scsi)
Disk /dev/sda: 480GB
Sector size (logical/physical): 512B/4096B
Partition Table: msdos
Disk Flags:

Number  Start   End     Size    Type     File system  Flags
 1      1049kB  269MB   268MB   primary  fat32        boot, lba
 2      269MB   32.5GB  32.2GB  primary  ext4

(parted) mkpart
Partition type?  primary/extended? primary
File system type?  [ext2]? ext4
Start? 32501
End?
End? 100%
(parted) print
Model: JMicron Generic (scsi)
Disk /dev/sda: 480GB
Sector size (logical/physical): 512B/4096B
Partition Table: msdos
Disk Flags:

Number  Start   End     Size    Type     File system  Flags
 1      1049kB  269MB   268MB   primary  fat32        boot, lba
 2      269MB   32.5GB  32.2GB  primary  ext4
 3      32.5GB  480GB   448GB   primary  ext4         lba

(parted) set 3 lvm on
(parted) print
Model: JMicron Generic (scsi)
Disk /dev/sda: 480GB
Sector size (logical/physical): 512B/4096B
Partition Table: msdos
Disk Flags:

Number  Start   End     Size    Type     File system  Flags
 1      1049kB  269MB   268MB   primary  fat32        boot, lba
 2      269MB   32.5GB  32.2GB  primary  ext4
 3      32.5GB  480GB   448GB   primary  ext4         lvm, lba

(parted) quit
```

### Step 5. Checking USB-SATA Adapter

Checking that the USB SATA adapter suppors UASP.

```shell
lsusb -t

/:  Bus 02.Port 1: Dev 1, Class=root_hub, Driver=xhci_hcd/4p, 5000M
    |__ Port 1: Dev 2, If 0, Class=Mass Storage, Driver=uas, 5000M
/:  Bus 01.Port 1: Dev 1, Class=root_hub, Driver=xhci_hcd/1p, 480M
    |__ Port 1: Dev 2, If 0, Class=Hub, Driver=hub/4p, 480M
        |__ Port 3: Dev 3, If 0, Class=Human Interface Device, Driver=usbhid, 1.5M
        |__ Port 3: Dev 3, If 1, Class=Human Interface Device, Driver=usbhid, 1.5M
        |__ Port 4: Dev 4, If 0, Class=Human Interface Device, Driver=usbhid, 1.5M

```
> Driver=uas indicates that the adpater supports UASP


Check USB-SATA adapter ID

```shell
sudo lsusb
Bus 002 Device 002: ID 174c:55aa ASMedia Technology Inc. Name: ASM1051E SATA 6Gb/s bridge, ASM1053E SATA 6Gb/s bridge, ASM1153 SATA 3Gb/s bridge, ASM1153E SATA 6Gb/s bridge
Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
Bus 001 Device 004: ID 0000:3825
Bus 001 Device 003: ID 145f:02c9 Trust
Bus 001 Device 002: ID 2109:3431 VIA Labs, Inc. Hub
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
```

> NOTE: In this case ASMedia TEchnology ASM1051E has ID 152d:0578


### Step 6. Modify USB partitions following instrucions described [here](./installing_ubuntu.md#step-5-modify-mounted-partitions-to-fix-booting-procedure-from-disk)


## Ubuntu OS Initital Configuration

After booting from the USB3.0 external storage for the first time, the Raspberry Pi will have SSH connectivity and it will be ready to be automatically configured from the ansible control node `pimaster`.

Initial configuration tasks includes: removal of snap package, and Raspberry PI specific configurations tasks such as: intallation of fake hardware clock, installation of some utility packages scripts and change default GPU Memory plit configuration. See instructions [here](./basic_os_configuration.md).

For automating all this initial configuration tasks, ansible role **basic_setup** has been developed.

## Router/Firewall Configuration

For automating configuration tasks, ansible role [**ricsanfre.firewall**](https://galaxy.ansible.com/ricsanfre/firewall) has been developed.

### Step 1. Enable IP forwarding

To convert gateway into a router, Ubuntu need to be configured to enable the forwarding of IP packets.
This is done by adding to **/etc/sysctl.conf** file:

    net.ipv4.ip_forward=1

### Step 2. Configure filtering and forwarding rules

This can be done installing **iptables** package and configuring iptables rules.

    sudo apt install iptables
    sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
    sudo iptables -A FORWARD -i wlan0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -i eth0 -o wlan0 -j ACCEPT

and persist iptables rules across reboots by installing **iptables-persistent**

    sudo apt install iptables-persistent # First time
    sudo dpkg-reconfigure iptables-persistent # Every time rules are changed

In Ubuntu 20.04 applying this procedure does not make the rules to persit across reboots. Moreover since Ubuntu 20.10 **nftables** package is used instead iptables.
nftables seems to have the support of the Linux community and iptables probably will be deprecated in future releases.

For configuring router/firewall rules, [**nftables**](https://www.netfilter.org/projects/nftables/) package will be used.

Package can be installed with apt:

   sudo apt install nftables

And it can be configured using command line or configuration file `/etc/nftables.conf`.

```
TBD: CONTENT nftables.conf
```

With this rules:

- **gateway** is accepting incoming ICMP, SSH, NTP, DNS and HTTP and HTTPS traffic
- **gateway** is forwarding only SSH, HTTP, DNS and HTTPS traffic

### Configuring Ansible Role

nftables default rules establish by the role can be updated by changing roles variables for `gateway` host (see `gateway` host variables in [`host_vars\gateway.yml`](../ansible/host_vars/gateway.yml) file)

The rules configured for `gateway` allow incoming traffic (icmp, http, https, iscsi, ssh, dns, dhcp, ntp and snmp) and forward http, https, ssh, dns and ntp traffic.


### Configuring static route in my Laptop and VM `pimaster`

To acess to the cluster nodes from my home network a static route need to be added for using `gateway` as router of my lab network (10.0.0.0/24)

- Adding static route in my Windows laptop

    Open a command:

        ROUTE -P ADD 10.0.0.0 MASK 255.255.255.0 192.168.1.11 METRIC 1
    
- Adding static route in Linux VM running on my laptop (VirtualBox)
  
    Modify `/etc/netplan/50-cloud-init.yaml` for adding the static route
    
    ```yml 
    network:
    version: 2
    ethernets:
      enp0s3:
        dhcp4: no
        addresses: [192.168.56.20/24]
      enp0s8:
        dhcp4: yes
        routes:
        - to: 10.0.0.0/24
          via: 192.168.1.11        
    ```
     > NOTE: This is `pimaster` VirutalBOX network configuration:
     >- **Eth0** (enp0s3) connected to VBox **Host-Only adapter** (laptop only connection)
     >- **Eth1** (enp0s8) connected to VBox **Bridge adapter** (home network connection)
    
## DHCP/DNS Configuration

**dnsmasq** will be used as lightweigh DHCP/DNS server
For automating configuration tasks, ansible role [**ricsanfre.dnsmasq**](https://galaxy.ansible.com/ricsanfre/dnsmasq) has been developed.

### Step 1. Install dnsmasq

    sudo apt install dnsmasq
	
### Step 2. Configure dnsmasq

Edit file `/etc/dnsmasq.d/dnsmasq.conf`

```
TBD: CONTENT dnsmasq.conf
```

### Step 3. Restart dnsmasq service

### Configuring Ansible Role

DHCP static IP leases and DNS records are taken automatically from ansible inventory file for those hosts with `ip`, `hostname` and `mac` variables are defined. See [`inventory.yml`](../ansible/inventory.yml) file.

```yml
...
    cluster:
      hosts:
        node1:
          hostname: node1
          ansible_host: 10.0.0.11
          ip: 10.0.0.11
          mac: dc:a6:32:9c:29:b9
        node2:
          hostname: node2
          ansible_host: 10.0.0.12
          ip: 10.0.0.12
          mac: e4:5f:01:2d:fd:19
...
```

Additional DHCP static IP leases and DNS records can be added using `dnsmasq_additional_dhcp_hosts` and `dnsmasq_additional_dns_hosts` role variables.

DNS/DHCP specific configuration, dnsmasq role variables for `gateway` host, are located in [`host_vars\gateway.yml`](../ansible/host_vars/gateway.yml) file.

### Commands

1. Check DHCP leases in DHCP server

    See file `/var/lib/misc/dnsmasq.leases`
	
2. Check DHCP lease in DHCP Clients

    See file `/var/lib/dhcp/dhclient.leases`
	
3. Release DHCP current lease (DHCP client)
   
    ```
  	sudo dhclient -r <interface>
  	```
	
4. Obtain a new DHCP lease

    ```
    sudo dhclient <interface>
	  ```


## NTP Server Configuration

Ubuntu by default uses timedatectl / timesyncd to synchronize time and users can optionally use chrony to serve the Network Time Protocol
Since Ubuntu 16.04 timedatectl / timesyncd (which are part of systemd) replace most of ntpdate / ntp.
(https://ubuntu.com/server/docs/network-ntp)

Since ntp and ntpdate are deprecated **chrony** package will be used for configuring NTP synchronization.

**gateway** will be hosting a NTP server and the rest of cluster nodes will be configured as NTP Clients.

For automating ntp configuration tasks on all nodes (gateway and node1-4), ansible role [**ricsanfre.ntp**](https://galaxy.ansible.com/ricsanfre/ntp) has been created.

### Step 1. Install chrony

    sudo apt install chrony


### Step 2. Configure chrony

Edit file `/etc/chrony/chrony.conf`

- In **gateway**

    Configure NTP servers and allow serving NTP to lan clients.
	
    ```
    pool 0.ubuntu.pool.ntp.org iburst
    pool 1.ubuntu.pool.ntp.org iburst
    pool 2.ubuntu.pool.ntp.org iburst
    pool 3.ubuntu.pool.ntp.org iburst

    allow 10.0.0.0/24
    ```

- In **node1-4**:

    Configure gateway as NTP server
   
    ```
    server 10.0.0.1
    ```

### Chrony commands

Check time synchronization with Chronyc

1. Confirm that NTP is enabled

    ```
    timedatectl
	  ```

2. Checking Chrony is running and view the peers and servers to which it is connected
    
	  ```
    chronyc activity
	  ```

3. To view a detailed list of time servers, their IP addresses, time skew, and offset
    
	  ```
    chronyc sources
	  ```

4. Confirm that the chrony is synchronized
   
    ```
    chronyc tracking
	  ```

## iSCSI configuration

`gateway` is configured as iSCSI Target to export LUNs mounted by `node1-node4`

iSCSI configuration in `gateway` has been automated developing a couple of ansible roles: **ricsanfre.storage** for managing LVM and **ricsanfre.iscsi_target** for configuring a iSCSI target.

Further details about iSCSI configurations and step-by-step manual instructions are defined [here](./san_installation.md).

`gateway` exposes a dedicated LUN of 100 GB for each of the clusters nodes.