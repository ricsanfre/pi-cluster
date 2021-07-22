# Gateway Configuration

One of the Raspeberry Pi (2GB), **gateway**, is used as Router and Firewall for the home lab, isolating the raspberry pi cluster from my home network.
It will also provide DNS, NTP and DHCP services to my lab network. 
This Raspberry Pi (gateway), is connected to my home network using its WIFI interface (wlan0) and to the LAN Switch using the eth interface (eth0).

In order to ease the automation with Ansible, OS installed on **gateway** is the same as the one installed in the nodes of the cluster (**node1-node4**): Ubuntu 20.04.2 64 bits.

## Network Configuration

The WIFI interface (wlan0) will be used to be connected to my home lab (dynamic IP using DHCP), while ethernet interface (eth0) will be connected to the lan switch (static IP address)

Ubuntu's netplan yaml configuration file used, part of cloud-init boot `/boot/network-config` is like:

```
version: 2
ethernets:
  eth0:
    dhcp4: false
    addresses: [10.0.0.1/24]
wifis:
  wlan0:
    dhcp4: true
    optional: true
    access-points:
      "<SSID_NAME>":
        password: "<SSID_PASSWD>"
```

## Router/Firewall Configuration

For automating configuration tasks, **ansible role router** has been created.

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

In Ubuntu 20.04 applying this procedure does not make the rules to persit acroos reboots. Moreover since Ubuntu 20.10 **nftables** package is used instead iptables.
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

nftables rules can be updated by changing roles variables:

```
# In Accepting rules HTTP, HTTPS, SSH, DNS, DHCP, NTP
in_tcp_accept: '{ http, https, ssh }'
in_udp_accept: '{ 53, 67, 68, 123 }'

# Forwarding Accepting rules
forward_tcp_accept: '{ http, https, ssh }'
forward_udp_accept: '{ domain, ntp }'
```

## DHCP/DNS Configuration

**dnsmasq** will be used as lightweigh DHCP/DNS server
For automating configuration tasks, **ansible role dnsmasq** has been created.

### Step 1. Install dnsmasq

    sudo apt install dnsmasq
	
### Step 2. Configure dnsmasq

Edit file `/etc/dnsmasq.d/dnsmasq.conf`

```
TBD: CONTENT dnsmasq.conf
```

### Configuring Ansible Role

DHCP static IP leases and DNS registers are taken automatically from ansible inventory file.

```
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

Local cluster domain name and relay DNS servers can be configured.

```
# Cluster lodal domain
cluster_domain_name: cluster

# Home network DNS servers
home_dns_servers:
  - 80.58.61.250
  - 80.58.61.254

```

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

For automating ntp configuration tasks on all nodes (gateway and node1-4), **ansible role ntp** has been created.

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
