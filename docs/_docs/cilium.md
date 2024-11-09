---
title: Cilium (Kubernetes CNI)
permalink: /docs/cilium/
description: How to install Cilium CNI in the picluster.
last_modified_at: "09-09-2024"
---

[Cilium](https://cilium.io/) is an open source, cloud native solution for providing, securing, and observing network connectivity between workloads, powered by [eBPF](https://ebpf.io/) Kernel technology.

In a Kubernetes cluster, Cilium can be used as,

- High performance CNI
  
  See details in [Cilium Use-case: Layer 4 Load Balancer](https://cilium.io/use-cases/load-balancer/)


- Kube-proxy replacement
  
  Kube-proxy is a component running in the nodes of the cluster which provides load-balancing traffic targeted to kubernetes services (via Cluster IPs and Node Ports), routing the traffic to the proper backend pods.
  
  Cilium can be used to replace kube-proxy component, replacing kube-proxy's iptables based routing by [eBFP](https://ebpf.io/) technology.

  See details in [Cilium Use-case: Kube-proxy Replacement](https://cilium.io/use-cases/kube-proxy/)

- Layer 4 Load Balancer
 
  Software based load-balancer for the kubernetes cluster which is able to announce the routes to kubernetes services using BGP or L2 protocols

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


K3S master nodes need to be installed with the following additional options:

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
- Step 2: Fetch the latest charts from the repository:

    ```shell
    helm repo update
    ```

- Step 3: Create helm values file `cilium-values.yml`

  ```yml
  # Cilium operator config
  operator:
    # replicas: 1  # Uncomment this if you only have one node
    # Roll out cilium-operator pods automatically when configmap is updated.
    rollOutPods: true

    # Install operator on master node
    nodeSelector:
      node-role.kubernetes.io/master: "true"

  # Roll out cilium agent pods automatically when ConfigMap is updated.
  rollOutCiliumPods: true

  # K8s API service
  k8sServiceHost: 127.0.0.1
  k8sServicePort: 6444

  # Replace Kube-proxy
  kubeProxyReplacement: true
  kubeProxyReplacementHealthzBindAddr: 0.0.0.0:10256

  # -- Configure IP Address Management mode.
  # ref: https://docs.cilium.io/en/stable/network/concepts/ipam/
  ipam:
    operator:
      clusterPoolIPv4PodCIDRList: "10.42.0.0/16"

  # Configure L2 announcements (LB-IPAM configuration)
  l2announcements:
    enabled: true
  externalIPs:
    enabled: true

  # Increase the k8s api client rate limit to avoid being limited due to increased API usage 
  k8sClientRateLimit:
    qps: 50
    burst: 200
  ```

- Step 4: Install Cilium in kube-system namespace

    ```shell
    helm install cilium cilium/cilium --namespace kube-system -f cilium-values.yaml
    ```

- Step 5: Confirm that the deployment succeeded, run:

    ```shell
    kubectl -n kube-system get pod
    ```

### Helm chart configuration details


- Configure Cilium Operator, to run on master nodes and roll out automatically when configuration is updated

  ```yaml
  operator:
    # Roll out cilium-operator pods automatically when configmap is updated.
    rollOutPods: true

    # Install operator on master node
    nodeSelector:
      node-role.kubernetes.io/master: "true"
  ```

- Configure Cilium agents to roll out automatically when configuration is updated

  ```yaml
  # Roll out cilium agent pods automatically when ConfigMap is updated.
  rollOutCiliumPods: true
  ```

- Configure Cilium to replace kube-proxy

  ```yaml
  # Replace Kube-proxy
  kubeProxyReplacement: true
  kubeProxyReplacementHealthzBindAddr: 0.0.0.0:10256
  ```

  Further details about kube-proxy replacement mode in [Cilium doc](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)

- Cilium LB-IPAM configuration
  
  ```yaml
  l2announcements:
    enabled: true
  externalIPs:
    enabled: true
  ```

  Cilium to perform L2 announcements and reply to ARP requests (`l2announcements.enabled`). This configuration requires Cilium to run in kube-proxy replacement mode.

  Also announce external IPs assigned to LoadBalancer type Services need to be enabled (`externalIPs.enabled`, i.e the IPs assigned by LB-IPAM.

- Configure access to Kubernetes API

  ```yaml
  k8sServiceHost: 127.0.0.1
  k8sServicePort: 6444
  ```
  This variables should point to Kuberentes API listening in a Virtual IP configured in `haproxy` (10.0.0.11) and port 6443.
  K3s has an API server proxy listening in 127.0.0.1:6444 on all nodes in the cluster, so it is not needed to point to external virtual IP address.


- Increase the k8s api client rate limit to avoid being limited due to increased API usage
  
  ```yaml 
  k8sClientRateLimit:
    qps: 50
    burst: 200
  ```
  The leader election process, used by L2 annoucements, continually generates API traffic, so API request. The default client rate limit is 5 QPS (query per second) with allowed bursts up to 10 QPS. this default limit is quickly reached when utilizing L2 announcements and thus users should size the client rate limit accordingly.

  See details in [Cilium L2 announcements documentation](https://docs.cilium.io/en/latest/network/l2-announcements/#sizing-client-rate-limit)

### Configure Cilium monitoring and Hubble UI

{{site.data.alerts.note}}
Prometheus Operator CDRs need to be installed before Cilium, so ServiceMonitor resources can be created.
CDRs are automatically deployed when installing kube-prometheus-stack helm chart.

As part of a cluster fresh installation, Only Prometheus Operator CDRs can be installed:

```shell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus-operator-crds prometheus-community/prometheus-operator-crds
```

Then Cilium CNI can be installed, to have fully functional cluster.

Finally, when installing kube-prometheus-stack helm chart, installation of the CDRs can be skipped when executing helm install command (`helm install --skip-crds`).

{{site.data.alerts.end}}

- Configure Prometheus Monitoring metrics and Grafana dashboards

  Add following configuration to helm chart `values.yaml`:

  ```yaml
  operator:
    # Enable prometheus integration for cilium-operator
    prometheus:
      enabled: true
      serviceMonitor:
        enabled: true
    # Enable Grafana dashboards for cilium-operator
    dashboards:
      enabled: true
      annotations:
        grafana_folder: Cilium

  # Enable Prometheus integration for cilium-agent
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true
      # scrape interval
      interval: "10s"
      # -- Relabeling configs for the ServiceMonitor hubble
      relabelings:
        - action: replace
          sourceLabels:
            - __meta_kubernetes_pod_node_name
          targetLabel: node
          replacement: ${1}
      trustCRDsExist: true
  # Enable Grafana dashboards for cilium-agent
  # grafana can import dashboards based on the label and value
  # ref: https://github.com/grafana/helm-charts/tree/main/charts/grafana#sidecar-for-dashboards
  dashboards:
    enabled: true
    annotations:
      grafana_folder: Cilium

  ```

- Enable Huble UI

  Add following configuration to helm chart `values.yaml`:

  ```yaml
  # Enable Hubble
  hubble:
    enabled: true
    # Enable Monitoring
    metrics:
      enabled:
        - dns:query
        - drop
        - tcp
        - flow
        - port-distribution
        - icmp
        - http
      serviceMonitor:
        enabled: true
        # scrape interval
        interval: "10s"
        # -- Relabeling configs for the ServiceMonitor hubble
        relabelings:
          - action: replace
            sourceLabels:
              - __meta_kubernetes_pod_node_name
            targetLabel: node
            replacement: ${1}
      # Grafana Dashboards
      dashboards:
        enabled: true
        annotations:
          grafana_folder: Cilium
    relay:
      enabled: true
      rollOutPods: true
      # Enable Prometheus for hubble-relay
      prometheus:
        enabled: true
        serviceMonitor:
          enabled: true
    ui:
      enabled: true
      rollOutPods: true
      # Enable Ingress
      ingress:
        enabled: true
        annotations:
          # Enable external authentication using Oauth2-proxy
          nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.picluster.ricsanfre.com/oauth2/start?rd=https://$host$request_uri
          nginx.ingress.kubernetes.io/auth-url: http://oauth2-proxy.oauth2-proxy.svc.cluster.local/oauth2/auth
          nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
          nginx.ingress.kubernetes.io/auth-response-headers: Authorization

          # Enable cert-manager to create automatically the SSL certificate and store in Secret
          # Possible Cluster-Issuer values:
          #   * 'letsencrypt-issuer' (valid TLS certificate using IONOS API)
          #   * 'ca-issuer' (CA-signed certificate, not valid)
          cert-manager.io/cluster-issuer: letsencrypt-issuer
          cert-manager.io/common-name: hubble.picluster.ricsanfre.com
        className: nginx
        hosts: ["hubble.picluster.ricsanfre.com"]
        tls:
          - hosts:
            - hubble.picluster.ricsanfre.com
            secretName: hubble-tls
  ```

See further details in [Cilium Monitoring and Metrics](https://docs.cilium.io/en/stable/observability/metrics/) and [Cilium Hubble UI](https://docs.cilium.io/en/stable/gettingstarted/hubble/) and [Cilium Hubble Configuration](https://docs.cilium.io/en/latest/gettingstarted/hubble-configuration/).

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

#### Configuring LoadBalancer Services

{{site.data.alerts.note}}
Service's `.spec.loadBalancerIP` was the method used to specify the external IP, from load balancer Ip Pool, to be assigned to the service. It has been deprecated since [Kubernetes v1.24](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.24.md) and might be removed in a future release. It is recommended to use implementation-specific annotations when available
{{site.data.alerts.end}}


Services can request specific IPs. The legacy way of doing so is via `.spec.loadBalancerIP` which takes a single IP address. This method has been deprecated in k8s v1.24.

With Cilium LB IPAM, the way of requesting specific IPs is to use annotation, `io.cilium/lb-ipam-ips`. This annotation takes a comma-separated list of IP addresses, allowing for multiple IPs to be requested at once.


```yaml
apiVersion: v1
kind: Service
metadata:
  name: service-blue
  namespace: example
  labels:
    color: blue
  annotations:
    io.cilium/lb-ipam-ips: "20.0.10.100,20.0.10.200"
spec:
  type: LoadBalancer
  ports:
  - port: 1234
```

See further details in [Cilium LB IPAM documentation](https://docs.cilium.io/en/stable/network/lb-ipam/).


## Cilium and ArgoCD

ArgoCD automatic synchornization and pruning of resources might might delete some of the Resources automatically created by Cilium. This is a well-known behaviour of ArgoCD. Check ["Argocd installation"](/docs/argocd/) document.


ArgoCD need to be configured to exclude the synchronization of  CiliumIdentity resources:

```yaml
resource.exclusions: |
 - apiGroups:
     - cilium.io
   kinds:
     - CiliumIdentity
   clusters:
     - "*"
```

Also other issues related to Hubble's rotation of certificates need to be considere and add the following configuration to Cilium's ArgoCd Application resource

```yaml
ignoreDifferences:
  - group: ""
    kind: ConfigMap
    name: hubble-ca-cert
    jsonPointers:
    - /data/ca.crt
  - group: ""
    kind: Secret
    name: hubble-relay-client-certs
    jsonPointers:
    - /data/ca.crt
    - /data/tls.crt
    - /data/tls.key
  - group: ""
    kind: Secret
    name: hubble-server-certs
    jsonPointers:
    - /data/ca.crt
    - /data/tls.crt
    - /data/tls.key
```


See further details in Cilium documentation: [Troubleshooting Cilium deployed with Argo CD](https://docs.cilium.io/en/latest/configuration/argocd-issues/).



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
