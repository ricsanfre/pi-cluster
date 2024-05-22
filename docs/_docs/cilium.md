---
title: Cilium CNI
permalink: /docs/cilium/
description: How to install Cilium CNI in the picluster.
last_modified_at: "17-01-2023"
---

[Cilium](https://cilium.io/) is an open source, cloud native solution for providing, securing, and observing network connectivity between workloads, fueled by the revolutionary Kernel technology [eBPF](https://ebpf.io/)

Within a Kubernetes cluster Cilium can be deployed as,

- High performance CNI

  
  See details in [Cilium Use-case: Layer 4 Load Balancer](https://cilium.io/use-cases/load-balancer/)


- Kube-proxy replacement
  
  Kube-proxy is a component running in the nodes of the cluster which provides load-balancing traffic targeted to kubernetes services (via Cluster IPs and Node Ports), routing the traffic to the proper backend pods.
  
  Cilium can be used to replace kube-proxy component, replacing traditional iptables based kube-proxy routing, by [eBFP](https://ebpf.io/).

  See details in [Cilium Use-case: Kube-proxy Replacement](https://cilium.io/use-cases/kube-proxy/)

- Layer 4 Load Balancer
 
  Software based load-balancer for the kubernetes cluster.

  able to announce the routes using BGP or L2 protocols

  Cilium's LB IPAM is a feature that allows Cilium to assign IP addresses to Kubernetes Services of type LoadBalancer.

  Once IP address is asigned, Cilium can advertise those assigned IPs, through BGP or L2 announcements, so traffic can be routed to cluster services from the exterior (Nort-bound traffic: External to Pod)

  See details in [Cilium Use-case: Layer 4 Load Balancer](https://cilium.io/use-cases/load-balancer/)

{{site.data.alerts.note}}

For further information about basic networking in Kuberenetes check out ["Kubernetes networking basics"](/docs/k8s-networking/).

{{site.data.alerts.end}}

In the Pi Cluster, Cilium can be used as a replacement for the following networking components of in the cluster

- Flannel CNI, installed by default by K3S, which uses an VXLAN overlay as networking protocol. Cilium CNI networking using eBPF technology.
  
- Kube-proxy, so eBPF based can be used to increase performance.

- Metal-LB, load balancer. MetalLB was used for LoadBalancer IP Address Management (LB-IPAM) and L2 announcements for Address Resolution Protocol (ARP) requests over the local network. 
  Cilium 1.13 introduced LB-IPAM support and 1.14 added L2 announcement capabilities, making possible to replace MetalLB in my homelab. My homelab does not have a BGP router and so new L2 aware functionality can be used.


## K3S installation

By default K3s install and configure basic Kubernetes networking packages:

- [Flannel](https://github.com/flannel-io/flannel) as Networking plugin, CNI (Container Networking Interface), for enabling pod communications
- [CoreDNS](https://coredns.io/) providing cluster dns services
- [Traefik](https://traefik.io/) as ingress controller
- [Klipper Load Balancer](https://github.com/k3s-io/klipper-lb) as embedded Service Load Balancer


K3S master nodes need to be installed with the following additional options

- `--flannel-backend=none`: to disable Fannel instalation
- `--disable-network-policy`: Most CNI plugins come with their own network policy engine, so it is recommended to set --disable-network-policy as well to avoid conflicts.
- `--disable-kube-proxy`: to disable kube-proxy installation
- `--disable servicelb` to disable default service load balancer installed by K3S (Klipper Load Balancer). Cilium will be used instead.

See complete intallation procedure and other configuration settings in ["K3S Installation"](/docs/k3s-installation/)


{{site.data.alerts.note}}

After instalallation, since CNI plugin has not been yet installed, kubernetes nodes will be in `NotReady` status, and any Pod (CoreDNS or metric-service) in `Pending` status.

{{site.data.alerts.end}}

## Cilium Installation

Installation using `Helm` (Release 3):

- Step 1: Add Cilium Helm repository:

    ```shell
    helm repo add cilium https://helm.cilium.io/
    ```
- Step2: Fetch the latest charts from the repository:

    ```shell
    helm repo update
    ```
- Step 3: Create namespace

    ```shell
    kubectl create namespace nginx
    ```
- Step 4: Create helm values file `cilium-values.yml`

  ```yml
  # Increase the k8s api client rate limit to avoid being limited due to increased API usage 
  k8sClientRateLimit:
    qps: 50
    burst: 200


  # Avoid having to manually restart the Cilium pods on config changes 
  operator:
  # replicas: 1  # Uncomment this if you only have one node
    rollOutPods: true
    
    # Install operator on master node
    nodeSelector:
      node-role.kubernetes.io/master: "true"

  rollOutCiliumPods: true

  # K8s API service
  k8sServiceHost: 10.0.0.11
  k8sServicePort: 6443

  # Replace Kube-proxy
  kubeProxyReplacement: true
  kubeProxyReplacementHealthzBindAddr: 0.0.0.0:10256

  # -- Configure IP Address Management mode.
  # ref: https://docs.cilium.io/en/stable/network/concepts/ipam/
  ipam:
    operator:
      clusterPoolIPv4PodCIDRList: "10.42.0.0/16"

  l2announcements:
    enabled: true

  externalIPs:
    enabled: true

  ```

- Step 5: Install Cilium in kube-system namespace

    ```shell
    helm install cilium cilium/cilium --namespace kube-system -f cilium-values.yaml
    ```

- Step 6: Confirm that the deployment succeeded, run:

    ```shell
    kubectl -n kube-system get pod
    ```

### Helm chart configuration details

TBD

### Configure LB-IPAM


- Step 1: Configure IP addess pool and the announcement method (L2 configuration)

  Create the following manifest file: `cilium-config.yaml`
    ```yml
    ---
    apiVersion: "cilium.io/v2alpha1"
    kind: CiliumLoadBalancerIPPool
    metadata:
      name: "first-pool"
      namespace: kube-system
    spec:
      blocks:
        - start: "10.0.0.100"
          stop: "10.0.0.200"

    ---
    apiVersion: cilium.io/v2alpha1
    kind: CiliumL2AnnouncementPolicy
    metadata:
      name: default-l2-announcement-policy
      namespace: kube-system
    spec:
      externalIPs: true
      loadBalancerIPs: true

    ```
   
   Apply the manifest file

   ```shell
   kubectl apply -f cilium-config.yaml
   ```


## K3S Uninstallation

If custom CNI, like Cilium, is used, K3s scripts to clean up an existing installation (`k3s-uninstall.sh` or `k3s-killall.sh`) need to be used carefully.

Those scripts does not clean Cilium networking configuration, and execute them might cause to lose network connectivity to the host when K3s is stopped.

Before running k3s-killall.sh or k3s-uninstall.sh on any node, cilium interfaces must be removed (cilium_host, cilium_net and cilium_vxlan):

```shell
ip link delete cilium_host
ip link delete cilium_net
ip link delete cilium_vxlan
```

Additionally, iptables rules for cilium should be removed:

```shell
iptables-save | grep -iv cilium | iptables-restore
ip6tables-save | grep -iv cilium | ip6tables-restore
```

Also CNI config directory need to be removed

```shell
rm /etc/cni/net.d
```

## References

- [Comparing Networking Solutions for Kubernetes: Cilium vs. Calico vs. Flannel](https://www.civo.com/blog/calico-vs-flannel-vs-cilium)
- [Cilium Installation Using K3s](https://docs.cilium.io/en/stable/installation/k3s/)
- [K3S install custom CNI](https://docs.k3s.io/networking/basic-network-options#custom-cni)

