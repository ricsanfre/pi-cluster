---
title: K3S Networking
permalink: /docs/k3s-networking/
description: Description of K3S default networking components and how they can be configured.
last_modified_at: "17-01-2023"
---

{{site.data.alerts.note}}
Basic kubernetes networking concepts and useful references can be found in [Reference Docs: Kubernetes networking basics](/docs/k8s-networking/) 
{{site.data.alerts.end}}

## K3S networking default add-ons

By default K3s install and configure basic Kubernetes networking packages:

- [Flannel](https://github.com/flannel-io/flannel) as Networking plugin, CNI (Container Networking Interface), for enabling pod communications
- [CoreDNS](https://coredns.io/) providing cluster dns services
- [Traefik](https://traefik.io/) as ingress controller
- [Klipper Load Balancer](https://github.com/k3s-io/klipper-lb) as embedded Service Load Balancer

## Flannel as CNI

K3S run by default with flannel as the CNI, using VXLAN as the default backend. Flannel is running as backend `go` routine within k3s unique process

k3s server installation options can be provided in order to configure Network CIDR to be used by PODs ans Services and the flannel backend to be used.

| k3s server option | default value | Description |
| ----- | ---- |---- |
| `--cluster-cidr value` | “10.42.0.0/16” | Network CIDR to use for pod IPs
| `--service-cidr value` | “10.43.0.0/16” | Network CIDR to use for services IPs
| `--flannel-backend value` | “vxlan” | ‘none’ to disable or ‘vxlan’, ‘ipsec’, ‘host-gw’, or ‘wireguard’
{: .table }

By default, flannel will have a 10.42.X.0/24 subnet allocated to each node (X=0, 1, 2, 3, etc.), K3S Pod will use IP address from subnet's address space.

When Flannel is running it creates the following interfaces in eah node:

- a network device `flannel.1` as VTEP (VXLAN Tunnel End Point) device.

    ```shell
    oss@node1:~$ ip -d addr show flannel.1
    4: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN group default
        link/ether 5e:08:1d:56:15:e3 brd ff:ff:ff:ff:ff:ff promiscuity 0 minmtu 68 maxmtu 65535
        vxlan id 1 local 10.0.0.11 dev eth0 srcport 0 0 dstport 8472 nolearning ttl auto ageing 300 udpcsum noudp6zerocsumtx noudp6zerocsumrx numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
        inet 10.42.0.0/32 scope global flannel.1
        valid_lft forever preferred_lft forever
        inet6 fe80::5c08:1dff:fe56:15e3/64 scope link
    ```
- and a bridge interface `cni0` with ip address 10.42.X.1/24

    ```shell
    oss@node1:~$ ip -d addr show cni0
    5: cni0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UP group default qlen 1000
        link/ether 72:0e:b2:60:e6:23 brd ff:ff:ff:ff:ff:ff promiscuity 0 minmtu 68 maxmtu 65535
        bridge forward_delay 1500 hello_time 200 max_age 2000 ageing_time 30000 stp_state 0 priority 32768 vlan_filtering 0 vlan_protocol 802.1Q bridge_id 8000.72:e:b2:60:e6:23 designated_root 8000.72:e:b2:60:e6:23 root_port 0 root_path_cost 0 topology_change 0 topology_change_detected 0 hello_timer    0.00 tcn_timer    0.00 topology_change_timer    0.00 gc_timer  242.68 vlan_default_pvid 1 vlan_stats_enabled 0 vlan_stats_per_port 0 group_fwd_mask 0 group_address 01:80:c2:00:00:00 mcast_snooping 1 mcast_router 1 mcast_query_use_ifaddr 0 mcast_querier 0 mcast_hash_elasticity 16 mcast_hash_max 4096 mcast_last_member_count 2 mcast_startup_query_count 2 mcast_last_member_interval 100 mcast_membership_interval 26000 mcast_querier_interval 25500 mcast_query_interval 12500 mcast_query_response_interval 1000 mcast_startup_query_interval 3124 mcast_stats_enabled 0 mcast_igmp_version 2 mcast_mld_version 1 nf_call_iptables 0 nf_call_ip6tables 0 nf_call_arptables 0 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
        inet 10.42.0.1/24 brd 10.42.0.255 scope global cni0
        valid_lft forever preferred_lft forever
        inet6 fe80::700e:b2ff:fe60:e623/64 scope link
        valid_lft forever preferred_lft forever
    ```

Traffics between cni0 and flannel.1 are forwarded by ip routing enabled in the node

![flannel](/assets/img/flannel.png)

## CoreDNS

k3s server installation options can be provided in order to configure coreDNS

| k3s server option | default value | Description |
| ----- | ---- |---- |
| `--cluster-dns value` | “10.43.0.10”	| Cluster IP for coredns service. Should be in your service-cidr range
| `--cluster-domain value` | “cluster.local” | Cluster Domain
{: .table }

## Traefik as Ingress Controller

[Traefik](https://traefik.io/) is a modern HTTP reverse proxy and load balancer made to deploy microservices with ease. It is embedded in K3s installatio and deployed by default when starting K3s cluster.

Traefik K3S add-on is disabled during K3s installation, so it can be installed manually to have full control over the version and its initial configuration.

To disable embedded Traefik, install K3s with `--disable traefik` option.

Further details about how to configure Traefik can be found in ["Ingress-Controller Traefik documentation"](/docs/traefik).

## Klipper-LB as Load Balancer

[Klipper Load Balancer](https://github.com/k3s-io/klipper-lb) is deployed by default when starting the k3s cluster.
In the cluster, Metal LB load balancer will be used so it is needed to disable Klipper-LB first.
To disable the embedded LB, configure all servers in the cluster with the `--disable servicelb` option.

Further details about how to install Metal LB can be found in ["Load Balancer (Metal LB) documentation"](/docs/traefik).
