---
title: Service Mesh (Istio)
permalink: /docs/istio/
description: How to deploy service-mesh architecture based on Istio. Adding observability, traffic management and security to our Kubernetes cluster.
last_modified_at: "10-07-2024"

---

## Istio Ambient Mode




## Istio Installation


### Cilium CNI configuration

The main goal of Cilium configuration is to ensure that traffic redirected to Istio’s sidecar proxies (sidecar mode) or node proxy (ambient mode) is not disrupted. That disruptions can happen when enabling Cilium’s kubeProxyReplacement which uses socket based load balancing inside a Pod. SocketLB need to be disabled for non-root namespaces (helm chart option `socketLB.hostNamespacesOnly=true`).

Kube-proxy-replacement option is mandatory when using L2 announcing feature, which is used in Pi Cluster. 

Also Istio uses a CNI plugin to implement functionality for both sidecar and ambient modes. To ensure that Cilium does not interfere with other CNI plugins on the node, it is important to set the cni-exclusive parameter to false.

The following options need to be added to Cilium helm values.yaml.

```yaml
# Istio configuration
# https://docs.cilium.io/en/latest/network/servicemesh/istio/
# Disable socket lb for non-root ns. This is used to enable Istio routing rules
socketLB:
  hostNamespaceOnly: true
# Istio uses a CNI plugin to implement functionality for both sidecar and ambient modes. 
# To ensure that Cilium does not interfere with other CNI plugins on the node,
cni:
  exclusive: false

```

Due to how Cilium manages node identity and internally allow-lists node-level health probes to pods, applying default-DENY NetworkPolicy in a Cilium CNI install underlying Istio in ambient mode, will cause kubelet health probes (which are by-default exempted from NetworkPolicy enforcement by Cilium) to be blocked.

This can be resolved by applying the following CiliumClusterWideNetworkPolicy:

```yaml
apiVersion: "cilium.io/v2"
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: "allow-ambient-hostprobes"
spec:
  description: "Allows SNAT-ed kubelet health check probes into ambient pods"
  endpointSelector: {}
  ingress:
  - fromCIDR:
    - "169.254.7.127/32"
```
See [istio issue #49277](https://github.com/istio/istio/issues/49277) for more details.


See further details in [Cilium Istio Configuration](https://docs.cilium.io/en/latest/network/servicemesh/istio/) and [Istio Cilium CNI Requirements](https://istio.io/latest/docs/ambient/install/platform-prerequisites/#cilium)


### istioctl installation

Install the istioctl binary with curl:

Download the latest release with the command:

```shell
curl -sL https://istio.io/downloadIstioctl | sh -
```

Add the istioctl client to your path, on a macOS or Linux system:

```shell
export PATH=$HOME/.istioctl/bin:$PATH
```


### Istio control plane installation



Installation using `Helm` (Release 3):

- Step 1: Add the Istio Helm repository:

  ```shell
  helm repo add istio https://istio-release.storage.googleapis.com/charts
  ```
- Step2: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```
- Step 3: Create namespace

  ```shell
  kubectl create namespace istio-system
  ```

- Step 4: Install Istio base components (CRDs, Cluster Policies)

  ```shell
  helm install istio-base istio/base -n istio-system
  ```

- Step 5: Install Istio CNI

  ```shell
  helm install istio-cni istio/cni -n istio-system --set profile=ambient
  ```

- Step 6: Install istio discovery

  ```shell
  helm install istiod istio/istiod -n istio-system --set profile=ambient
  ```

- Step 6: Install Ztunnel

  ```shell
  helm install ztunnel istio/ztunnel -n istio-system --set profile=ambient
  ```


- Step 6: Confirm that the deployment succeeded, run:

  ```shell
  kubectl get pods -n istio-system
  ```

https://istio.io/latest/docs/ambient/install/helm-installation/


### Istio Gateway installation

- Create Istio Gateway namespace

  ```shell
  kubectl create namespace istio-gateway
  ```

- Install helm chart

  ```shell
  helm install istio-ingress istio/gateway -n istio-ingress
  ```

### Testing istio installation

Istio provides a testing application [BookInfo Application](https://istio.io/latest/docs/examples/bookinfo/


See further details about deploying sample application here (https://istio.io/latest/docs/ambient/getting-started/deploy-sample-app/)