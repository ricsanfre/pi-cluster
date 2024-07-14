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

## Kiali installation

[Kiali](https://kiali.io/) is an observability console for Istio with service mesh configuration and validation capabilities. It helps you understand the structure and health of your service mesh by monitoring traffic flow to infer the topology and report errors. Kiali provides detailed metrics and a basic Grafana integration, which can be used for advanced queries. Distributed tracing is provided by integration with Jaeger.

See details about installing Kiali using Helm in [Kiali's Quick Start Installation Guide](https://kiali.io/docs/installation/quick-start/)


Installation using `Helm` (Release 3):

- Step 1: Add the Kiali Helm repository:

  ```shell
  helm repo add kiali https://istio-release.storage.googleapis.com/charts
  ```
- Step 2: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```

- Step 3: Create `kiali-values.yaml`

  ```yaml
  auth:
    strategy: "anonymous"
  external_services:
    istio:
      root_namespace: istio-system
      component_status:
        enabled: true
        components:
        - app_label: istiod
          is_core: true
        - app_label: istio-ingress
          is_core: true
          is_proxy: true
          namespace: istio-ingress  
  ```

- Step 4: Install Kiali in istio-system namespace

  ```shell
  helm install kiali-server kiali/kiali-server --namespace istio-system -f kiali-values.yaml
  ```



https://www.lisenet.com/2023/kiali-does-not-see-istio-ingressgateway-installed-in-separate-kubernetes-namespace/



## Testing istio installation

[Book info sample application](https://istio.io/latest/docs/examples/bookinfo/) can be deployed to test installation

- Create Kustomized bookInfo app

  - Create app directory

    ```shell
    mkdir book-info-app
    ```

  - Create book-info-app/kustomized.yaml file

    ```yaml
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    namespace: book-info
    resources:
    - ns.yaml
      # https://istio.io/latest/docs/examples/bookinfo/
    - https://raw.githubusercontent.com/istio/istio/release-1.22/samples/bookinfo/platform/kube/bookinfo.yaml
    - https://raw.githubusercontent.com/istio/istio/release-1.22/samples/bookinfo/platform/kube/bookinfo-versions.yaml
    - https://raw.githubusercontent.com/istio/istio/release-1.22/samples/bookinfo/gateway-api/bookinfo-gateway.yaml
    ```

  - Create book-info-app/ns.yaml file

    ```yaml
    apiVersion: v1
    kind: Namespace
    metadata:
      name: book-info
    ```


- Deploy book info app

  ```shell
  kubectl kustomize book-info-app | kubectl apply -f -  
  ```

- Label namespace to enable automatic sidecar injection

  See [Ambient Mode - Add workloads to the mesh"](https://istio.io/latest/docs/ambient/usage/add-workloads/)
  
  ```shell
  kubectl label namespace book-info istio.io/dataplane-mode=ambient
  ```

  Ambient mode can be seamlessly enabled (or disabled) completely transparently as far as the application pods are concerned. Unlike the sidecar data plane mode, there is no need to restart applications to add them to the mesh, and they will not show as having an extra container deployed in their pod.


 - Validate configuration

   ```shell
   istioctl validate
   ```

## Monitoring

https://istio.io/latest/docs/concepts/observability/

https://github.com/istio/istio/tree/master/samples/addons


## References

- Install istio using Helm chart: https://istio.io/latest/docs/setup/install/helm/ 
- Istio getting started: https://istio.io/latest/docs/setup/getting-started/
- Kiali: https://kiali.io/

- NGINX Ingress vs Istio gateway: https://imesh.ai/blog/kubernetes-nginx-ingress-vs-istio-ingress-gateway/
