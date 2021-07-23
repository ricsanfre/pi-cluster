# Use ip and ss Commands

`ifconfig` and `netstat` commands are not installed by default on Ubuntu 20.04. Installation of package net-tools is needed for using those commands.

Use alternative commands `ip` and `ss` instead.


For example, to display a list of network interfaces, run the ss command instead of netstat. To display information for IP addresses, run the ip addr command instead of ifconfig -a.

Examples are as follows:

```
USE THIS IPROUTE COMMAND     INSTEAD OF THIS NET-TOOL COMMAND
ip addr                      ifconfig -a
ss                           netstat
ip route                     route
ip maddr                     netstat -g
ip link set eth0 up          ifconfig eth0 up
ip -s neigh                  arp -v
ip link set eth0 mtu 9000    ifconfig eth0 mtu 9000
```

Examples are as follows:

```
ip neigh
198.51.100.2 dev eth0 lladdr 00:50:56:e2:02:0f STALE
198.51.100.254 dev eth0 lladdr 00:50:56:e7:13:d9 STALE
198.51.100.1 dev eth0 lladdr 00:50:56:c0:00:08 DELAY

arp -a
? (198.51.100.2) at 00:50:56:e2:02:0f [ether] on eth0
? (198.51.100.254) at 00:50:56:e7:13:d9 [ether] on eth0
? (198.51.100.1) at 00:50:56:c0:00:08 [ether] on eth0
```
