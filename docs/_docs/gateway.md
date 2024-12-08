---
title: Cluster Gateway (Ubuntu OS)
permalink: /docs/gateway/
description: How to configure a Raspberry Pi as router/firewall for our Kubernetes Cluster, runing Ubuntu OS, providing connectivity and basic services (DNS, DHCP, NTP, SAN).
last_modified_at: "03-02-2024"
---

One of the Raspeberry Pi (2GB), **gateway**, is used as Router and Firewall for the home lab, isolating the raspberry pi cluster from my home network.
It will also provide DNS, NTP and DHCP services to my lab network.

This Raspberry Pi (gateway), is connected to my home network using its WIFI interface (wlan0) and to the LAN Switch using the eth interface (eth0).

In order to ease the automation with Ansible, OS installed on **gateway** is the same as the one installed in the nodes of the cluster: Ubuntu 22.04 64 bits.


## Storage Configuration

`gateway` node is based on a Raspberry Pi 4B 2GB booting from a USB Flash Disk.


## Network Configuration

The WIFI interface (wlan0) will be used to be connected to my home network using static IP address (192.168.1.11/24), while ethernet interface (eth0) will be connected to the lan switch, lab network, using static IP address (10.0.0.1/24)
Static IP addres in home network, will enable the configuration of static routes in my labtop and VM running on it (`pimaster`) to access the cluster nodes without fisically connect the laptop to the lan switch with an ethernet cable. 


## Unbuntu OS instalation

Ubuntu can be installed on Raspbery PI using a preconfigurad cloud image that need to be copied to SDCard or USB Flashdisk/SSD.

Raspberry Pis will be configured to boot Ubuntu OS from USB conected disk (Flash Disk or SSD disk). The initial Ubuntu 22.04 LTS configuration on a Raspberry Pi 4 will be automated using cloud-init.

In order to enable boot from USB, Raspberry PI firmware might need to be updated. Follow the producedure indicated in ["Raspberry PI - Firmware Update"](/docs/firmware/).

The installation procedure followed is the described in ["Ubuntu OS Installation"](/docs/ubuntu/rpi/) using cloud-init configuration files (`user-data` and `network-config`) for `gateway`.

`user-data` depends on the storage architectural option selected::

| User Data | 
|--------------------|
|  [user-data]({{ site.git_edit_address }}/metal/rpi/cloud-init/gateway/user-data) | 
{: .table .border-dark }

`network-config` is the same in both architectures:


| Network configuration |
|---------------------- |
| [network-config]({{ site.git_edit_address }}/metal/rpi/cloud-init/gateway/network-config) |
{: .table .border-dark }


### cloud-init: network configuration


Ubuntu's netplan yaml configuration file used, part of cloud-init boot `/boot/network-config` is the following:

```yml
version: 2
ethernets:
  eth0:
    dhcp4: false
    dhcp6: false
    optional: true
    addresses: 
     - 10.0.0.1/24
wifis:
  wlan0:
    dhcp4: false
    dhcp6: false
    optional: true
    access-points:
      <SSID_NAME>:
        password: <SSID_PASSWD>
    addresses: 
     - 192.168.1.11/24
    routes:
      - to: default
        via: 192.168.1.1
    nameservers:
      addresses:
        - 1.1.1.1
        - 8.8.8.8
      search:
        - homelab.ricsanfre.com
```

It assigns static IP address 10.0.0.1 to eth0 port and configures wifi interface (wlan0) to have static IP address in home network (192.168.1.1). DNS servers of my ISP are also configured.

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

`dnsmasq` will be used as lightweight DHCP/DNS server.

DNS configured as Resolver/Forwarder. See more details in [PiCluster - DNS Architecture](/docs/dns/).


For automating configuration tasks, ansible role [**ricsanfre.dnsmasq**](https://galaxy.ansible.com/ricsanfre/dnsmasq) has been developed.

Manual installation process is the following:

- Step 1. Install dnsmasq

  ```shell
  sudo apt install dnsmasq
	```

- Step 2. Configure dnsmasq

  Edit file `/etc/dnsmasq.d/dnsmasq.conf`

  ```
  # Our DHCP/DNS service will be providing services over eth0 adapter
  interface=eth0

  # We will listen on the static IP address we declared earlier
  listen-address= 10.0.0.1

  # DHCP IP range
  dhcp-range=10.0.0.100,10.0.0.249,12h

  # Upstream nameservers
  server=/homelab.ricsanfre.com/10.0.11
  server=1.1.1.1
  server=8.8.8.8

  # Bind dnsmasq to the interfaces it is listening on (eth0)
  bind-interfaces

  # Never forward plain names (without a dot or domain part)
  domain-needed

  domain=picluster.ricsanfre.com

  # Never forward addresses in the non-routed address spaces.
  bogus-priv

  # Do not use the hosts file on this machine
  # expand-hosts

  # Useful for debugging issues
  # log-queries
  # log-dhcp

- Step 3. Restart dnsmasq service

  ```shell
  sudo systemctl restart dnsmasq
  ```

### Configuring Ansible Role

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
