---
title: Service Mesh (Linkerd)
permalink: /docs/service-mesh/
description: How to deploy service-mesh architecture based on Linkerd.

---

## Why a Service Mesh

Introduce Service Mesh architecture to add observability, traffic management, and security capabilities to internal communications within the cluster.

[Linkerd](https://linkerd.io/) will be deployed in the cluster as a Service Mesh implementation.

## Why Linkerd and not Istio

Most known Service Mesh implementation, [Istio](https://istio.io), is not currently supporting ARM64 architecture.

[Linkerd](https://linkerd.io/), which is a CNCF graduated project, does support ARM64 architectures since release 2.9 (see [linkerd 2.9 announcement](https://linkerd.io/2020/11/09/announcing-linkerd-2.9/).

Moreover,instead of using [Envoy proxy](https://www.envoyproxy.io/), sidecar container  to be deployed with any Pod as communication proxy, Linkerd uses its own ulta-light proxy which reduces the required resource footprint (cpu, memory) and makes it more suitable for Raspberry Pis.

## Automatic mTLS

By default, Linkerd automatically enables mutually-authenticated Transport Layer Security (mTLS) for all TCP traffic between meshed pods. This means that Linkerd adds authenticated, encrypted communication to your application with no extra work on your part. (And because the Linkerd control plane also runs on the data plane, this means that communication between Linkerd’s control plane components are also automatically secured via mTLS.)

The Linkerd control plane contains a certificate authority (CA) called `identity`. This CA issues TLS certificates to each Linkerd data plane proxy. These TLS certificates expire after 24 hours and are automatically rotated. The proxies use these certificates to encrypt and authenticate TCP traffic to other proxies.

On the control plane side, Linkerd maintains a set of credentials in the cluster: a **trust anchor**, and an **issuer certificate and private key**. While Linkerd automatically rotates the TLS certificates for data plane proxies every 24 hours, it does not rotate the TLS credentials and private key associated with the issuer. `cert-manager` can be used to initially generate this issuer certificate and private key and automatically rotate them.

## Linkerd Installation

Installation procedure to use cert-manager and bein able to automatically rotate control-plane tls credentiasl is described in [linkerd documentation](https://linkerd.io/2.11/tasks/automatically-rotating-control-plane-tls-credentials/).

The following instalation procedure is a slightly different from the one proposed in that documentation since we will use as linkerd trust-anchor the root CA and CA ClusterIssuer already created during Cert-manager installation and configuration for the cluster.

### Installation pre-requisite: Configure Cert-Manager

Cert-manager need to be configured to act as an on-cluster CA and to re-issue Linkerd’s issuer certificate and private key on a periodic basis.

Cert-manager CA root certificate (trust-anchor) and CA Cluster issuer is already configured as part of [Cert-Manager installation and configuration](/docs/certmanager/).

That trust-anchor anc ClusterIssuer will be used to generate linkerd certificate used as CA for signing linkerd's mTLS certificates.

### Linkerd Installation using Helm

Installation using `Helm` (Release 3):

- Step 1: Add the Linkerd Helm stable repository:

    ```shell
    helm repo add linkerd https://helm.linkerd.io/stable
    ```
- Step2: Fetch the latest charts from the repository:

    ```shell
    helm repo update
    ```
- Step 3: Create namespace

  By default, the helm chart creates the control plane namespace with the `config.linkerd.io/admission-webhooks: disabled` label. It is required for the control plane to work correctly.creates the namespace annotated and labeled.

  Since we are creating the namespace we need to provide the same labels and annotations.

  Create namespace manifest file `linkerd_namespace.yml`

  ```yml
  kind: Namespace
  apiVersion: v1
  metadata:
    name: linkerd
    annotations:
      linkerd.io/inject: disabled
    labels:
      linkerd.io/is-control-plane: "true"
      config.linkerd.io/admission-webhooks: disabled
      linkerd.io/control-plane-ns: linkerd
  ```

  And apply the manifest with the following command:


  ```shell
  kubectl apply -f linkerd_namespace.yml
  ```

- Step 4: Create `linkerd-identity-issuer` certificate resource

  Create file `linkerd-identity-issuer.yml`

  ```yml
  apiVersion: cert-manager.io/v1
  kind: Certificate
  metadata:
    name: linkerd-identity-issuer
    namespace: linkerd
  spec:
    secretName: linkerd-identity-issuer
    duration: 48h
    renewBefore: 25h
    issuerRef:
      name: ca-issuer
      kind: ClusterIssuer
      group: cert-manager.io
    commonName: identity.linkerd.cluster.local
    dnsNames:
    - identity.linkerd.cluster.local
    isCA: true
    privateKey:
      algorithm: ECDSA
    usages:
    - cert sign
    - crl sign
    - server auth
    - client auth
  ```

  ClusterIssuer `ca-issuer`, created as part of cert-manager configuration, is used to sign this certificate.

  `duration`  instructs cert-manager to consider certificates as valid for 48 hours and `renewBefore` indicates that cert-manager will attempt to issue a new certificate 25 hours before expiration of the current one.

  Certificate is creates as CA (isCA:true) because it will be use by linkerd to issue mTLS certificates.

- Step 2: Command certmanger to create the `Certificate` and the associated `Secret`.

  ```shell
  kubectl apply -f linkerd-identity-issuer.yml
  ```

- Step 3: Get CA certificate used to sign the linkerd-identy-issuer certificate

  Linkerd installation procedure (using Helm chart of `linkerd` CLI), requires to pass as parameter the trust-anchor (root certiticate) used to sign the linkerd-identy-issuer. It can be obtained from the associated Secret with the following commad.

  ```shell
  kubectl get secret linkerd-identity-issuer -o jsonpath="{.data.ca\.crt}" -n linkerd | base64 -d > ca.crt
  ```

- Step 4: Install Linkerd

    ```shell
    helm install linkerd2 \
    --set-file identityTrustAnchorsPEM=ca.crt \
    --set identity.issuer.scheme=kubernetes.io/tls \
    --set installNamespace=false \
    linkerd/linkerd2 \
    -n linkerd
    ```

- Step 5: Confirm that the deployment succeeded, run:

    ```shell
    kubectl -n linkerd get pod
    ```

- Step 6: Check linkerd control plane configmap

  Check that the ca.crt is properly included in linkerd configmap

  ```shell
  kubectl get configmap linkerd-config -o yaml -n linkerd
  ```
  
  The `identiyTrustAnchorPEM` key included in the Configmap should show th ca.crt extracted in Step 3

  ```yml
  identityTrustAnchorsPEM: |-
  -----BEGIN CERTIFICATE-----
  MIIBbzCCARWgAwIBAgIRAKTg35A0zYXdNKIfOfzmvBswCgYIKoZIzj0EAwIwFzEV
  MBMGA1UEAxMMcGljbHVzdGVyLWNhMB4XDTIyMDMwODEyMTYxM1oXDTIyMDYwNjEy
  MTYxM1owFzEVMBMGA1UEAxMMcGljbHVzdGVyLWNhMFkwEwYHKoZIzj0CAQYIKoZI
  zj0DAQcDQgAEYcZquh74RiIWje8/PHC8haksDdjvQroRrZQnsKP9j/LL+C0qLx9n
  7Fs3nLMQ6ipRZ1KV9k/sP0nFHzI4G4W3wKNCMEAwDgYDVR0PAQH/BAQDAgKkMA8G
  A1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFM+IzMMYOlVcCe0BEBvmVKGO7RF9MAoG
  CCqGSM49BAMCA0gAMEUCIBRop9dU9iDuZRVlxFLjwwxnQxL601atw/298/wQWdzn
  AiEAwlZ6RTYjoN4XHxQnz2yZhu7ACsjX5p3oSNnL2nOs+7k=
  -----END CERTIFICATE-----
  ```

### Linkerd Viz extension installation

Linkerd provides a full on-cluster metrics stack, a web dashboard, and pre-configured Grafana dashboards. This is the linkerd viz extension.

This extension installs the following components into a new namespace linkerd-viz:

- A Prometheus instance
- A Grafana instance
- metrics-api, tap, tap-injector, and web components

Since we have already our monitoring deployment, we will configure Viz extension to use the existing Prometheus and Grafana instance. See linkerd documentation ["Bringing your own Prometheus"](https://linkerd.io/2.11/tasks/external-prometheus/).


linkerd-viz dashboard (web component) will be exposed configuring a Ingress resource. By default linkerd-viz dashboard has a DNS rebinding protection. Since Traefik does not support a mechanism for ovewritting Host header, the Host validation regexp that the dashboard server uses need to be tweaked using Helm chart paramenter `enforcedHostRegexp`. See document ["Exposing dashboard - DNS Rebinding Protection"](https://linkerd.io/2.11/tasks/exposing-dashboard/#dns-rebinding-protection) for more details.


- Step 1: Create namespace

  By default, the helm chart creates a namespace `linkerd-viz` with annotations `linkerd.io/inject: enabled` and `config.linkerd.io/proxy-await: "enabled"`

  Since we are creating the namespace we need to provide the same labels and annotations.

  Create namespace manifest file `linkerd_viz_namespace.yml`

  ```yml
  kind: Namespace
  apiVersion: v1
  metadata:
    name: linkerd-viz
    annotations:
      linkerd.io/inject: enabled
      config.linkerd.io/proxy-await: "enabled"
    labels:
      linkerd.io/extension: viz
  ```

  And apply the manifest with the following command:


  ```shell
  kubectl apply -f linkerd_viz_namespace.yml
  ```


- Step 2: Prepare values.yml for Viz helm chart installation

  ```yml
  # Skip namespace creation
  installNamespace: false
  # Disable Prometheus installation and configure external Prometheus URL
  prometheusUrl: http://kube-prometheus-stack-prometheus.k3s-monitoring.svc.cluster.local:9090
  prometheus:
    enabled: false
  # Disable Grafana installation and configure external Grafana URL
  grafana:
    enabled: false
  grafanaUrl: kube-prometheus-stack-grafana.k3s-monitoring.svc.cluster.local:80
  # Disabling DNS rebinding protection
  dahsboard:
    enforcedHostRegexp: ".*"
  ```

- Step 3: Install linkerd viz extension helm

  ```shell
  helm install linkerd-viz -n linkerd-viz -f values.yml
  ```
  By default, helm chart creates `linkerd-viz` namespace where all components are deployed.


- Step 4: Exposing Linkerd Viz dashboard

  Ingress controller rule can be defined to grant access to Viz dashboard. 

  In case of Traefik, it is not needed to mesh Traefik deployment to grant access

  Linkerd documentation contains information about how to configure [Traefik as Ingress Controller](https://linkerd.io/2.11/tasks/exposing-dashboard/#traefik). To enable mTLS in the communication from Ingress Controller, Traefik deployment need to be meshed using "ingress" proxy injection.

- Step 5: Configure Prometheus to scrape metrics from linkerd
  
  Create `linkerd-prometheus.yml`
  
  ```yml
  ---
  apiVersion: monitoring.coreos.com/v1
  kind: PodMonitor
  metadata:
    labels:
      app: linkerd
      release: kube-prometheus-stack
    name: linkerd-controller
    namespace: k3s-monitoring
  spec:
    namespaceSelector:
      matchNames:
        - linkerd-viz
        - linkerd
    selector:
      matchLabels: {}
    podMetricsEndpoints:
      - interval: 10s
        scrapeTimeout: 10s
        relabelings:
        - sourceLabels:
          - __meta_kubernetes_pod_container_port_name
          action: keep
          regex: admin-http
        - sourceLabels:
          - __meta_kubernetes_pod_container_name
          action: replace
          targetLabel: component
        # Replace job value
        - source_labels:
          - __address__
          action: replace
          targetLabel: job
          replacement: linkerd-controller
  ---
  apiVersion: monitoring.coreos.com/v1
  kind: PodMonitor
  metadata:
    labels:
      app: linkerd
      release: kube-prometheus-stack
    name: linkerd-service-mirror
    namespace: k3s-monitoring
  spec:
    namespaceSelector:
      any: true
    selector:
      matchLabels: {}
    podMetricsEndpoints:
      - interval: 10s
        scrapeTimeout: 10s
        relabelings:
        - sourceLabels:
          - __meta_kubernetes_pod_label_linkerd_io_control_plane_component
          - __meta_kubernetes_pod_container_port_name
          action: keep
          regex: linkerd-service-mirror;admin-http$
        - sourceLabels:
          - __meta_kubernetes_pod_container_name
          action: replace
          targetLabel: component
        # Replace job value
        - source_labels:
          - __address__
          action: replace
          targetLabel: job
          replacement: linkerd-service-mirror
  ---
  apiVersion: monitoring.coreos.com/v1
  kind: PodMonitor
  metadata:
    labels:
      app: linkerd
      release: kube-prometheus-stack
    name: linkerd-proxy
    namespace: k3s-monitoring
  spec:
    namespaceSelector:
      any: true
    selector:
      matchLabels: {}
    podMetricsEndpoints:
      - interval: 10s
        scrapeTimeout: 10s
        relabelings:
        - sourceLabels:
          - __meta_kubernetes_pod_container_name
          - __meta_kubernetes_pod_container_port_name
          - __meta_kubernetes_pod_label_linkerd_io_control_plane_ns
          action: keep
          regex: ^linkerd-proxy;linkerd-admin;linkerd$
        - sourceLabels: [__meta_kubernetes_namespace]
          action: replace
          targetLabel: namespace
        - sourceLabels: [__meta_kubernetes_pod_name]
          action: replace
          targetLabel: pod
        - sourceLabels: [__meta_kubernetes_pod_label_linkerd_io_proxy_job]
          action: replace
          targetLabel: k8s_job
        - action: labeldrop
          regex: __meta_kubernetes_pod_label_linkerd_io_proxy_job
        - action: labelmap
          regex: __meta_kubernetes_pod_label_linkerd_io_proxy_(.+)
        - action: labeldrop
          regex: __meta_kubernetes_pod_label_linkerd_io_proxy_(.+)
        - action: labelmap
          regex: __meta_kubernetes_pod_label_linkerd_io_(.+)
        - action: labelmap
          regex: __meta_kubernetes_pod_label_(.+)
          replacement: __tmp_pod_label_$1
        - action: labelmap
          regex: __tmp_pod_label_linkerd_io_(.+)
          replacement:  __tmp_pod_label_$1
        - action: labeldrop
          regex: __tmp_pod_label_linkerd_io_(.+)
        - action: labelmap
          regex: __tmp_pod_label_(.+)
        # Replace job value
        - source_labels:
          - __address__
          action: replace
          targetLabel: job
          replacement: linkerd-proxy
  ``` 
  
  Apply manifest file

  ```shell
  kubectl apply -f linkerd-prometheus.yml
  ```

  {{site.data.alerts.note}}

  This is a direct translation of the [Prometheus' scrape configuration defined in linkerd documentation](https://linkerd.io/2.11/tasks/external-prometheus/#prometheus-scrape-configuration) to Prometheus Operator based configuration (ServiceMonitor and PodMonitor CRDs).

  Only two additional changes have been added to match linkerd's Grafana dashboards configuration:

  - Changing `job` label: Prometheus operator by default creates job names and job labels with `<namespace>/<podMonitor/serviceMonitor_name>`. Additional relabel rule has been added to remove namespace from job label matching Grafana dashboard's filters

  - Changing scraping `interval` and `timeout` to 10 seconds, instead default prometheus configuration (30 seconds). Linkerd's Grafana dashboards are configured to calculate rates from metrics in the last 30 seconds.

  {{site.data.alerts.end}}
   
- Step 6: Load linkerd dashboards into Grafana
  
  Linkerd available Grafana dashboards are located in linkerd2 repository: [linkerd grafana dashboards](https://github.com/linkerd/linkerd2/tree/main/grafana/dashboards)

  Follow ["Provision dashboards automatically"](/docs/prometheus/#provisioning-dashboards-automatically) procedure to load Grafana dashboards automatically.


## Meshing a service with linkerd

There are two common ways to define a resource as meshed with Linkerd:

- **Explicit**: add `linkerd.io/inject: enabled` annotation per resource. Annotated pod deployment is injected with linkerd-proxy.

  Annotation can be added automatically using `linkerd` command to inject the annotation
  
  ```shell
  kubectl get -n NAMESPACE deploy -o yaml | linkerd inject - | kubectl apply -f -
  ```
  
  This command takes all deployments resoureces from NAMESPACE and inject the annotation, so linkerd can inject linkerd-proxy automatically


- **Implicit**: add `linkerd.io/inject: enabled` annotation for a namespace. Any new pod created within the namespace is automatically injected with linkerd-proxy.

  Using kubectl:
  ```shell
  kubectl annotate ns <namespace_name> linkerd.io/inject=enabled
  ```
  
  Through manifest file during namespace creation or patching the resource.
  ```yml
  kind: Namespace
  apiVersion: v1
  metadata:
    name: test
    annotations:
      linkerd.io/inject: enabled
  ```

### Problems with Kuberentes Jobs and implicit annotation


With `linkerd.io/inject: enabled` annotation at namespace level, [Kubernetes Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/) do not terminate after completion since the Pods created are injected with linkerd-proxy and it continues to run after the job container completes its work. 

That behaviour might cause errors during helm chart installation that deploy Jobs or during executions of scheduled CronJobs.

As stated in this [blog post](https://itnext.io/three-ways-to-use-linkerd-with-kubernetes-jobs-c12ccc6d4c7c) there are different ways to handle this issue, both of them requires to modify Job template definition: 

1) Do not mesh the Jobs resources

Adding `linkerd.io/inject: disabled` annotation to job template definition.

```yml
jobTemplate:
  spec:
    template:
      metadata:
        annotations:
          linkerd.io/inject: disabled
```

2) Shuting down linkerd-proxy as part of the Job execution. 

This can be done using [`linkerd-await`](https://github.com/linkerd/linkerd-await) as wrapper of the main job command. 
`linkerd-await` waits till linkerd-proxy is ready then executes the main job command and, when it finishes, it calls the linkerd-proxy `/shutdown` endpoint. 
  ```shell
  linked-await --shutdown option <job_commad>
  ```

See details of implementation of this second workarround [here](https://itnext.io/three-ways-to-use-linkerd-with-kubernetes-jobs-c12ccc6d4c7c)


## Meshing cluster services

### Longhorn distributed Storate

#### Error installing Longhorn with namespace implicit annotation

When installing longhorn installation hangs when deploying CSI plugin.

`longhorn-driver-deployer` pod crashes showing an error "Got an error when checking MountProgapgation with node status, Node XX is not support mount propagation"


```sh
oss@node1:~$ kubectl get pods -n longhorn-system
NAME                                        READY   STATUS             RESTARTS        AGE
longhorn-ui-84f97cf569-c6fcq                2/2     Running            0               15m
longhorn-manager-cc7tt                      2/2     Running            0               15m
longhorn-manager-khrx6                      2/2     Running            0               15m
longhorn-manager-84zwx                      2/2     Running            0               15m
instance-manager-e-86ec5db9                 2/2     Running            0               14m
instance-manager-r-cdcb538b                 2/2     Running            0               14m
engine-image-ei-4dbdb778-bc9q2              2/2     Running            0               14m
instance-manager-r-0d602480                 2/2     Running            0               14m
instance-manager-e-429cc6bf                 2/2     Running            0               14m
instance-manager-e-af266d5e                 2/2     Running            0               14m
instance-manager-r-02fad614                 2/2     Running            0               14m
engine-image-ei-4dbdb778-2785c              2/2     Running            0               14m
engine-image-ei-4dbdb778-xrj4k              2/2     Running            0               14m
longhorn-driver-deployer-6bc898bc7b-nmzkc   1/2     CrashLoopBackOff   6 (2m46s ago)   15m
oss@node1:~$ kubectl logs longhorn-driver-deployer-6bc898bc7b-nmzkc longhorn-driver-deployer -n longhorn-system
2022/03/20 12:42:58 proto: duplicate proto type registered: VersionResponse
W0320 12:42:58.148324       1 client_config.go:552] Neither --kubeconfig nor --master was specified.  Using the inClusterConfig.  This might not work.
time="2022-03-20T12:43:48Z" level=warning msg="Got an error when checking MountPropagation with node status, Node node2 is not support mount propagation"
time="2022-03-20T12:43:48Z" level=fatal msg="Error deploying driver: CSI cannot be deployed because MountPropagation is not set: Node node2 is not support mount propagation"
```

### Prometheus Stack

To mesh with linkerd all Prometheus-stack services, implicit annotation at namespace level can be used before deploying kube-prometheys-stack chart.


When deploying `kube-prometheus-stack` helm using an annotated namespace (`linkerd.io/inject: enabled`), causes the Prometheus Operartor to hung.

Job pod `pod/kube-prometheus-stack-admission-create-<randomAlphanumericString>` is created and its status is always `NotReady` since the linkerd-proxy continues to run after the job container ends so the Job Pod never ends.

See [linkerd Prometheus Operator issue](https://github.com/prometheus-community/helm-charts/issues/479). 

To solve this issue linkerd injection must be disabled in the associated jobs created by Prometheus Operator. This can be achieved adding the following parameters to `values.yml` file of kube-prometheus-stack helm chart.

```yml
prometheusOperator:
  admissionWebhooks:
    patch:
      podAnnotations:
        linkerd.io/inject: disabled
```

Modify [Prometheus installation procedure](/docs/monitoring/) to annotate the corresponding namespace before deploying the helm chart and use the modified values.yml file.

```shell
kubectl annotate ns k3s-monitoring linkerd.io/inject=enabled
```

{{site.data.alerts.note}}

`node-exporter` daemonset, which are part of kube-prometheus-stack, are not injected with linkerd-proxy becasue its PODs use hosts network namespace `spec.hostNework=true`. Linkerd injection is disabled for pods with hostNetwork=true.

If you try to inject manually:

```shell
kubectl get daemonset -n k3s-monitoring -o yaml | linkerd inject -

Error transforming resources:
failed to inject daemonset/kube-prometheus-stack-prometheus-node-exporter: hostNetwork is enabled
```

{{site.data.alerts.end}}


### EFK

To mesh with linkerd all EFK services, it is enough to use the implicit annotation at namespace level before deploying ECK Operator and create Kibana and Elasticsearch service and before deploying fluentbit chart.

Modify [EFK installation procedure](/docs/logging/) to annotate the corresponding namespace before deploying the helm charts.

```shell
kubectl annotate ns elastic-system linkerd.io/inject=enabled

kubectl annotate ns k3s-logging linkerd.io/inject=enabled
```

When deploying Elasticsearch and Kibana using the ECK operator, it is needed to specify the parameter `automountServiceAccountToken: true`, otherwise the linkerd-proxy is not injected.

The following configuration need to be added to Elastic and Kibana resources

```yml
podTemplate:
  spec:
    automountServiceAccountToken: true

```

For details about how to integrate with linkerd Elastic stack components using ECK operator, see [ECK-linkerd document](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-service-mesh-linkerd.html).


{{site.data.alerts.important}}

Elasticsearch automatic TLS configuration that was itinitially configured has been disabled, so Linkerd can gather more metrics about the connections. See [issue #45](https://github.com/ricsanfre/pi-cluster/issues/45)

{{site.data.alerts.end}}


## Configure Ingress Controller

Linkerd does not come with a Ingress Controller. Existing ingress controller can be integrated with Linkerd doing the following:

  - Configuring Ingress Controller to support Linkerd.
  - Meshing Ingress Controller pods so that they have the Linkerd proxy installed.

Linkerd can be used with any ingress controller. In order for Linkerd to properly apply features such as route-based metrics and traffic splitting, Linkerd needs the IP/port of the Kubernetes Service as the traffic destination. However, by default, many ingresses, like Traefik, do their own load balance and endpoint selection when forwarding HTTP traffic pass the IP/port of the destination Pod, rather than the Service as a whole.

In order to enable linkerd implementation of load balancing at HTTP request level, Traefik load balancing mechanism must be skipped.

More details in linkerd documentation ["Ingress Traffic"](https://linkerd.io/2.11/tasks/using-ingress/).


### Meshing Traefik

In order to integrate Traefik with Linkerd the following must be done:

1. Traefik must be meshed with `ingress mode` enabled, i.e. with the `linkerd.io/inject: ingress` annotation rather than the default enabled.
  
   Executing the following command Traefik deployment is injected with  linkerd-proxy in ingress mode:

   ```shell
   kubectl get deployment traefik -o yaml -n kube-system | linkerd inject --ingress - | kubectl apply -f -
   ```

   {{site.data.alerts.important}}

   In ingress mode only HTTP traffic is routed by linkerd-proxy. Traefik will stop routing any HTTPS traffic. In this mode we must be sure that Traefil will end all TLS communications coming from ourside de cluster and that it communicate with the internal services only using HTTP.

   This is how we have configured all services within the cluster. Disabling TLS configurations of all internal HTTP services.

   Linkerd at platform level provides that TLS secure layer.

   HTTP communications from clients outside the cluster are secured by Traefik (closing external TLS sessions). From Traefik traffic routing to the cluster will be secured by Linkerd-proxy.

   {{site.data.alerts.end}}

   Since Traefik needs to talk to Kubernetes API using HTTPS standard port (to impliments its own routing and load balancing mechanism), this mode of execution breaks Traefik unless outbound communications using port 443 skips the linkerd-proxy.

   For making Traefik still working with its own loadbalancing/routing mechanism the following command need to be executed.

   ```shell
   kubectl get deployment traefik -o yaml -n kube-system | linkerd inject --ingress --skip-outbound-ports 443 - | kubectl apply -f - 
   ```

   See [Linkerd discussion #7387](https://github.com/linkerd/linkerd2/discussions/7387) for further details about this issue.

   Alternative the Traefik helm chart can be configured so the deployed pod contains the required linkerd annotations to enable the ingress mode and skip port 443. The following additional values must be provided

   ```yml
   deployment:
      podAnnotations:
        linkerd.io/inject: ingress
        config.linkerd.io/skip-outbound-ports: "443"
   ```

   Traefik is a K3S embedded components that is auto-deployed using Helm. In order to configure Helm chart configuration parameters the official [document](https://rancher.com/docs/k3s/latest/en/helm/#customizing-packaged-components-with-helmchartconfig) must be followed. See how to do it in [Traefik configuration documentation](/docs/traefik/)



2. Replace Traefik routing and load-balancing mechanism by linkerd-proxy routing and load balancing mechanism.

   Configure Ingress resources to use a Traefik's Middleware inserting a specific header, `l5d-dst-override` pointing to the Service IP/Port (using internal DNS name: `<service-name>.<namespace-name>.svc.cluster.local`

   Linkerd-proxy configured in ingress mode will take `ld5-dst-override` HTTP header for routing the traffic to the service.

   When an HTTP (not HTTPS) request is received by a Linkerd proxy, the destination service of that request is identified. 

   The destination service for a request is computed by selecting the value of the first HTTP header to exist of, `l5d-dst-override`, `:authority`, and `Host`. The port component, if included and including the colon, is stripped. That value is mapped to the fully qualified DNS name.


   Per ingress resource do the following:

   - Step 1: Create Middleware routing for providing l5d-dst-override HTTP header

      ```yml
      apiVersion: traefik.containo.us/v1alpha1
      kind: Middleware
      metadata:
        name: l5d-header-middleware
        namespace: my-namespace
      spec:
        headers:
          customRequestHeaders:
            l5d-dst-override: "my-service.my-namespace.svc.cluster.local:80"

      ```
    - Step 2: Add traefik middleware annotation to Ingress definition

      ```yml
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: my-ingress
        namespace: my-namespace
        annotations:
          traefik.ingress.kubernetes.io/router.middlewares:
            my-namespace-l5d-header-middleware@kubernetescrd

      ```

{{site.data.alerts.note}}

Since Traefik terminates TLS, this TLS traffic (e.g. HTTPS calls from outside the cluster) will pass through Linkerd as an opaque TCP stream and Linkerd will only be able to provide byte-level metrics for this side of the connection. The resulting HTTP or gRPC traffic to internal services, of course, will have the full set of metrics and mTLS support.

{{site.data.alerts.end}}

## References

- How Linkerd uses iptables to transparently route Kubernetes traffic [[1]](https://linkerd.io/2021/09/23/how-linkerd-uses-iptables-to-transparently-route-kubernetes-traffic/)
- Protocol Detection and Opaque Ports in Linkerd [[2]](https://linkerd.io/2021/02/23/protocol-detection-and-opaque-ports-in-linkerd/)
- How to configure linkerd service-mesh with Elastic Cloud Operator [[3]](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-service-mesh-linkerd.html)
- x [[4]]()
- x [[5]]()
