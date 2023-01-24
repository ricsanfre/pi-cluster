---
title: Gateway installation
permalink: /docs/gateway/
description: How to configure a Raspberry Pi as router/firewall of our Raspberry Pi Kubernetes Cluster providing connectivity and basic services (DNS, DHCP, NTP, SAN).
last_modified_at: "10-09-2022"
---

One of the Raspeberry Pi (2GB), **gateway**, is used as Router and Firewall for the home lab, isolating the raspberry pi cluster from my home network.
It will also provide DNS, NTP and DHCP services to my lab network. In case of deployment using centralized SAN storage architectural option, `gateway` is providing SAN services also.

This Raspberry Pi (gateway), is connected to my home network using its WIFI interface (wlan0) and to the LAN Switch using the eth interface (eth0).

In order to ease the automation with Ansible, OS installed on **gateway** is the same as the one installed in the nodes of the cluster (**node1-node5**): Ubuntu 20.04.3 64 bits.


## Hardware

`gateway` node is based on a Raspberry Pi 4B 2GB booting from a USB Flash Disk or SSD Disk depending on storage architectural option selected.

- Dedicated disks storage architecture: A Samsung USB 3.1 32 GB Fit Plus Flash Disk will be used connected to one of the USB 3.0 ports of the Raspberry Pi.
- Centralized SAN architecture: Kingston A400 480GB SSD Disk and a USB3.0 to SATA adapter will be used connected to `gateway`. SSD disk for hosting OS and iSCSI LUNs

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
## Storage configuration. Centralized SAN

SSD Disk will be partitioned in boot time reserving 30 GB for root filesystem (OS installation) and the rest will be used for creating a logical volumes (LVM) mounted as `/storage`. This will provide local storage capacity in each node of the cluster, used mainly by Kuberentes distributed storage solution and by backup solution.

cloud-init configuration `user-data` includes commands to be executed once in boot time, executing a command that changes partition table and creates a new partition before the automatic growth of root partitions to fill the entire disk happens.

{{site.data.alerts.note}}
As a reference of how cloud images partitions grow in boot time check this blog [entry](https://elastisys.com/how-do-virtual-images-grow/)
{{site.data.alerts.end}}

Command executed in boot time is

```shell
sgdisk /dev/sda -e .g -n=0:30G:0 -t 0:8e00
```

This command:
  - First convert MBR partition to GPT (-g option)
  - Second moves the GPT backup block to the end of the disk  (-e option)
  - then creates a new partition starting 30GiB into the disk filling the rest of the disk (-n=0:10G:0 option)
  - And labels it as an LVM partition (-t option)

## Unbuntu boot from USB

The installation procedure followed is the described in ["Ubuntu OS Installation"](/docs/ubuntu/) using cloud-init configuration files (`user-data` and `network-config`) for `gateway`, depending on the storage architectural option selected:

| Storage Architeture| User data    | Network configuration |
|--------------------| ------------- |-------------|
|  Dedicated Disks |[user-data]({{ site.git_edit_address }}/cloud-init/dedicated_disks/gateway/user-data){: .link-dark } | [network-config]({{ site.git_edit_address }}/cloud-init/dedicated_disks/gateway/network-config){: .link-dark }|
| Centralized SAN | [user-data]({{ site.git_edit_address }}/cloud-init/centralized_san/gateway/user-data){: .link-dark } | [network-config]({{ site.git_edit_address }}/cloud-init/centralized_san/gateway/network-config){: .link-dark } |
{: .table .table-secondary .border-dark }

## Ubuntu OS Initital Configuration

After booting from the USB3.0 external storage for the first time, the Raspberry Pi will have SSH connectivity and it will be ready to be automatically configured from the ansible control node `pimaster`.

Initial configuration tasks includes: removal of snap package, and Raspberry PI specific configurations tasks such as: intallation of fake hardware clock, installation of some utility packages scripts and change default GPU Memory plit configuration. See instructions in ["Ubuntu OS initial configurations"](/docs/os-basic/).

For automating all this initial configuration tasks, ansible role **basic_setup** has been developed.

## Router/Firewall Configuration

For automating configuration tasks, ansible role [**ricsanfre.firewall**](https://galaxy.ansible.com/ricsanfre/firewall) has been developed.


### Enabling IP Forwarding

To convert gateway into a router, Ubuntu need to be configured to enable the forwarding of IP packets.
This is done by adding to **/etc/sysctl.conf** file:
```
net.ipv4.ip_forward=1
```

### Configure Filtering and Forwarding rules

This can be done installing `iptables` package and configuring iptables rules.

For example forwarding rules can be configured with the following commads:

```shell
sudo apt install iptables
sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
sudo iptables -A FORWARD -i wlan0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o wlan0 -j ACCEPT
```

But for configuring router/firewall rules, [**nftables**](https://www.netfilter.org/projects/nftables/) package will be used instead.

`nftables` is the succesor of `iptables` and it allows for much more flexible, easy to use, scalable and performance packet classification. Both of them are based on `netfilter` kernel module and according to their community maintaners [netfilter](https://www.netfilter.org) in nftables is "where all the fancy new features are developed".

In Debian, since 11 release (Buster), `nftables` is the default and recommended firewall package replacing `iptables` (see https://wiki.debian.org/nftables). Starting with Debian Buster, nf_tables is the default backend when using iptables, by means of the iptables-nft layer (i.e, using iptables syntax with the nf_tables kernel subsystem). In Ubuntu, since Ubuntu 20.10, `ip-tables` package is including [`xtables-nft`](https://manpages.ubuntu.com/manpages/jammy/en/man8/iptables-nft.8.html) commands which are versions of iptables commands but using nftables kernel api for enabling the migration from iptables to nftables.

`nftables` seems to have the support of the Linux community and iptables probably will be deprecated in future releases.

Package can be installed with apt:

```shell
sudo apt install nftables
```

And it can be configured using command line or a configuration file `/etc/nftables.conf`.

As a modular example:

- Global Configuration File

  `/etc/nftables.conf`
  ```
  #!/usr/sbin/nft -f
  # Ansible managed

  # clean
  flush ruleset

  include "/etc/nftables.d/defines.nft"

  table inet filter {
          chain global {
                  # 005 state management
                  ct state established,related accept
                  ct state invalid drop
          }
          include "/etc/nftables.d/sets.nft"
          include "/etc/nftables.d/filter-input.nft"
          include "/etc/nftables.d/filter-output.nft"
          include "/etc/nftables.d/filter-forward.nft"
  }

  # Additionnal table for Network Address Translation (NAT)
  table ip nat {
          include "/etc/nftables.d/sets.nft"
          include "/etc/nftables.d/nat-prerouting.nft"
          include "/etc/nftables.d/nat-postrouting.nft"
  }

  ```
- Variables  Variables containing the IP address and ports to be used by the rules files

  `/etc/nftables.d/defines.nft`
  ```
    # broadcast and multicast
    define badcast_addr = { 255.255.255.255, 224.0.0.1, 224.0.0.251 }

    # broadcast and multicast
    define ip6_badcast_addr = { ff02::16 }

    # in_tcp_accept
    define in_tcp_accept = { ssh, https, http }

    # in_udp_accept
    define in_udp_accept = { snmp, domain, ntp, bootps }

    # out_tcp_accept
    define out_tcp_accept = { http, https, ssh }

    # out_udp_accept
    define out_udp_accept = { domain, bootps , ntp }

    # lan_interface
    define lan_interface = eth0

    # wan_interface
    define wan_interface = wlan0

    # lan_network
    define lan_network = 10.0.0.0/24

    # forward_tcp_accept
    define forward_tcp_accept = { http, https, ssh }

    # forward_udp_accept
    define forward_udp_accept = { domain, ntp }

  ```
- Nftables typed and tagged variables, [sets](https://wiki.nftables.org/wiki-nftables/index.php/Sets).

  `/etc/nftables.d/sets.nft`
  ```
    set blackhole {
          type ipv4_addr;
          elements = $badcast_addr
      }

    set forward_tcp_accept {
          type inet_service; flags interval;
          elements = $forward_tcp_accept
      }

    set forward_udp_accept {
          type inet_service; flags interval;
          elements = $forward_udp_accept
      }

    set in_tcp_accept {
          type inet_service; flags interval;
          elements = $in_tcp_accept
      }

    set in_udp_accept {
          type inet_service; flags interval;
          elements = $in_udp_accept
      }

    set ip6blackhole {
          type ipv6_addr;
          elements = $ip6_badcast_addr
      }

    set out_tcp_accept {
          type inet_service; flags interval;
          elements = $out_tcp_accept
      }

    set out_udp_accept {
          type inet_service; flags interval;
          elements = $out_udp_accept
      }

  ```
- Input traffic filtering rules

  `/etc/nftables.d/filter-input.nft`
  ```
  chain input {
          # 000 policy
          type filter hook input priority 0; policy drop;
          # 005 global
          jump global
          # 010 drop unwanted
          # (none)
          # 011 drop unwanted ipv6
          # (none)
          # 015 localhost
          iif lo accept
          # 050 icmp
          meta l4proto {icmp,icmpv6} accept
          # 200 input udp accepted
          udp dport @in_udp_accept ct state new accept
          # 210 input tcp accepted
          tcp dport @in_tcp_accept ct state new accept
    }

  ```

- Output traffic filtering rules
  
  `/etc/nftables.d/filter-output.nft`
  ```
  chain output {
        # 000 policy: Allow any output traffic
        type filter hook output priority 0;
    }
  ```

- Forwarding traffic rules

  `/etc/nftables.d/filter-forward.nft`
  ```
  chain forward {
      # 000 policy
          type filter hook forward priority 0; policy drop;
      # 005 global
        jump global
      # 200 lan to wan tcp
        iifname $lan_interface ip saddr $lan_network oifname $wan_interface tcp dport @forward_tcp_accept ct state new accept
      # 210 lan to wan udp
        iifname $lan_interface ip saddr $lan_network oifname $wan_interface udp dport @forward_udp_accept ct state new accept
      # 220 ssh from wan
        iifname $wan_interface oifname $lan_interface ip daddr $lan_network tcp dport ssh ct state new accept
      # 230 http from wan
        iifname $wan_interface oifname $lan_interface ip daddr $lan_network tcp dport {http, https} ct state new accept

    }
  ```
  
  These forwarding rules enables:

  - Outgoing traffic (from the cluster): all tcp/udp traffic is allowed.
  - Incoming traffic (to the cluster): only the following traffic is allowed:
    - SSH
    - HTTP and HTTPS on standard ports (TCP 80 and 443).


  {{site.data.alerts.note}}

  Additional rules can be configured to enable the traffic to different services running in the cluster. For example:

  - To access to Minio console running on **node1**, the following rule need to be added.

    ```
    # 240 s3 from wan
    iifname $wan_interface oifname $lan_interface ip daddr 10.0.0.11 tcp dport {9091, 9092} ct state new accept
    ```

  - To access kubernetes port-forwarding feature from my laptop connected to home network, the following rule need to be enable:
    ```
    # 250 port-forwarding from wan
    iifname $wan_interface oifname $lan_interface ip daddr 10.0.0.11 tcp dport 8080 ct state new accept
    ``` 
    
    This rule enables incoming traffic to node1 in port 8080 which can be used to configure port-forward feature to access to any service.

    ```shell
    kubectl port-forward svc/[service-name] -n [namespace] [external-port]:[internal-port] --addess 0.0.0.0
    ```

  {{site.data.alerts.end}}

- NAT pre-routing rules

  `/etc/nftables.d/nat-prerouting.nft`
  ```
  chain prerouting {
          # 000 policy
          type nat hook prerouting priority 0;
    }

  ```

- NAT post-routing rules
  `/etc/nftables.d/nat-postrouting.nft`
  ```
  chain postrouting {
          # 000 policy
          type nat hook postrouting priority 100;
          # 005 masquerade lan to wan
          ip saddr $lan_network oifname $wan_interface masquerade
    }

  ```
  

{{site.data.alerts.important}} **About iptables rules persistency**


In Ubuntu for having iptables persistent rules across reboots `iptables-persistent` and `netfilter-persistent` packages need to be installed.

`netfilter-persistent` systemd service is in charge to save the rules during shutdown and load on startup

Rules can be saved on demand using the command:

```shell
sudo netfilter-persistent save
```
Rules are stored in the following location:

`/etc/iptables/rules.v[4-6]`

{{site.data.alerts.end}}

### Configuring Ansible Role

nftables default rules establish by the role can be updated by changing roles variables for `gateway` host (see `gateway` host variables in [`ansible/host_vars/gateway.yml`]({{ site.git_edit_address }}/ansible/host_vars/gateway.yml) file)

The rules configured for `gateway` allow incoming traffic (icmp, http, https, iscsi, ssh, dns, dhcp, ntp and snmp) and forward http, https, ssh, dns and ntp traffic.


### Configuring static routes to access to cluster from home network

To acess to the cluster nodes from my home network a static route need to be added for using `gateway` as router of my lab network (10.0.0.0/24)

This route need to be added to my Laptop and the VM running `pimaster` node

- Adding static route in my Windows laptop

  Open a command:

  ```dos
  ROUTE -P ADD 10.0.0.0 MASK 255.255.255.0 192.168.1.11 METRIC 1
  ```

- Adding static route in Linux VM running on my laptop (VirtualBox)
  
  Modify `/etc/netplan/50-cloud-init.yaml` for adding the static route
    
  ```yml 
  network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: no
      addresses: [192.168.56.20/24] #Host Only VirtualBox network
    enp0s8:
      dhcp4: yes # Home network IP address
      routes:
      - to: 10.0.0.0/24 #Cluster Lab Network
        via: 192.168.1.11 #`gateway` static ip address in home network        
  ```
  {{site.data.alerts.note}}

  This is `pimaster` VirutalBOX network configuration:
  - **Eth0** (enp0s3) connected to VBox **Host-Only adapter** (laptop only connection)
  - **Eth1** (enp0s8) connected to VBox **Bridge adapter** (home network connection)

  {{site.data.alerts.end}}  

## DHCP/DNS Configuration

`dnsmasq` will be used as lightweigh DHCP/DNS server
For automating configuration tasks, ansible role [**ricsanfre.dnsmasq**](https://galaxy.ansible.com/ricsanfre/dnsmasq) has been developed.

- Step 1. Install dnsmasq

  ```shell
  sudo apt install dnsmasq
	```

- Step 2. Configure dnsmasq

  Edit file `/etc/dnsmasq.d/dnsmasq.conf`

  ```
  # Our DHCP service will be providing addresses over our eth0 adapter
  interface=eth0

  # We will listen on the static IP address we declared earlier
  listen-address= 10.0.0.1

  # Pre-allocate a bunch of IPs on the 10.0.0.0/8 network for the Raspberry Pi nodes
  # DHCP will allocate these for 12 hour leases, but will always assign the same IPs to the same Raspberry Pi
  # devices, as you'll populate the MAC addresses below with those of your actual Pi ethernet interfaces

  dhcp-range=10.0.0.32,10.0.0.128,12h

  # DNS nameservers
  server=80.58.61.250
  server=80.58.61.254

  # Bind dnsmasq to the interfaces it is listening on (eth0)
  bind-interfaces

  # Never forward plain names (without a dot or domain part)
  domain-needed

  local=/picluster.ricsanfre.com/

  domain=picluster.ricsanfre.com

  # Never forward addresses in the non-routed address spaces.
  bogus-priv

  # Do not use the hosts file on this machine
  # expand-hosts

  # Useful for debugging issues
  # log-queries
  # log-dhcp

  # DHCP configuration based on inventory
  dhcp-host=e4:5f:01:28:36:98,10.0.0.1
  dhcp-host=08:00:27:f3:6b:dd,10.0.0.10
  dhcp-host=dc:a6:32:9c:29:b9,10.0.0.11
  dhcp-host=e4:5f:01:2d:fd:19,10.0.0.12
  dhcp-host=e4:5f:01:2f:49:05,10.0.0.13
  dhcp-host=e4:5f:01:2f:54:82,10.0.0.14
  dhcp-host=e4:5f:01:d9:ec:5c,10.0.0.15

  # Adding additional DHCP hosts
  # Ethernet Switch
  dhcp-host=94:a6:7e:7c:c7:69,10.0.0.2

  # DNS configuration based on inventory
  host-record=gateway.picluster.ricsanfre.com,10.0.0.1
  host-record=pimaster.picluster.ricsanfre.com,10.0.0.10
  host-record=node1.picluster.ricsanfre.com,10.0.0.11
  host-record=node2.picluster.ricsanfre.com,10.0.0.12
  host-record=node3.picluster.ricsanfre.com,10.0.0.13
  host-record=node4.picluster.ricsanfre.com,10.0.0.14
  host-record=node5.picluster.ricsanfre.com,10.0.0.15

  # Adding additional DNS
  # NTP Server
  host-record=ntp.picluster.ricsanfre.com,10.0.0.1
  # DNS Server
  host-record=dns.picluster.ricsanfre.com,10.0.0.1
  ```

  {{site.data.alerts.note}}

  Additional DNS records can be added for the different services exposed by the cluster. For example:

  - S3 service DNS name pointing to `node1`
    ```
    # S3 Server
    host-record=s3.picluster.ricsanfre.com,10.0.0.11
    ```
  - Monitoring DNS service pointing to Ingress Controller IP address (from MetaLB pool)
    ```
    # Monitoring
    host-record=monitoring.picluster.ricsanfre.com,10.0.0.100
    ```
  {{site.data.alerts.end}}

- Step 3. Restart dnsmasq service

  ```shell
  sudo systemctl restart dnsmasq
  ```

### Configuring Ansible Role

DHCP static IP leases and DNS records are taken automatically from ansible inventory file for those hosts with `ip`, `hostname` and `mac` variables are defined. See [`ansible/inventory.yml`]({{ site.git_edit_address }}/ansible/inventory.yml) file.

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

DNS/DHCP specific configuration, dnsmasq role variables for `gateway` host, are located in [`ansible/host_vars/gateway.yml`]({{ site.git_edit_address }}/ansible/host_vars/gateway.yml) file.

### Useful Commands

1. Check DHCP leases in DHCP server

   See file `/var/lib/misc/dnsmasq.leases`
	
2. Check DHCP lease in DHCP Clients

   See file `/var/lib/dhcp/dhclient.leases`
	
3. Release DHCP current lease (DHCP client)
   
   ```shell
   sudo dhclient -r <interface>
   ```
	
4. Obtain a new DHCP lease (DHCP client)

   ```shell
   sudo dhclient <interface>
	 ```

5. Relesase DHCP lease (DHCP server)

   ```shell
   sudo dhcp_release <interface> <address> <MAC address> <client_id>
   ```

   `<interface>`, `<address>` , `<MAC address>` and `<client_id>` are columns in file `/var/lib/misc/dnsmasq.leases`

   ```shell
   cat `/var/lib/misc/dnsmasq.leases`
   1662325792 e4:5f:01:2f:54:82 10.0.0.14 node4 ff:ce:f0:c5:95:00:02:00:00:ab:11:1d:5c:ee:f7:30:5a:1c:c3
   1662325794 e4:5f:01:2d:fd:19 10.0.0.12 node2 ff:59:1d:0c:2c:00:02:00:00:ab:11:a2:0c:7b:67:b5:0d:a0:b6
   1662325795 e4:5f:01:2f:49:05 10.0.0.13 node3 ff:2b:f0:10:76:00:02:00:00:ab:11:f4:83:c3:e4:cd:06:92:25
   1662325796 dc:a6:32:9c:29:b9 10.0.0.11 node1 ff:38:f0:78:87:00:02:00:00:ab:11:f1:8d:67:ed:9f:35:f9:9b
   ```
 
   Format in the file is:

   ```shell
   <lease_expire_time_stamp> <MAC address> <address> <hostname> <client_id>
   ```

### Additional connfiguration: Updating DNS resolver

Ubuntu 20.04 comes with systemd-resolved service that provides a DNS stub resolver on Ubuntu 20.04. A stub resolver is a small DNS client running on the server that provides network name resolution to local applications and implements a DNS caching.

The DNS servers contacted are determined from the global settings in /etc/systemd/resolved.conf, the per-link static settings in `/etc/systemd/network/*.network` files, the per-link dynamic settings received over DHCP, information provided via resolvectl(1), and any DNS server information made available by other system services.

All nodes of the cluster will receive the configuration of the DNS server in the cluster (dnsmasq running in `gateway` node) from DHCP. But `gateway` node need to be configured to use local dnsmaq service instead of the default DNS servers  received by the DCHP connection to my home network (my home network configuration).

To check the name server used by the local resolver run:

```shell
systemd-resolve --status
```

To specify the dns server to be used modify the file `/etc/systemd/resolved.conf`

Add the following lines
```
[Resolve]
DNS=10.0.0.1
Domains=picluster.ricsanfre.com
```

Restart systemd-resolve service

```shell
sudo systemctl restart systemd-resolved
```

## NTP Server Configuration

Ubuntu by default uses `timedatectl` / `timesyncd` to synchronize time and users can optionally use `chrony` to serve the Network Time Protocol
From Ubuntu 16.04 timedatectl / timesyncd (which are part of systemd) replace most of ntpdate / ntp.
(https://ubuntu.com/server/docs/network-ntp)

Since ntp and ntpdate are deprecated **chrony** package will be used for configuring NTP synchronization.

**gateway** will be hosting a NTP server and the rest of cluster nodes will be configured as NTP Clients.

For automating ntp configuration tasks on all nodes (gateway and node1-5), ansible role [**ricsanfre.ntp**](https://galaxy.ansible.com/ricsanfre/ntp) has been created.

- Step 1. Install chrony

  ```shell
  sudo apt install chrony
  ```

- Step 2. Configure chrony

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

  - In **node1-5**:

    Configure gateway as NTP server
   
    ```
    server 10.0.0.1
    ```

### Chrony commands

Check time synchronization with Chronyc

1. Confirm that NTP is enabled

   ```shell
    timedatectl
	 ```

2. Checking Chrony is running and view the peers and servers to which it is connected
    
	 ```shell
   chronyc activity
	 ```

3. To view a detailed list of time servers, their IP addresses, time skew, and offset
    
	 ```shell
   chronyc sources
	 ```

4. Confirm that the chrony is synchronized
   
   ```shell
   chronyc tracking
	 ```

## iSCSI configuration. Centralized SAN

`gateway` has to be configured as iSCSI Target to export LUNs mounted by `node1-node5`

iSCSI configuration in `gateway` has been automated developing a couple of ansible roles: **ricsanfre.storage** for managing LVM and **ricsanfre.iscsi_target** for configuring a iSCSI target.

Specific `gateway` ansible variables to be used by these roles are stored in [`ansible/vars/centralized_san/centralized_san_target.yml`]({{ site.git_edit_address }}/ansible/vars/centralized_san/centralized_san_target.yml)

Further details about iSCSI configurations and step-by-step manual instructions are defined in ["Cluster SAN installation"](/docs/san/).

`gateway` exposes a dedicated LUN of 100 GB for each of the clusters nodes.