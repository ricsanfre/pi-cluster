---
title: Service Mesh (Istio)
permalink: /docs/istio/
description: How to deploy service-mesh architecture based on Istio. Adding observability, traffic management and security to our Kubernetes cluster.
last_modified_at: "07-03-2025"

---


## Why a Service Mesh

Introduce Service Mesh architecture to add observability, traffic management, and security capabilities to internal communications within the cluster.


{{site.data.alerts.important}}

I have been testing and using [Linkerd](https://linkerd.io/) as Service Mesh solution for my cluster since release 1.3 (April 2022). See ["Service Mesh (Linkerd)"](/docs/service-mesh/) document.

Main reasons for selecting Linkerd over Istio were:
- ARM64 architecture support. Istio did not support ARM architectures at that time.
- Better performance and reduced memory/cpu footprint. Linkerd Proxy vs Istio's Envoy Proxy

Since the initial evaluation was made:

- In Aug 2022, Istio, introduced ARM64 support in release 1.15. See [istio 1.15 announcement](https://istio.io/latest/news/releases/1.15.x/announcing-1.15/)

- In Feb 2024, Linkerd maintaner, Buyoyant, announced that it would no longer provide stable builds. See [Linkerd 2.15 release announcement](https://linkerd.io/2024/02/21/announcing-linkerd-2.15/#a-new-model-for-stable-releases). That decision prompted CNCF to open a health check on the project.

- Istio is developing a sidecarless architecture, [Ambient mode](https://istio.io/latest/docs/ops/ambient/), which is expected to use a reduced footprint. In March 2024, Istio announced the beta relase of Ambient mode for upcoming 1.22 istio release: See [Istio ambient mode beta release announcement](https://www.cncf.io/blog/2024/03/19/istio-announces-the-beta-release-of-ambient-mode/)

For those reasons, Service Mesh solution in the cluster has been migrated to Istio since release 1.9.

{{site.data.alerts.end}} 

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

  This sidecarless new architecture is expected to use a lower footprint than Linkerd.

  Preliminary comparison, made by [solo-io](https://www.solo.io/), main contributor to Istio's new Ambient mode, shows reduced Istio footprint and better performance results than Istio sidecar mode. See comparison analysis ["Istio in Ambient Mode - Doing More for Less!"](https://www.solo.io/blog/istio-more-for-less)


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


## Istio Sidecar Mode

![istio-sidecar-architecture](/assets/img/istio-architecture-sidecar.png)

In sidecar mode, Istio implements its features using a per-pod L7 proxy,[Envoy proxy](https://www.envoyproxy.io/). This is a transparent proxy running as sidecar container within the pods. Proxies automatically intercept Pod's inbound/outbound TCP traffic and add transparantly encryption (mTLS), Later-7 load balancing, routing, retries, telemetry, etc.


## Istio Ambient Mode


![istio-sidecar-architecture](/assets/img/istio-architecture-ambient-L4.png)

In ambient mode, Istio deploys a shared agent, running on each node in the Kubernetes cluster. This agent is a zero-trust tunnel (or `ztunnel`), and its primary responsibility is to securely connect and authenticate elements within the mesh. The networking stack on the node redirects all traffic of participating workloads through the local ztunnel agent.

Ztunnels enable the core functionality of a service mesh: zero trust. A secure overlay is created when ambient is enabled for a namespace. It provides workloads with mTLS, telemetry, authentication, and L4 authorization, without terminating or parsing HTTP.

After ambient mesh is enabled and a secure overlay is created, a namespace can be configured to utilize L7 features. 

Namespaces operating in this mode use one or more Envoy-based waypoint proxies to handle L7 processing for workloads in that namespace. Istio’s control plane configures the ztunnels in the cluster to pass all traffic that requires L7 processing through the waypoint proxy. Importantly, from a Kubernetes perspective, waypoint proxies are just regular pods that can be auto-scaled like any other Kubernetes deployment.

![istio-sidecar-architecture](/assets/img/istio-architecture-ambient-L7.png)


In ambient mode, Istio implements its features using two different proxies, a per-node Layer 4 (L4) proxy, ztunnel, and optionally a per-namespace Layer 7 (L7) proxy, waypoint proxy.


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

{{site.data.alerts.important}}
This policy override is _not_ required unless you already have other default-deny `NetworkPolicies` or `CiliumNetworkPolicies` applied in the cluster
{{site.data.alerts.end}}

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

Istio generates detailed telemetry (metrics, traces and logs) for all service communications within a mesh

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

[Kiali](https://kiali.io/) is an observability console for Istio with service mesh configuration and validation capabilities. It helps you understand the structure and health of your service mesh by monitoring traffic flow to infer the topology and report errors. Kiali provides detailed metrics and a basic Grafana integration, which can be used for advanced queries. Distributed tracing is provided in this cluster by integration with Tempo.

See details about installing Kiali using Helm in [Kiali's Quick Start Installation Guide](https://kiali.io/docs/installation/quick-start/)

Kiali is installed using the Kiali Operator.

Installation using `Helm` (Release 3):

- Step 1: Create Kiali namespace

  ```shell
  kubectl create namespace kiali
  ```

- Step 2: Add the Kiali Helm repository:

  ```shell
  helm repo add kiali https://istio-release.storage.googleapis.com/charts
  ```
- Step 3: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```

- Step 4: Create `kiali-operator-values.yaml`

  ```yaml
  cr:
    create: true
    namespace: kiali
    spec:
      istio_namespace: "istio-system"
      server:
        web_fqdn: "kiali.${CLUSTER_DOMAIN}"
        web_port: "443"
        web_schema: "https"
        web_root: "/"
      auth:
        strategy: "anonymous"
      external_services:
        prometheus:
          url: "http://kube-prometheus-stack-prometheus.kube-prom-stack:9090/prometheus/"
        grafana:
          enabled: true
          internal_url: "http://grafana.grafana.svc.cluster.local/grafana/"
          external_url: "https://grafana.${CLUSTER_DOMAIN}"
          auth:
            type: bearer
            use_kiali_token: true
        tracing:
          enabled: true
          internal_url: "http://tempo-query-frontend.tempo.svc.cluster.local:3100/"
          provider: "tempo"
          tempo_config:
            org_id: "1"
            datasource_uid: "a8d2ef1c-d31c-4de5-a90b-e7bc5252cd00"
          use_grpc: true
          grpc_port: 9095
      deployment:
        logger:
          log_level: debug
  ```

- Step 5: Install Kiali Operator in kiali namespace

  ```shell
  helm install kiali-operator kiali/kiali-operator --namespace kiali -f kiali-operator-values.yaml
  ```

- Step 6: Check Kiali is up and running

  ```shell
  kubectl get pods -n kiali
  kubectl get service kiali -n kiali
  ```

- Step 7: Expose Kiali through Envoy Gateway with an `HTTPRoute`

  ```yaml
  apiVersion: gateway.networking.k8s.io/v1
  kind: HTTPRoute
  metadata:
    name: kiali-console
    namespace: kiali
  spec:
    hostnames:
      - kiali.${CLUSTER_DOMAIN}
    parentRefs:
      - group: gateway.networking.k8s.io
        kind: Gateway
        name: public-gateway
        namespace: envoy-gateway-system
    rules:
      - backendRefs:
          - name: kiali
            port: 20001
        matches:
          - path:
              type: PathPrefix
              value: /
  ```

  {{site.data.alerts.note}}

  Substitute variables (`${var}`) in the above yaml file before applying it.
  -   Replace `${CLUSTER_DOMAIN}` by the domain used in the cluster. For example: `homelab.ricsanfre.com`

  To expose Kiali using the `HTTPRoute`, Envoy Gateway and the shared `public-gateway` `Gateway` must already be installed in the cluster. See installation details in [Envoy Gateway documentation](/docs/envoy-gateway/).

  {{site.data.alerts.end}}

  With this configuration the Kiali Server custom resource is created with the following config:

  - Server public URL settings are configured through `cr.spec.server`.

    `web_fqdn`, `web_port`, `web_schema`, and `web_root` tell Kiali the external URL where it is published so redirects and generated links use `https://kiali.${CLUSTER_DOMAIN}/`.

  - No authentincation strategy (`cr.spec.auth.strategy: "anonymous"`).

  - Kiali is exposed through Envoy Gateway using an external `HTTPRoute` resource instead of the Kiali ingress settings.

    See further details in [Kubernetes Gateway API HTTPRoute](https://gateway-api.sigs.k8s.io/api-types/httproute/)

  - External connection to Prometheus, Grafana and Tempo is configured (`cr.spec.external_services`)

    See further details in [Kiali Configuring Prometheus Tracing Grafana](https://kiali.io/docs/configuration/p8s-jaeger-grafana/)

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
    - Valid redirect URIs: `https://kiali.${CLUSTER_DOMAIN}/*`
    - Root URL: `https://kiali.${CLUSTER_DOMAIN}/`
  - Save the configuration.

- Step 2: Locate kiali client credentials

  Under the Credentials tab you will now be able to locate Kiali client's secret.

  ![kiali-keycloak-4](/assets/img/kiali-keycloak-4.png)

- Step 3: Store Kiali client secret so it can be synchronized by External Secrets

  In this repository the Kiali secret is not created manually. Instead, an `ExternalSecret` named `kiali-externalsecret` reads the client secret from Vault key `kiali/oauth2` and materializes Kubernetes Secret `kiali` with key `oidc-secret`.

  The equivalent manifest used in this repository is:

  ```yaml
  apiVersion: external-secrets.io/v1
  kind: ExternalSecret
  metadata:
    name: kiali-externalsecret
    namespace: kiali
  spec:
    secretStoreRef:
      name: vault-backend
      kind: ClusterSecretStore
    target:
      name: kiali
    data:
      - secretKey: oidc-secret
        remoteRef:
          key: kiali/oauth2
          property: client-secret
  ```

- Step 4: Configure Kiali OpenID Connect authentication

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
          issuer_uri: "https://iam.${CLUSTER_DOMAIN}/realms/picluster"
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
    - https://raw.githubusercontent.com/istio/istio/release-1.29/samples/bookinfo/platform/kube/bookinfo.yaml
    - https://raw.githubusercontent.com/istio/istio/release-1.29/samples/bookinfo/platform/kube/bookinfo-versions.yaml
    - https://raw.githubusercontent.com/istio/istio/release-1.29/samples/bookinfo/gateway-api/bookinfo-gateway.yam
    ```

    {{site.data.alerts.note}}
    Book-app release version has to be aligned with Istio release.
    {{site.data.alerts.end}}

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

## Sample Namespace Mesh Configuration

In my cluster I deploy a sample e-commerce application, which is composed of several microservices deployed in different namespaces. See details of the e-commerce application in [https://github.com/ricsanfre/spring-microservices-otel-k8s](https://github.com/ricsanfre/spring-microservices-otel-k8s). The purpose of this application is to test a distributed microservices-based architecture and test Istio mesh configuration and observability capabilities.

Each namespace in the ambient mesh requires specific configuration depending on
its workload characteristics. The Pi Cluster currently has five namespaces
participating in the mesh: `envoy-gateway-system`, `keycloak`, `databases`,
`e-commerce`, and `kafka`.

### Topology

The following diagram shows how ztunnel proxies mediate traffic between namespaces, which mTLS mode each uses, and where exceptions are needed for non-mesh clients:

<pre class="mermaid">
graph TB
    subgraph External["Outside Mesh"]
        ext["External HTTP Clients"]
        api["kube-apiserver<br/>(admission webhooks)"]
        prom["Prometheus<br/>(metrics scraping)"]
        tofu["Tofu Controller<br/>(flux-system)"]
    end

    subgraph Node["Kubernetes Node"]
        ztunnel["ztunnel<br/>(per-node L4 proxy)"]

        subgraph envoy["envoy-gateway-system"]
            eg["Envoy Gateway"]
        end

        subgraph kc["keycloak"]
            key["Keycloak"]
        end

        subgraph db["databases"]
            cnpg["CNPG Operator"]
            pg["PostgreSQL"]
            valkey["Valkey"]
            mongo["MongoDB"]
        end

        subgraph ec["e-commerce"]
            web["Web Frontend"]
            api_svc["API Services"]
        end

        subgraph ka["kafka"]
            strimzi["Strimzi Operator"]
            broker["Kafka Brokers"]
            entity["Entity Operator"]
        end
    end
    
    ext -->|"HTTPS (external)"| eg
    api -->|"TLS :443 → :9443<br/>webhook"| cnpg
    api -->|"TLS :8443<br/>webhook"| strimzi
    prom -->|"HTTP :9404"| broker
    prom -->|"HTTP :8080"| strimzi
    prom -->|"HTTP :8081"| entity
    prom -->|"HTTP :9187"| pg
    prom -->|"HTTP :9216"| mongo
    prom -->|"HTTP :9121"| valkey
    tofu -->|"HTTP :8080"| key

    eg <-->|"HBONE mTLS"| ztunnel
    key <-->|"HBONE mTLS"| ztunnel
    cnpg <-->|"HBONE mTLS"| ztunnel
    pg <-->|"HBONE mTLS"| ztunnel
    valkey <-->|"HBONE mTLS"| ztunnel
    mongo <-->|"HBONE mTLS"| ztunnel
    web <-->|"HBONE mTLS"| ztunnel
    api_svc <-->|"HBONE mTLS"| ztunnel
    strimzi <-->|"HBONE mTLS"| ztunnel
    broker <-->|"HBONE mTLS"| ztunnel
    entity <-->|"HBONE mTLS"| ztunnel

    style envoy fill:#e8f5e9,stroke:#2e7d32
    style kc fill:#fff3e0,stroke:#e65100
    style db fill:#e3f2fd,stroke:#1565c0
    style ec fill:#f3e5f5,stroke:#7b1fa2
    style ka fill:#fce4ec,stroke:#c62828

    envoyDesc["🟢 envoy-gateway-system<br/>PERMISSIVE — accepts external traffic"]
    kcDesc["🟠 keycloak<br/>PERMISSIVE :8080<br/>tofu runner outside mesh"]
    dbDesc["🔵 databases<br/>STRICT<br/>PERMISSIVE :9443 (CNPG webhook)<br/>PERMISSIVE :9187, :9216, :9121 (metrics)"]
    ecDesc["🟣 e-commerce<br/>STRICT — all internal"]
    kaDesc["🔴 kafka<br/>STRICT<br/>PERMISSIVE :8443, :8080 (Strimzi webhook)<br/>PERMISSIVE :9404, :8081 (metrics)"]
```
</pre>

### Mesh Configuration Summary

| Namespace | mTLS Mode | Exceptions | Reason |
|-----------|-----------|------------|--------|
| `envoy-gateway-system` | PERMISSIVE | — | External clients lack SPIFFE identities |
| `keycloak` | PERMISSIVE (port :8080) | Tofu Controller in `flux-system` (outside mesh) | Non-mesh client needs plaintext access to Keycloak API |
| `databases` | STRICT | PERMISSIVE :9443 (CNPG webhook), PERMISSIVE :9187 (CNPG metrics), PERMISSIVE :9216 (MongoDB metrics), PERMISSIVE :9121 (Valkey metrics) | kube-apiserver webhook calls + Prometheus scraping from outside mesh |
| `e-commerce` | STRICT | — | All workloads communicate within the mesh |
| `kafka` | STRICT | PERMISSIVE :8443, :8080 (Strimzi operator webhook + metrics), PERMISSIVE :9404 (broker JMX), PERMISSIVE :8081 (entity-operator metrics) | kube-apiserver webhook calls + Prometheus scraping from outside mesh |

### Enabling Ambient Mesh in a Namespace

Namespaces opt into the ambient mesh by adding the label:

```shell
kubectl label namespace <name> istio.io/dataplane-mode=ambient
```

Unlike sidecar mode, ambient mode requires no pod restarts — traffic
redirection through ztunnel is transparent to application containers.

### Namespace: envoy-gateway-system

Envoy Gateway serves as the ingress point for external HTTP traffic. Since
external clients lack SPIFFE identities, the namespace uses PERMISSIVE mTLS:

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: envoy-gateway-permissive
  namespace: envoy-gateway-system
spec:
  selector: {matchLabels: {}}
  mtls:
    mode: PERMISSIVE
```

### Namespace: keycloak

Keycloak requires special configuration due to three factors:

1. **Double mTLS encryption** — Keycloak auto-generates TLS certificates for
   JGroups (Infinispan distributed cache). When ztunnel wraps this traffic in
   HBONE mTLS, the certificates clash. Disable embedded JGroups mTLS in the
   Keycloak CR:

   ```yaml
   additionalOptions:
     - name: cache-embedded-mtls-enabled
       value: "false"
   ```

2. **Operator NetworkPolicy** — The Keycloak Operator creates a restrictive
   NetworkPolicy that blocks ztunnel infrastructure ports. An additive policy is
   required to allow HBONE tunnel termination (15008), waypoint proxy (15006),
   and Istio health/metrics ports (15020, 15021):

   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: keycloak-istio-mesh
     namespace: keycloak
   spec:
     podSelector:
       matchLabels:
         app: keycloak
         app.kubernetes.io/managed-by: keycloak-operator
     ingress:
       - ports:
           - {port: 15008, protocol: TCP}
           - {port: 15006, protocol: TCP}
           - {port: 15020, protocol: TCP}
           - {port: 15021, protocol: TCP}
       - from:
           - namespaceSelector:
               matchLabels:
                 kubernetes.io/metadata.name: istio-system
             podSelector:
               matchLabels:
                 app: ztunnel
         ports:
           - {port: 7800, protocol: TCP}
           - {port: 57800, protocol: TCP}
   ```

3. **Non-mesh client** — The Tofu Controller in `flux-system` runs outside the
   mesh. Port :8080 (Keycloak HTTP API) uses PERMISSIVE mTLS:

   ```yaml
   apiVersion: security.istio.io/v1
   kind: PeerAuthentication
   metadata:
     name: keycloak-permissive
     namespace: keycloak
   spec:
     selector:
       matchLabels:
         app: keycloak
     portLevelMtls:
       "8080":
         mode: PERMISSIVE
   ```

### Namespace: databases

The `databases` namespace hosts CloudNativePG, Valkey, and MongoDB operators.
Key considerations:

1. **Single namespace owner** — Three operators define the `databases` namespace.
   To prevent label-stripping races, `databases/common` is the sole owner of the
   namespace resource. All operators reference it rather than defining their own.

2. **CNPG admission webhook** — The `cnpg-webhook-service` serves TLS on
   container port 9443 (exposed via Service port 443). The kube-apiserver calls
   this webhook from outside the mesh without a SPIFFE identity. A
   pod-specific PERMISSIVE exception is needed:

   ```yaml
   apiVersion: security.istio.io/v1
   kind: PeerAuthentication
   metadata:
     name: databases-strict
     namespace: databases
   spec:
     selector: {matchLabels: {}}
     mtls:
       mode: STRICT
   ---
   apiVersion: security.istio.io/v1
   kind: PeerAuthentication
   metadata:
     name: cnpg-webhook-permissive
     namespace: databases
   spec:
     selector:
       matchLabels:
         app.kubernetes.io/name: cloudnative-pg
     portLevelMtls:
       "9443":
         mode: PERMISSIVE
   ```

   The pod-specific `cnpg-webhook-permissive` has a more specific selector and
   takes precedence over the namespace-wide `databases-strict`. Port 9443 is
   PERMISSIVE only for the CNPG operator pod; all other workloads and ports
   remain STRICT.

3. **Prometheus metrics scraping** — Prometheus runs in `kube-prom-stack`, outside the mesh
   without a SPIFFE identity. Each database type exposes metrics on a dedicated port
   that must be PERMISSIVE to allow scraping. A separate PeerAuthentication targets
   each workload's pod labels for least-privilege exceptions:

   | Database | Port | PeerAuthentication | Selector |
   |----------|------|--------------------|----------|
   | CloudNative-PG (e-commerce) | 9187 | `cnpg-metrics-permissive` | `cnpg.io/cluster: postgres-ecommerce` |
   | CloudNative-PG (Keycloak) | 9187 | `postgres-keycloak-metrics-permissive` | `cnpg.io/cluster: postgres-keycloak` |
   | MongoDB | 9216 | `mongodb-metrics-permissive` | `app: mongodb-svc` |
   | Valkey | 9121 | `valkey-metrics-permissive` | `app.kubernetes.io/name: valkey` |

   Example for the e-commerce CNPG cluster:

   ```yaml
   apiVersion: security.istio.io/v1
   kind: PeerAuthentication
   metadata:
     name: cnpg-metrics-permissive
     namespace: databases
   spec:
     selector:
       matchLabels:
         cnpg.io/cluster: postgres-ecommerce
     portLevelMtls:
       "9187":
         mode: PERMISSIVE
   ```

   {{site.data.alerts.note}}

   Each database workload requires its own PeerAuthentication because the pod label
   selectors are database-specific. Policies are placed in the component that owns
   the workload: e-commerce database policies in `apps/e-commerce/config/databases/components/`,
   Keycloak database policies in `platform/keycloak/database/components/`.

   {{site.data.alerts.end}}

### Namespace: e-commerce

Standard ambient mesh with STRICT mTLS — no exceptions needed. All e-commerce
workloads communicate within the mesh or through the Envoy Gateway:

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: e-commerce-strict
  namespace: e-commerce
spec:
  selector: {matchLabels: {}}
  mtls:
    mode: STRICT
```

### Namespace: kafka

The Kafka namespace requires STRICT mTLS with several PERMISSIVE exceptions:

1. **Strimzi admission webhooks** — The Strimzi operator deploys validating and
   mutating webhooks on port 8443. The kube-apiserver calls these from outside
   the mesh without a SPIFFE identity.

2. **Prometheus metrics scraping** — Prometheus runs in `kube-prom-stack`
   (outside the mesh) and scrapes metrics from Kafka brokers (port 9404),
   Strimzi operator (port 8080), and entity-operator (port 8081).

```yaml
# Namespace-wide default
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: kafka-strict
  namespace: kafka
spec:
  selector: {matchLabels: {}}
  mtls:
    mode: STRICT
---
# Strimzi operator: PERMISSIVE on webhook and metrics ports
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: strimzi-operator-permissive
  namespace: kafka
spec:
  selector:
    matchLabels:
      strimzi.io/kind: cluster-operator
  portLevelMtls:
    "8443":
      mode: PERMISSIVE
    "8080":
      mode: PERMISSIVE
---
# Kafka broker JMX metrics
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: kafka-broker-metrics-permissive
  namespace: kafka
spec:
  selector:
    matchLabels:
      strimzi.io/kind: Kafka
  portLevelMtls:
    "9404":
      mode: PERMISSIVE
---
# Entity Operator health/metrics
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: entity-operator-metrics-permissive
  namespace: kafka
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: entity-operator
  portLevelMtls:
    "8081":
      mode: PERMISSIVE
```

Pod-specific PeerAuthentications have more specific selectors and take
precedence over the namespace-wide `kafka-strict`. Webhook and metrics ports are
PERMISSIVE only for the targeted pods.

#### Kafka Listeners and Ambient Mesh

Kafka uses three listeners with different interactions with the mesh:

| Listener | Port | TLS | Mesh Interaction |
|----------|------|-----|------------------|
| Plain (internal) | 9092 | None | ztunnel HBONE provides transport encryption — no app-level TLS needed |
| TLS (internal) | 9093 | TLS | ztunnel wraps in HBONE mTLS ("double encryption"); redundant with mesh |
| External | 9094 | TLS Passthrough | External clients negotiate TLS end-to-end with brokers via Envoy Gateway; ztunnel is transparent at L4 |

The Strimzi operator has `generateNetworkPolicy: false`, so no operator-created
NetworkPolicies conflict with ztunnel. Unlike Keycloak, no additive
NetworkPolicy is needed.

### Istio Infrastructure Ports

When operator-created NetworkPolicies restrict pod ingress, the following
ztunnel/ambient mesh ports must be explicitly allowed:

| Port | Purpose |
|------|---------|
| 15006 | Waypoint proxy |
| 15008 | HBONE tunnel termination |
| 15020 | Istio health checks |
| 15021 | Istio metrics |

These ports are required for ambient mesh to function when NetworkPolicies are
present. Without them, ztunnel cannot deliver proxied traffic to pods.


## References

- Install istio using Helm chart: https://istio.io/latest/docs/setup/install/helm/ 
- Istio getting started: https://istio.io/latest/docs/setup/getting-started/
- Kiali: https://kiali.io/
- NGINX Ingress vs Istio gateway: https://imesh.ai/blog/kubernetes-nginx-ingress-vs-istio-ingress-gateway/
- [Istio ambient mesh traffic redirection](https://istio.io/latest/docs/ambient/architecture/traffic-redirection/)
- [Keycloak: Configuring distributed caches](https://www.keycloak.org/server/caching)
- [Keycloak: Running inside a service mesh](https://www.keycloak.org/server/caching#_running_inside_a_service_mesh)
