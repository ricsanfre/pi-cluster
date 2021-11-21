# Gateway Configuration

One of the Raspeberry Pi (2GB), **gateway**, is used as Router and Firewall for the home lab, isolating the raspberry pi cluster from my home network.
It will also provide DNS, NTP and DHCP services to my lab network.
This Raspberry Pi (gateway), is connected to my home network using its WIFI interface (wlan0) and to the LAN Switch using the eth interface (eth0).

In order to ease the automation with Ansible, OS installed on **gateway** is the same as the one installed in the nodes of the cluster (**node1-node4**): Ubuntu 20.04.3 64 bits.


#### Table of contents

1. [Hardware](#hardware)
2. [Network Configuration](#network-configuration)
3. [Ubuntu boot from SSD](#unbuntu-boot-from-ssd)
4. [Initial OS Configuration](#ubuntu-os-initital-configuration)
5. [Router/Firewall Configuration](#routerfirewall-configuration)
6. [DHCP/DNS Configuration](#dhcpdns-configuration)
7. [NTP Server Configuration](#ntp-server-configuration)


## Hardware

`gateway` node is based on a Raspberry Pi 4B 2GB boot from a USB Flash Disk avoiding the use of SDCards.
A Samsung USB 3.1 32 GB Fit Plus Flash Disk will be used connected to one of the USB 3.0 ports of the Raspberry Pi.

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

The installation procedure followed is the described [here](./installing_ubuntu.md) using cloud-init configuration files (`user-data` and `network-config`) for `gateway`.


| User data file   | Network configuration |
| ------------- |-------------|
| [user-data](../cloud-init-ubuntu-images/gateway/user-data) | [network-config](../cloud-init-ubuntu-images/gateway/network-config)|



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

This can be done installing `iptables` package and configuring iptables rules.

For example forwarding rules can be configured with the follwing commads:

    sudo apt install iptables
    sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
    sudo iptables -A FORWARD -i wlan0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -i eth0 -o wlan0 -j ACCEPT

But for configuring router/firewall rules, [**nftables**](https://www.netfilter.org/projects/nftables/) package will be used instead.

`nftables` is the succesor of `iptables` and it allows for much more flexible, easy to use, scalable and performance packet classification. Both of them are based on `netfilter` kernel module and according to their community maintaners [netfilter](netfilter.org) in nftables is "where all the fancy new features are developed".

In Debian, since 11 release (Buster), `nftables` is the default and recommended firewall package replacing `iptables` (see https://wiki.debian.org/nftables). Starting with Debian Buster, nf_tables is the default backend when using iptables, by means of the iptables-nft layer (i.e, using iptables syntax with the nf_tables kernel subsystem). In Ubuntu, since Ubuntu 20.10, `ip-tables` package is including [`xtables-nft`](https://manpages.ubuntu.com/manpages/groovy/man8/iptables-nft.8.html) commands which are versions of iptables commands but using nftables kernel api for enabling the migration from iptables to nftables.

`nftables` seems to have the support of the Linux community and iptables probably will be deprecated in future releases.

Package can be installed with apt:

   sudo apt install nftables

And it can be configured using command line or a configuration file `/etc/nftables.conf`.

```
TBD: CONTENT nftables.conf
```

<br>

> ***NOTE: About iptables rules persistency***
>
>
> iptables rules need to be saved to a file and restore it on startup from the backup file
>
>This can be done with the following commands:
>
>     sudo iptables-save > /etc/iptables/rules.v4
>
>     sudo iptables-restore < /etc/iptables/rules.v4
>
>and its IPv6 vesrions:
>
>     sudo ip6tables-save > /etc/iptables/rules.v6
>
>     sudo ip6tables-restore < /etc/iptables/rules.v6
>
>Init scripts should be configured to automatically load iptables rules on startup.
>
>In Ubuntu and Debian there is a package `iptables-persistent` which takes over the automatic loading of the saved iptables rules
>
>     sudo apt install iptables-persistent # First time
>     sudo dpkg-reconfigure iptables-persistent # Every time rules are changed
>
>In Ubuntu 20.04 applying this procedure is not working any more and it does not make the rules to persit across reboots.


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
