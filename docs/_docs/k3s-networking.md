---
title: K3S Networking
permalink: /docs/k3s-networking/
description: How to configure K3S networking inour Raspberry Pi Kubernetes cluster. How to disable default K3s load balancer and configure Metal LB.
last_modified_at: "21-07-2022"
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

Traefik is a modern HTTP reverse proxy and load balancer made to deploy microservices with ease. It simplifies networking complexity while designing, deploying, and running applications.

## Metal LB as Cluster Load Balancer

Instead of using the embeded service load balancer that only comes with K3S, a more generic kubernetes load balancer like [Metal LB](https://metallb.universe.tf/) will be used. This load balancer can be used with almost any distribution of kubernetes.

In order to use Metal LB, K3S embedded Klipper Load Balancer must be disabled: K3s server installation  option `--disable servicelb`.

K3S fresh installation (disabling embedded service load balanced) the following pods and services are started by default:

```shell
kubectl get pods --all-namespaces
NAMESPACE     NAME                                      READY   STATUS      RESTARTS   AGE
kube-system   metrics-server-86cbb8457f-k52mz           1/1     Running     0          7m45s
kube-system   local-path-provisioner-5ff76fc89d-qzfpp   1/1     Running     0          7m45s
kube-system   coredns-7448499f4d-wk4sd                  1/1     Running     0          7m45s
kube-system   helm-install-traefik-crd-5r72x            0/1     Completed   0          7m46s
kube-system   helm-install-traefik-86kpb                0/1     Completed   2          7m46s
kube-system   traefik-97b44b794-vtj7x                   1/1     Running     0          5m24s

kubectl get services --all-namespaces
NAMESPACE     NAME             TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
default       kubernetes       ClusterIP      10.43.0.1       <none>        443/TCP                      8m32s
kube-system   kube-dns         ClusterIP      10.43.0.10      <none>        53/UDP,53/TCP,9153/TCP       8m29s
kube-system   metrics-server   ClusterIP      10.43.169.140   <none>        443/TCP                      8m28s
kube-system   traefik          LoadBalancer   10.43.50.56     <pending>     80:30582/TCP,443:30123/TCP   5m53s
```

### Why Metal LB

Kubernetes does not offer an implementation of network load balancers (Services of type LoadBalancer) for bare-metal clusters. The implementations of network load balancers that Kubernetes does ship with are all glue code that calls out to various IaaS platforms (GCP, AWS, Azure…). In bare-metal kubernetes clusters, like the one I am building, "LoadBalancer" services will remain in the “pending” state indefinitely when created.
(see in previous output of `kubectl get services` command how `traefik` LoadBAlancer service "External IP" is "pending")

For Bare-metal cluster only two optios remain availale for managing incoming traffic to the cluster: “NodePort” and “externalIPs” services. Both of these options have significant downsides for production use, which makes bare-metal clusters second-class citizens in the Kubernetes ecosystem.

MetalLB provides a network load balacer that can be integrated with standard network equipment, so that external services on bare-metal clusters can be accesible using a pool of "external" ip addresses.

### How Metal LB works

MetalLB can work in two modes, BGP and Layer 2. The major advantage of the layer 2 mode is its universality: it will work on any Ethernet network. In BGP mode specific routers are needed to deploy the solution.

In [layer 2 mode](https://metallb.universe.tf/concepts/layer2/), one node assumes the responsibility of advertising a particular kuberentes service (LoadBalance type) to the local network, this is call the `leader` node. From the network’s perspective, it simply looks like that node has multiple IP addresses assigned to its network interface and it just responds to ARP requests for IPv4 services, and NDP requests for IPv6.

When configuring MetalLB in layer 2 mode, all traffic for a service IP goes to the leader node. From there, kube-proxy spreads the traffic to all the service’s pods. Thus MetalLB layer 2 really does not implement a load balancer. Rather, it implements a failover mechanism so that a different node can take over should the current leader node fail for some reason.

MetalLB consists of two different pods:

- Controller: resposible for handling IP address assigments from a configured Pool.
- Speaker: DaemonSet pod running on each worker node, resposible for announcing the allocated IPs.


![metal-lb-architecture](/assets/img/metallb_architecture.png)


### Requesting Specific IPs

MetalLB respects the Kubernetes service `spec.loadBalancerIP` parameter, so if a static IP address from the available pool need to be set up for a specific service, it can be requested by setting that parameter. If MetalLB does not own the requested address, or if the address is already in use by another service, assignment will fail and MetalLB will log a warning event visible in `kubectl describe service <service name>`.


### Install Metal Load Balancer


Installation using `Helm` (Release 3):

- Step 1: Add the Metal LB Helm repository:
  
    ```shell
    helm repo add metallb https://metallb.github.io/metallb
    ```

- Step 2: Fetch the latest charts from the repository:

    ```shell
    helm repo update
    ```

- Step 3: Create namespace

    ```shell
    kubectl create namespace metallb-system
    ```

- Step 4: Install Metallb in the metallb-system namespace.

    ```shell
    helm install metallb metallb/metallb --namespace metallb-system
    ```
  
  
- Step 5: Confirm that the deployment succeeded, run:

    ```shell
    kubectl -n metallb-system get pod
    ```

- Step 6: Configure IP addess pool and the announcement method (L2 configuration)

  Create the following manifest file: `metallb-config.yaml`
    ```yml
    ---
    # Metallb address pool
    apiVersion: metallb.io/v1beta1
    kind: IPAddressPool
    metadata:
      name: picluster-pool
      namespace: metallb-system
    spec:
      addresses:
      - 10.0.0.100-10.0.0.200

    ---
    # L2 configuration
    apiVersion: metallb.io/v1beta1
    kind: L2Advertisement
    metadata:
      name: example
      namespace: metallb-system
    spec:
      ipAddressPools:
      - picluster-pool

    ```
   
   Apply the manifest file

   ```shell
   kubectl apply -f metallb-config.yaml
   ```

    After a while, metallb is deployed and traefik LoadBalancer service gets its externa-ip from the configured pool and is accessible from outside the cluster

    ```shell
    kubectl get services --all-namespaces
    NAMESPACE     NAME             TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
    default       kubernetes       ClusterIP      10.43.0.1       <none>        443/TCP                      63m
    kube-system   kube-dns         ClusterIP      10.43.0.10      <none>        53/UDP,53/TCP,9153/TCP       63m
    kube-system   metrics-server   ClusterIP      10.43.169.140   <none>        443/TCP                      63m
    kube-system   traefik          LoadBalancer   10.43.50.56     10.0.0.100    80:30582/TCP,443:30123/TCP   60m
    ```
{{site.data.alerts.important}}

  In previous chart releases there was a way to configure MetallB in deployment time providing the following values.yaml:
  
  ```yml
    configInline:
      address-pools:
        - name: default
            protocol: layer2
            addresses:
              - 10.0.0.100-10.0.0.200
  ```
  Helm chart `configInline` in `values.yaml` has been deprecated since MetalLB 0.13.
  Configuration must be done creating the corresponding MetalLB Kubernets CRD (`IPAddressPool` and `L2Advertisement`). See [MetalLB configuration documentation](https://metallb.universe.tf/configuration/).

{{site.data.alerts.end}}