---
title: Service Mesh (Istio)
permalink: /docs/istio/
description: How to deploy service-mesh architecture based on Istio. Adding observability, traffic management and security to our Kubernetes cluster.
last_modified_at: "22-07-2024"

---


## Why a Service Mesh

Introduce Service Mesh architecture to add observability, traffic management, and security capabilities to internal communications within the cluster.

I have been testing and using [Linkerd](https://linkerd.io/) as Service Mesh solution for my cluster since relase 1.3 (April 2022). See ["Service Mesh (Linkerd)"](/docs/service-mesh/) document.  

Main reasons for selecting Linkerd over Istio were:
- ARM64 architecture support. Istio did not support ARM architectures at that time.
- Better performance and reduced memory/cpu footprint. Linkerd Proxy vs Istio's Envoy Proxy

Since the initial evaluation was made:

- In Aug 2022, Istio, introduced ARM64 support in release 1.15. See [istio 1.15 announcement](https://istio.io/latest/news/releases/1.15.x/announcing-1.15/)

- In Feb 2024, Linkerd maintaner, Buyoyant, announced that it would no longer provide stable builds. See [Linkerd 2.15 release announcement](https://linkerd.io/2024/02/21/announcing-linkerd-2.15/#a-new-model-for-stable-releases). That decision prompted CNCF to open a health check on the project.

- Istio is developing a sidecarless architecture, [Ambient mode](https://istio.io/latest/docs/ops/ambient/), which is expected to use a reduced footprint. In March 2024, Istio announced the beta relase of Ambient mode for upcoming 1.22 istio release: See [Istio ambient mode beta release announcement](https://www.cncf.io/blog/2024/03/19/istio-announces-the-beta-release-of-ambient-mode/)



## Istio vs Linkerd

- **Open Source Community**

  Istio and Linkerd both are CNCF graduated projects.

  After latest change in Linkerd licensing mode, continuity of Linkerd under CNCF is not clear.

- **ARM support**

  [Istio](https://istio.io) added ARM64 architecture support in release 1.15. See [istio 1.15 announcement](https://istio.io/latest/news/releases/1.15.x/announcing-1.15/).

  [Linkerd](https://linkerd.io/) supports ARM64 architectures since release 2.9. See [linkerd 2.9 announcement](https://linkerd.io/2020/11/09/announcing-linkerd-2.9/).

- **Performance and reduced footprint**

  Linkerd uses its own implementation of the communications proxy, a sidecar container that need to be deployed with any Pod as to inctercep all inbound/outbound traffic. Instead of using a generic purpose proxy ([Envoy proxy](https://www.envoyproxy.io/)) used by traditional Istio's sidecar architecture, a specifc proxy tailored only to cover Kubernetes communications has been developed. Covering just Kubernetes scenario, allows Linkerd proxy to be a simpler, lighter, faster and more secure proxy than Envoy's based proxy

  Istio new sidecarless mode, ambient, uses a new L4 proxy, ztunnel, which is coded in Rust and which is not deployed side-by-side with every single pod, but only deployed one per node.

  This sidecarless new architecture is expected to use a lower footprint than Linkerd

  Preliminary comparison, made by [solo-io](https://www.solo.io/), main contributor to Istio's new Ambient mode, shows reduced Istio footprint and better performance results than Likerd. See comparison analysis ["Istio in Ambient Mode - Doing More for Less!"](https://github.com/solo-io/service-mesh-for-less-blog)




For those reasons, Service Mesh architecture will be migrate to Istio. See [issue #320](https://github.com/ricsanfre/pi-cluster/issues/320)




## Istio Architecture

An Istio service mesh is logically split into a data plane and a control plane.


- The **data plane** is the set of proxies that mediate and control all network communication between microservices. They also collect and report telemetry on all mesh traffic.
- The **control plane** manages and configures the proxies in the data plane.

Istio supports two main data plane modes:
- **sidecar mode**, which deploys an Envoy proxy along with each pod that you start in your cluster, or running alongside services running on VMs.
  sidecar mode is similar to the one providers by other Service Mesh solutions like linkerd.

- **ambient mode**, sidecaless mode, which uses a per-node Layer 4 proxy, and optionally a per-namespace Envoy proxy for Layer 7 features.

![istio-sidecar-vs-ambient](/assets/img/istio_sidecar_vs_ambient.jpg)

{{site.data.alerts.note}}
Even whe Istio Ambien mode is in beta state, since it is expected to provide a reduced footprint than the sidecar architecture, I will use ambient mode for the PiCluster

See [Istio ambient mode beta release announcement](https://www.cncf.io/blog/2024/03/19/istio-announces-the-beta-release-of-ambient-mode/)

{{site.data.alerts.end}}


## Istio Ambient Mode

In ambient mode, Istio implements its features using a per-node Layer 4 (L4) proxy, ztunnel, and optionally a per-namespace Layer 7 (L7) proxy, waypoint proxy.

- `ztunnel` proxy, providing basic L4 secured connectivity and authenticating workloads within the mesh (i.e.:mTLS).
  - L4 routing
  - Encryption and authentication via mTLS
  - L4 telemetry (metrics, logs)

- `waypoint` proxy, providing L7 functionality, is a deployment of the [Envoy proxy](https://www.envoyproxy.io/); the same engine that Istio uses for its sidecar data plane mode.
  - L7 routing
  - L7 telemetry (metrics, logs traces)

See further details in [Istio Ambient Documentation](https://istio.io/latest/docs/ambient/)


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
  helm install ztunnel istio/ztunnel -n istio-system
  ```


- Step 6: Confirm that the deployment succeeded, run:

  ```shell
  kubectl get pods -n istio-system
  ```

https://istio.io/latest/docs/ambient/install/helm-installation/


### Istio Gateway installation

- Create Istio Gateway namespace

  ```shell
  kubectl create namespace istio-ingress
  ```

- Install helm chart

  ```shell
  helm install istio-gateway istio/gateway -n istio-ingress
  ```

### Istio Observability configuration

Istio generates detailed telemetry (metricis, traces and logs) for all service communications within a mesh

See further details in [Istio Observability](https://istio.io/latest/docs/concepts/observability/)

#### Logs

Istio support sending [Envoy's access logs](https://www.envoyproxy.io/docs/envoy/latest/configuration/observability/access_log/usage) using OpenTelemetry and a way to configure it using [Istio's Telemetry API](https://istio.io/latest/docs/tasks/observability/telemetry/). So that Telemetry API can be used to configure Ambient's waypoint proxies (Envoy based proxies)

ztunnel proxies also generate by default operational and access logs.

See further details in [Istio Observability Logs](https://istio.io/latest/docs/tasks/observability/logs/)


#### Traces

Istio leverages Envoy's proxy distributed tracing capabilities. Since Istio Ambient mode is only using Envoy proxy for waypoint proxy.

By default in Ambient mode, using Istio's [book-info](https://istio.io/latest/docs/examples/bookinfo/) testing application, traces are only generated from istio-gateway. No Spans are generated by different microservices since there is no any Envoy Proxy exporting traces.


To enable Open Telemetry traces to be generated by Istio ingress gateway and other proxies:

- Step 1 - Enable Open Telemetry tracing provider in Istio'd control plane within [Mesh global configuration options](https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/)

  Add following configuration to istiod helm chart `values.yaml`

  ```yaml
  meshConfig:  
    # Enabling distributed traces
    enableTracing: true
    extensionProviders:
    - name: opentelemetry
      opentelemetry:
        port: 4317
        service: tempo-distributor.tempo.svc.cluster.local
        resource_detectors:
          environment: {}
  ```

  That configuration enables globallly OpenTelemetry provider using Grafana's Tempo Open Telemetry collector.

- Step 2 - Use Istio's Telemetry API to apply the default distributed tracing configuration to the cluster

  ```yaml
  apiVersion: telemetry.istio.io/v1alpha1
  kind: Telemetry
  metadata:
    name: otel-global
    namespace: istio-system
  spec:
    tracing:
    - providers:
      - name: opentelemetry
      randomSamplingPercentage: 100
      customTags:
        "my-attribute":
          literal:
            value: "default-value"  
  ```
  
  A specific configuration, per namespace or workload can be also configured. 

  See details in [Istio's Telemetry API doc](https://istio.io/latest/docs/tasks/observability/telemetry/)


See furhter details in [Istio Distributed Tracing](https://istio.io/latest/docs/tasks/observability/distributed-tracing/)


#### Metrics (Prometheus configuration)

Metrics from control plane (istiod) and proxies (ztunnel) can be extracted from Prometheus sever:


- Create following manifest file to create Prometheus Operator monitoring resources

  ```yaml
  apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    name: istio-component-monitor
    namespace: istio-system
    labels:
      monitoring: istio-components
      release: istio
  spec:
    jobLabel: istio
    targetLabels: [app]
    selector:
      matchExpressions:
      - {key: istio, operator: In, values: [pilot]}
    namespaceSelector:
      matchNames:
        - istio-system
    endpoints:
    - port: http-monitoring
      interval: 60s

  ```
  
  ```yaml
  apiVersion: monitoring.coreos.com/v1
  kind: PodMonitor
  metadata:
    name: ztunnel-monitor
    namespace: istio-system
    labels:
      monitoring: ztunnel-proxies
      release: istio
  spec:
    selector:
      matchLabels:
        app: ztunnel
    namespaceSelector:
      matchNames:
        - istio-system
    jobLabel: ztunnel-proxy
    podMetricsEndpoints:
    - path: /stats/prometheus
      interval: 60s
  ```


## Kiali installation

[Kiali](https://kiali.io/) is an observability console for Istio with service mesh configuration and validation capabilities. It helps you understand the structure and health of your service mesh by monitoring traffic flow to infer the topology and report errors. Kiali provides detailed metrics and a basic Grafana integration, which can be used for advanced queries. Distributed tracing is provided by integration with Jaeger.

See details about installing Kiali using Helm in [Kiali's Quick Start Installation Guide](https://kiali.io/docs/installation/quick-start/)

Kiali will be installing using Kiali operator which is recommeded

Installation using `Helm` (Release 3):

- Step 1: Add the Kiali Helm repository:

  ```shell
  helm repo add kiali https://istio-release.storage.googleapis.com/charts
  ```
- Step 2: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```

- Step 3: Create `kiali-operator-values.yaml`

  ```yaml
  cr:
    create: true
    namespace: istio-system
    spec:
        auth:
          strategy: "anonymous"
        external_services:
          prometheus:
            # Prometheus service
            url: "http://kube-prometheus-stack-prometheus.monitoring:9090/"
          grafana:
            enabled: true
            # Grafana service name is "grafana" and is in the "monitoring" namespace.
            in_cluster_url: 'http://grafana.monitoring.svc.cluster.local/grafana/'
            # Public facing URL of Grafana
            url: 'https://monitoring.picluster.ricsanfre.com/grafana/'
            auth:
              # Use same OAuth2.0 token used for accesing Kiali
              type: bearer
              use_kiali_token: true
          tracing:
            # Enabled by default. Kiali will anyway fallback to disabled if
            # Tempo is unreachable.
            enabled: true
            # Tempo service name is "query-frontend" and is in the "tempo" namespace.
            in_cluster_url: "http://tempo-query-frontend.tempo.svc.cluster.local:3100/"
            provider: "tempo"
            tempo_config:
              org_id: "1"
              datasource_uid: "a8d2ef1c-d31c-4de5-a90b-e7bc5252cd00"
            # Use grpc to speed up the download of metrics
            use_grpc: true
            grpc_port: 9095
        deployment:
          ingress:
            class_name: "nginx"
            enabled: true
            override_yaml:
              metadata:
                annotations:
                  # Enable cert-manager to create automatically the SSL certificate and store in Secret
                  # Possible Cluster-Issuer values:
                  #   * 'letsencrypt-issuer' (valid TLS certificate using IONOS API)
                  #   * 'ca-issuer' (CA-signed certificate, not valid)
                  cert-manager.io/cluster-issuer: letsencrypt-issuer
                  cert-manager.io/common-name: kiali.picluster.ricsanfre.com
              spec:
                rules:
                - host: kiali.picluster.ricsanfre.com
                  http:
                    paths:
                    - backend:
                        service:
                          name: kiali
                          port:
                            number: 20001
                      path: /
                      pathType: Prefix
                tls:
                - hosts:
                  - kiali.picluster.ricsanfre.com
                  secretName: kiali-tls
  ```

  With this configuration Kiali Server, Kiali Custom Resource, is created with the following config:

  - No authentincation strategy (`cr.spec.auth.strategy: "anonymous"`).

    See further details in [Kiali OpenID Connect Strategy](https://kiali.io/docs/configuration/authentication/openid/)

  - Ingress resource is created (`cr.spec.deployment.ingress`)

    See further details in [Kiali Ingress Documentation](https://kiali.io/docs/installation/installation-guide/accessing-kiali/)

  - External connection to Prometheus, Grafana and Tempo is configured (`cr.spec.external_services`)

    See further details in [Kiali Configuring Prometheus Tracing Grafana](https://kiali.io/docs/configuration/p8s-jaeger-grafana/)

- Step 4: Install Kiali Operator in istio-system namespace

  ```shell
  helm install kiali-operator kiali/kiali-operator --namespace istio-system -f kiali-operator-values.yaml
  ```


### Kiali OpenID Authentication configuration

Kiali can be configured to use as authentication mechanism Open Id Connect server.

Kiali only supports the authorization code flow of the OpenId Connect spec.

See further details in [Kiali OpenID Connect Strategy](https://kiali.io/docs/configuration/authentication/openid/).


- Step 1: Create a new OIDC client in 'picluster' Keycloak realm by navigating to:
  Clients -> Create client

  ![kiali-keycloak-1](/assets/img/kiali-keycloak-1.png)

  - Provide the following basic configuration:
    - Client Type: 'OpenID Connect'
    - Client ID: 'kiali'
  - Click Next.

  ![kiali-keycloak-2](/assets/img/kiali-keycloak-2.png)

  - Provide the following 'Capability config'
    - Client authentication: 'On'
    - Client authorization: 'On'
    - Authentication flow
      - Standard flow 'selected'
      - Implicit flow 'selected'
      - Direct access grants 'selected'
  - Click Next

  ![kiali-keycloak-3](/assets/img/kiali-keycloak-3.png)

  - Provide the following 'Logging settings'
    - Valid redirect URIs: https://kiali.picluster.ricsanfre.com/kiali/*
    - Root URL: https://kiali.picluster.ricsanfre.com/kiali/
  - Save the configuration.

- Step 2: Locate kiali client credentials

  Under the Credentials tab you will now be able to locate kiali client's secret.

  ![kiali-keycloak-4](/assets/img/kiali-keycloak-4.png)

- Step 3: Create secret for kiali storing client secret

  ```shell
  export CLIENT_SECRET=<kiali secret>

  kubectl create secret generic kiali --from-literal="oidc-secret=$CLIENT_SECRET" -n istio-system
  ```
- Step 4: Configure's kiali openId Connect authentication

  Add following to Kiali's helm chart operator values.yaml.

  ```yaml
  cr:
    spec:
      auth:
        # strategy: "anonymous"
        strategy: openid
        openid:
          client_id: "kiali"
          disable_rbac: true
          issuer_uri: "https://sso.picluster.ricsanfre.com/realms/picluster"
  ```

## Testing Istio installation

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

## Pending

- Kiali cannot connect to Grafana (authentication issue)

https://www.lisenet.com/2023/kiali-does-not-see-istio-ingressgateway-installed-in-separate-kubernetes-namespace/



## References

- Install istio using Helm chart: https://istio.io/latest/docs/setup/install/helm/ 
- Istio getting started: https://istio.io/latest/docs/setup/getting-started/
- Kiali: https://kiali.io/
- NGINX Ingress vs Istio gateway: https://imesh.ai/blog/kubernetes-nginx-ingress-vs-istio-ingress-gateway/
