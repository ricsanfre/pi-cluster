---
title: Ingress Controller (Traefik)
permalink: /docs/traefik/
description: How to configure Ingress Contoller based on Traefik in our Pi Kuberentes cluster.
last_modified_at: "04-01-2024"
---

{{site.data.alerts.important}} **Deprecated Technology in PiCluster project**

Ingress Controller solution for the cluster has been migrated to NGINX in release 1.8.
Traefik technology has been deprecated and this documentation is not updated anymore.

Reasons behind this decission in [PiCluster 1.8 release announcement](/blog/2024/01/04/announcing-release-1.8/).

See alternative Ingress Controller solution documentation: ["Ingress Controller (NGINX)"](/docs/nginx/).

{{site.data.alerts.end}}

All HTTP/HTTPS traffic comming to K3S exposed services should be handled by an Ingress Controller.
K3S default installation comes with Traefik HTTP reverse proxy which is a Kuberentes compliant Ingress Controller.

Traefik is a modern HTTP reverse proxy and load balancer made to deploy microservices with ease. It simplifies networking complexity while designing, deploying, and running applications.

{{site.data.alerts.note}}

Traefik K3S add-on is disabled during K3s installation, so it can be installed manually to have full control over the version and its initial configuration.

K3s provides a mechanism to customize traefik chart once the installation is over, but some parameters like namespace to be used cannot be modified. By default it is installed in `kube-system` namespace. Specifying a specific namespace `traefik` for all resources that need to be created for configuring Traefik will keep kubernetes configuration cleaner than deploying everything on `kube-system` namespace.

{{site.data.alerts.end}}


Traefik is able to manage access to Kubernetes Services by supporting the `Ingress` and `Gateway API` resource specs.
It also extends Kubernetes API defining new custom resource types (Kubernetes Custom Resources Definition (CRD): `IngressRoute` and `Middleware` 

- `IngressRoute` Traefik's custom resource is an extension of `Ingress` resources to provide an alternative way to configure access to a Kubernetes cluster.
- `Middleware` resources make possible tweaking the requests before they are sent backend service (or before the answer from the services are sent to the clients).

See detailed information in Traefik's documentation:
- [Traefik's Kuberentes Ingress](https://doc.traefik.io/traefik/providers/kubernetes-ingress/)
- [Traefik's Kuberentes IngressRoute](https://doc.traefik.io/traefik/providers/kubernetes-crd/)
- [Traefik's Kubernetes Gateway API](https://doc.traefik.io/traefik/providers/kubernetes-gateway/)
- [Traefik's Middelware](https://doc.traefik.io/traefik/middlewares/overview/)

## Configuring access to cluster services with Traefik

Standard kuberentes resource, `Ingress`, or specific Traefik resource, `IngressRoute` can be used to configure the access to cluster services through HTTP proxy capabilities provide by Traefik.

Following instructions details how to configure access to cluster service using standard `Ingress` resources where Traefik configuration is specified using annotations.


### Enabling HTTPS and TLS 

All externally exposed frontends deployed on the Kubernetes cluster should be accessed using secure and encrypted communications, using HTTPS protocol and TLS certificates. If possible those TLS certificates should be valid public certificates.

#### Enabling TLS in Ingress resources

As stated in [Kubernetes documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls), Ingress access can be secured using TLS by specifying a `Secret` that contains a TLS private key and certificate. The Ingress resource only supports a single TLS port, 443, and assumes TLS termination at the ingress point (traffic to the Service and its Pods is in plaintext).

[Traefik documentation](https://doc.traefik.io/traefik/routing/providers/kubernetes-ingress/), defines several Ingress resource annotations that can be used to tune the behavioir of Traefik when implementing a Ingress rule.

Traefik can be used to terminate SSL connections, serving internal not secure services by using the following annotations:
- `traefik.ingress.kubernetes.io/router.tls: "true"` makes Traefik to end TLS connections
- `traefik.ingress.kubernetes.io/router.entrypoints: websecure` 

With these annotations, Traefik will ignore HTTP (non TLS) requests. Traefik will terminate the SSL connections. Depending on protocol (HTTP or HTTPS) used by the backend service, Traefik will send decrypted data to an HTTP pod service or encrypted with SSL using the SSL certificate exposed by the service.

```yml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myingress
  annotations:
    # HTTPS entrypoint enabled
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    # TLS enabled
    traefik.ingress.kubernetes.io/router.tls: true
spec:
  tls:
  - hosts:
    - whoami
    secretName: whoami-tls # SSL certificate store in Kubernetes secret
  rules:
    - host: whoami
      http:
        paths:
          - path: /bar
            pathType: Exact
            backend:
              service:
                name:  whoami
                port:
                  number: 80
          - path: /foo
            pathType: Exact
            backend:
              service:
                name:  whoami
                port:
                  number: 80
```

SSL certificates can be created manually and stored in Kubernetes `Secrets`.

```yml
apiVersion: v1
kind: Secret
metadata:
  name: whoami-tls
data:
  tls.crt: base64 encoded crt
  tls.key: base64 encoded key
type: kubernetes.io/tls
```

This manual step can be avoided using Cert-manager and annotating the Ingress resource: `cert-manager.io/cluster-issuer: <issuer_name>`. See further details in [TLS certification management documentation](/docs/certmanager/).

#### Redirecting HTTP traffic to HTTPS

Middlewares are a means of tweaking the requests before they are sent to the service (or before the answer from the services are sent to the clients)
Traefik's [HTTP redirect scheme Middleware](https://doc.traefik.io/traefik/middlewares/http/redirectscheme/) can be used for redirecting HTTP traffic to HTTPS.

```yml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: redirect
  namespace: traefik
spec:
  redirectScheme:
    scheme: https
    permanent: true
```

This middleware can be inserted into a Ingress resource using HTTP entrypoint

Ingress resource annotation `traefik.ingress.kubernetes.io/router.entrypoints: web` indicates the use of HTTP as entrypoint and `traefik.ingress.kubernetes.io/router.middlewares:<middleware_namespace>-<middleware_name>@kuberentescrd` indicates to use a middleware when routing the requests.


```yml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myingress
  annotations:
    # HTTP entrypoint enabled
    traefik.ingress.kubernetes.io/router.entrypoints: web
    # Use HTTP to HTTPS redirect middleware
    traefik.ingress.kubernetes.io/router.middlewares: traefik-redirect@kubernetescrd
spec:
  rules:
    - host: whoami
      http:
        paths:
          - path: /bar
            pathType: Exact
            backend:
              service:
                name:  whoami
                port:
                  number: 80
          - path: /foo
            pathType: Exact
            backend:
              service:
                name:  whoami
                port:
                  number: 80
```

A global Traefik ingress route can be created for redirecting all incoming HTTP traffic to HTTPS

```yml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: http-to-https-redirect
  namespace: traefik
spec:
  entryPoints:
    - web
  routes:
    - kind: Rule
      match: PathPrefix(`/`)
      priority: 1
      middlewares:
        - name: redirect-to-https
      services:
        - kind: TraefikService
          name: noop@internal
```
This route has priority 1 and it will be executed before any other routing rule.

### Providing HTTP basic authentication

In case that the backend does not provide authentication/autherization functionality (i.e: longhorn ui), Traefik can be configured to provide HTTP authentication mechanism (basic authentication, digest and forward authentication).

Traefik's [Basic Auth Middleware](https://doc.traefik.io/traefik/middlewares/http/basicauth/) can be used for providing basic auth HTTP authentication.

#### Configuring Secret for basic Authentication

Kubernetes Secret resource need to be configured using manifest file like the following:

```yml
# Note: in a kubernetes secret the string (e.g. generated by htpasswd) must be base64-encoded first.
# To create an encoded user:password pair, the following command can be used:
# htpasswd -nb user password | base64
apiVersion: v1
kind: Secret
metadata:
  name: basic-auth-secret
  namespace: traefik
data:
  users: |2
    <base64 encoded username:password pair>
```

`data` field within the Secret resouce contains just a field `users`, which is an array of authorized users. Each user must be declared using the `name:hashed-password` format. Additionally all data included in Secret resource must be base64 encoded.

For more details see [Traefik documentation](https://doc.traefik.io/traefik/middlewares/http/basicauth/).

User:hashed-passwords pairs can be generated with `htpasswd` utility. The command to execute is:

```shell
htpasswd -nb <user> <passwd> | base64
```

The result encoded string is the one that should be included in `users` field.

`htpasswd` utility is part of `apache2-utils` package. In order to execute the command it can be installed with the command: `sudo apt install apache2-utils`

As an alternative, docker image can be used and the command to generate the `user:hashed-password` pairs is:
      
```shell
docker run --rm -it --entrypoint /usr/local/apache2/bin/htpasswd httpd:alpine -nb user password | base64
```
For example user:pass pair (oss/s1cret0) will generate a Secret file:

```yml
apiVersion: v1
kind: Secret
metadata:
  name: basic-auth-secret
  namespace: traefik
data:
  users: |2
    b3NzOiRhcHIxJDNlZTVURy83JFpmY1NRQlV6SFpIMFZTak9NZGJ5UDANCg0K
```
#### Middleware configuration

A Traefik Middleware resource must be configured referencing the Secret resource previously created

```yml
# Basic-auth middleware
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: basic-auth
  namespace: traefik
spec:
  basicAuth:
    secret: basic-auth-secret
    removeHeader: true
```

{{site.data.alerts.note}}

`removeHeader` option to true removes the authorization header before forwarding the request to backend service.

In some cases, like linkerd-viz, where basic auth midleware is used. Integration with Grafana fails if this option is not set to true. Grafana does not try to authenticate the user by other means if basic auth headers are present and returns a 401 unauthorized error. See [issue #122](https://github.com/ricsanfre/pi-cluster/issues/122)

{{site.data.alerts.end}}

#### Configuring Ingress resource

Add middleware annotation to Ingress resource referencing the basic auth middleware.
Annotation `traefik.ingress.kubernetes.io/router.middlewares:<middleware_namespace>-<middleware_name>@kuberentescrd` indicates to use a middleware when routing the requests.

```yml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  namespace: whoami
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: traefik-basic-auth@kubernetescrd
spec:
  rules:
    - host: whoami
      http:
        paths:
          - path: /bar
            pathType: Exact
            backend:
              service:
                name:  whoami
                port:
                  number: 80
          - path: /foo
            pathType: Exact
            backend:
              service:
                name:  whoami
                port:
                  number: 80

```


## Traefik Installation

Installation using `Helm` (Release 3):

- Step 1: Add Traefik's Helm repository:

    ```shell
    helm repo add traefik https://helm.traefik.io/traefik
    ```
- Step2: Fetch the latest charts from the repository:

    ```shell
    helm repo update
    ```
- Step 3: Create namespace

    ```shell
    kubectl create namespace traefik
    ```
- Step 4: Create helm values file `traefik-values.yml`

  ```yml
  # Enabling prometheus metrics and access logs
  # Enable access log
  logs:
    access:
      enabled: true
      format: json
      filePath: /data/access.log
    # This is translated to traefik parameters
    # "--metrics.prometheus=true"
    # "--accesslog"
    # "--accesslog.format=json"
    # "--accesslog.filepath=/data/access.log"
  deployment:
    # Adding access logs sidecar
    additionalContainers:
      - name: stream-accesslog
        image: busybox
        args:
        - /bin/sh
        - -c
        - tail -n+1 -F /data/access.log
        imagePullPolicy: Always
        resources: {}
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
        volumeMounts:
        - mountPath: /data
          name: data
  service:
    annotations:
      io.cilium/lb-ipam-ips: 10.0.0.111

  providers:
    # Enable cross namespace references
    kubernetesCRD:
      enabled: true
      allowCrossNamespace: true
    # Enable published service
    kubernetesIngress:
      publishedService:
        enabled: true

  # Enable prometheus metric service
  # This is translated to traefik parameters
  # --metrics.prometheus=true"
  metrics:
    prometheus:
      service:
        enabled: true
        serviceMonitoring: true
  ```

- Step 5: Install Traefik

    ```shell
    helm -f traefik-values.yml install traefik traefik/traefik --namespace traefik
    ```

- Step 6: Confirm that the deployment succeeded, run:

    ```shell
    kubectl -n traefik get pod
    ```

## Configuration


### Assign a static IP address from LoadBalancer pool to Ingress service

Traefik service of type LoadBalancer created by Helm Chart does not specify any static external IP address. TTo assign a static IP address belonging to LB pool, helm chart parameters shoud be specified:

In case of using Cilium LB-IPAM, the following configuration must be added to Helm Chart `traefik-values.yaml`

```yml
# Set specific LoadBalancer IP address for Ingress service
service:
  annotations:
    io.cilium/lb-ipam-ips: 10.0.0.111
```

In case of using Metal LB, the following configuration must be added to Helm Chart `traefik-values.yaml`

```yml
# Set specific LoadBalancer IP address for Ingress service
service:
  annotations:
    metallb.universe.tf/loadBalancerIPs: 10.0.0.111
```

With this configuration ip 10.0.0.111 is assigned to Traefik proxy and so, for all services exposed by the cluster.


### Enabling cross-namespaces references in IngressRoute resources

As alternative to standard `Ingress` kuberentes resources, Traefik's specific CRD, `IngressRoute` can be used to define access to cluster services. This CRD allows advanced routing configurations not possible to do with `Ingress` available Traefik's annotations.

`IngressRoute` and `Ingress` resources only can reference other Traefik's resources, i.e: `Middleware` located in the same namespace.
To change this, and allow `Ingress/IngressRoute` resources to access other resources defined in other namespaces, [`allowCrossNamespace`](https://doc.traefik.io/traefik/providers/kubernetes-crd/#allowcrossnamespace) Traefik helm chart value must be set to true.


The following values need to be specified within helm chart configuration.

```yml
# Enable cross namespace references
providers:
  kubernetesCRD:
    enabled: true
    allowCrossNamespace: true 
```

### Enabling Published service

Traefik by default, when using an external load balancer (Metal LB) does not update `status.loadbalancer` field in ingress resources. See [Traefik issue #3377](https://github.com/traefik/traefik/issues/3377).

When using Argo-cd, this field is used to obtaing the ingress object health status ingress resource are not getting health status and so application gets stucked.

Traefik need to be confgured [enabling published service](https://doc.traefik.io/traefik/providers/kubernetes-ingress/#publishedservice), and thus Traefik will copy Traefik's service loadbalancer.status (containing the service's external IPs, allocated by Metal-LB) to the ingresses.

See more details in [Argo CD issue #968](https://github.com/argoproj/argo-cd/issues/968)

The following values need to be specified within helm chart configuration.

```yml
providers:
  # Enable published service
  kubernetesIngress:
    publishedService:
      enabled: true
```


### Enabling access to Traefik-Dashboard


To provide HTTPS accesss to Traefik dashboard via HTTPS a `IngressRoute` need to be created linked to Traefik's websecure entrypoint

This IngressRoute resource is automatically created by Helm Chart when providing the proper configuration.

Before installing Traefik's Helm Chart, a secret containing TLS Certificate is required to configure TLS options in the `IngressRoute`.
Cert-Manager can be used to automate its generation:

```yml
# Create certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: traefik-cert
  namespace: traefik
spec:
  secretName: traefik-tls
  issuerRef:
    name: ca-issuer
    kind: ClusterIssuer
  commonName: traefik.homelab.ricsanfre.com
  dnsNames:
  - traefik.homelab.ricsanfre.com
  privateKey:
    algorithm: ECDSA
```

To enable its automatic creation when deploying helm chart, add following lines to `values.yaml`:

```yaml
# Enable dashboard ingress-route
ingressRoute:
  dashboard:
    enabled: true
    entryPoints: ["websecure"]
    matchRule: Host(`traefik.homelab.ricsanfre.com`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))
    tls: 
      secretName: traefik-tls
```

With this configuration Traefik's dashboard is available at  https://traefik.homelab.ricsanfre.com/dashboard/

#### Adding Authentication

In order to activate any kind of authentication Traefik's `Middleware` resources need to be configured as described before
Helm chart support the configuration of middlewares for the Ingress Route created for the dashboard: `ingressRoute.dashboard.middlewares`
Middleware resources cannot be created if Traefik's CRDs are installed before deploying the HelmChart.

As an alternative method to enable UI Dashboard  `IngressRoute` resource for enabling access to the Dashboard can be configured after deploying Helm Chart. 

In this case we need to disable the creation of  dashboard `IngressRoute` when deploying the helm chart.
```yaml
 ingressRoute:
    dashboard:
     enabled: false
```

Method described in [[#Providing HTTP basic authentication]] need to be followed to create corresponding HTTP Basic Authentication `Secret` and `Middleware` objects

```yaml
# IngressRoute https
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: traefik
spec:
  entryPoints:
    - websecure
  routes:
  - kind: Rule
    match: Host(`traefik.homelab.ricsanfre.com`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))
    services:
    - kind: TraefikService
      name: api@internal
    middlewares:
      - name: basic-auth
        namespace: traefik
  tls:
    secretName: traefik-tls
```

## Observability

### Metrics

By default helm installation does not enable Traefik's metrics for Prometheus.

To enable that the following configuration must be provided to Helm chart:

```yml
# Enable prometheus metric service
metrics:
  prometheus:
    service:
      enabled: true
```
This configuration makes traefik pod to open its metric port at TCP port 9100 and creates a service.

#### Kube-Prometheus-Stack Integration

Also `ServiceMonitoring` object, Prometheus Operator's CRD, can be automatically created so `kube-prometheus-stack is able to automatically start collecting metrics from Traefik

```yaml
metrics:
  prometheus:
    serviceMonitor: true
```

#### Grafana dashboard

Traefik dashboard can be donwloaded from [grafana.com](https://grafana.com): [dashboard id: 17346](https://grafana.com/grafana/dashboards/17346-traefik-official-standalone-dashboard/).
This dashboard has as prerequisite to have installed `grafana-piechart-panel` plugin.

The list of plugins to be installed can be specified during grafana helm deployment as values (`plugins` variable), and the dashboard can be automatically added using dashboards providers in the list of automated provisioned dashboards.

```yaml
# Add grafana-piechart-panel to list of plugins
plugins:
  - grafana-piechart-panel


# Configure default Dashboard Provider
# https://grafana.com/docs/grafana/latest/administration/provisioning/#dashboards
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: default
        orgId: 1
        folder: ""
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default-folder

# Add dashboard
# Dashboards
dashboards:
  default:
    traefik:
      # https://grafana.com/grafana/dashboards/17346-traefik-official-standalone-dashboard/
      gnetId: 17346
      revision: 9
      datasource:
        - { name: DS_PROMETHEUS, value: Prometheus }

``` 

### Logs

#### Enabling Access log

Traefik access logs contains detailed information about every request it handles. By default, these logs are not enabled. When they are enabled (throug parameter `--accesslog`), Traefik writes the logs to `stdout` by default, mixing the access logs with Traefik-generated application logs.

To avoid this, the access log default configuration must be changed to write logs to a specific file `/data/access.log` (`--accesslog.filepath`), adding to traekik deployment a sidecar container to tail on the access.log file. This container will print access.log to `stdout` but not missing it with the rest of logs.

Default access format need to be changed as well to use JSON format (`--accesslog.format=json`). That way those logs can be further parsed by Fluentbit and log JSON payload automatically decoded extracting all fields from the log. See Fluentbit's Kubernetes Filter `MergeLog` configuration option in the [documentation](https://docs.fluentbit.io/manual/pipeline/filters/kubernetes).

Following Traefik helm chart values need to be provided:

```yml
# Enable access log
logs:
  access:
    enabled: true
    format: json
    filePath: /data/access.log
  # This is translated to traefik parameters
  # "--metrics.prometheus=true"
  # "--accesslog"
  # "--accesslog.format=json"
  # "--accesslog.filepath=/data/access.log"
deployment:
  additionalContainers:
    - name: stream-accesslog
      image: busybox
      args:
      - /bin/sh
      - -c
      - tail -n+1 -F /data/access.log
      imagePullPolicy: Always
      resources: {}
      terminationMessagePath: /dev/termination-log
      terminationMessagePolicy: File
      volumeMounts:
      - mountPath: /data
        name: data
```

This configuration enables Traefik access log writing to `/data/acess.log` file in JSON format. It creates also the sidecar container `stream-access-log` tailing the log file.

### Traces

The ingress is a key component for distributed tracing solution because it is responsible for creating the root span of each trace and for deciding if that trace should be sampled or not.

Distributed tracing systems all rely on propagate the trace context through the chain of involved services. This trace context is encoding in HTTP request headers. There is two key protocols used to propagate tracing context: W3C, used by OpenTelemetry, and B3, used by OpenTracing.

Traefik 2.0 used OpenTracing to export traces to different backends. Since release 3.0, Traefik supports OpenTelemetry. See [Traefik 3.0 announcement](https://traefik.io/blog/announcing-traefik-proxy-v3-rc/)

Procedure described below, to configure OpenTracing is not valid anymore.


~~To activate tracing using B3 propagation protocol, the following options need to be provided~~
  
```
--tracing.zipkin=true
--tracing.zipkin.httpEndpoint=http://tempo-distributor.tracing.svc.cluster.local:9411/api/v2/spans
--tracing.zipkin.sameSpan=true
--tracing.zipkin.id128Bit=true
--tracing.zipkin.sampleRate=1
```

~~For more details see [Traefik tracing documentation](https://doc.traefik.io/traefik/observability/tracing/overview/)~~

~~In order to be able to correlate logs with traces in Grafana, Traefik access log should be configured so, trace ID is also present as a field in the logs. Trace ID comes as a header field (`X-B3-Traceid`), that need to be included in the logs.~~

~~By default no header is included in Traefik's access log. Additional parameters need to be added to include the traceID.~~

```
--accesslog.fields.headers.defaultmode=drop
--accesslog.fields.headers.names.X-B3-Traceid=keep
```

~~See more details in [Traefik access log documentation](https://doc.traefik.io/traefik/observability/access-logs/#limiting-the-fieldsincluding-headers).~~

~~When installing Traefik with Helm the following values.yml file achieve the above configuration~~

```yml
# Enable access log
logs:
  access:
    enabled: true
    format: json
    fields:
      general:
        defaultmode: keep
      headers:
        defaultmode: drop
        names:
          X-B3-Traceid: keep
# Enabling tracing
tracing:
  zipkin:
    httpEndpoint: http://tempo-distributor.tracing.svc.cluster.local:9411/api/v2/spans
    sameSpan: true
    id128Bit: true
    sampleRate: 1.0
``` 

~~In Traefik's access logs, a new field appear `request_X-B3-Traceid` containing trace id that can be used to extract Tempo traces information.~~

#### ~~Loki and Tempo integration~~

~~Grafana's  Loki data source can be configured to detect `traceID` automatically and providing a link in grafana to automatically opening the corresponding trace information from [[Grafana Tempo]].~~

~~See [Loki data source - derived Fields](https://grafana.com/docs/grafana/latest/datasources/loki/#derived-fields).~~

~~This can be done automatically when installing Grafana providing the following helm chart configuration:~~

```yml
additionalDataSources:
  - name: Loki
    type: loki
    uid: loki
    access: proxy
    url: http://loki-gateway.logging.svc.cluster.local
    jsonData:
      derivedFields:
        # Traefik traces integration
        - datasourceUid: tempo
          matcherRegex: '"request_X-B3-Traceid":"(\w+)"'
          name: TraceID
          url: $${__value.raw}

  - name: Tempo
    uid: tempo
    type: tempo
    access: proxy
    url: http://tempo-query-frontend.tracing.svc.cluster.local:3100
```

~~A derived field `TraceID` is added to logs whose message contains field `request_X-B3-Traceid` which is added by Traefik to access logs.~~