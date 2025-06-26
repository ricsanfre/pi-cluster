---
title: Ingress Controller (NGINX)
permalink: /docs/nginx/
description: How to configure Nginx Ingress Controller in our Pi Kubernetes cluster.
last_modified_at: "26-06-2025"
---

All HTTP/HTTPS traffic coming to K3S exposed services should be handled by a Ingress Controller.
K3S default installation comes with Traefik HTTP reverse proxy which is a Kubernetes compliant Ingress Controller.

Instead of using Traefik, [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/) can be deployed. Ingress nginx is an Ingress controller for Kubernetes using [NGINX](https://nginx.org/) as a reverse proxy and load balancer.

{{site.data.alerts.note}}

Traefik K3S add-on is disabled during K3s installation, so NGINX Ingress controller can be installed manually.

{{site.data.alerts.end}}

## Ingress Nginx Installation

Installation using `Helm` (Release 3):

-   Step 1: Add Ingress Nginx's Helm repository:

    ```shell
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    ```
-   Step 2: Fetch the latest charts from the repository:

    ```shell
    helm repo update
    ```
-   Step 3: Create namespace

    ```shell
    kubectl create namespace nginx
    ```
-   Step 4: Create helm values file `nginx-values.yml`

    ```yml
    controller:
      # Enabling Promethues metrics and Service Monitoring
      metrics:
        enabled: true
        serviceMonitor:
          enabled: true
      # Enabling OTEL traces
      opentelemetry:
        enabled: true

      # Allow snpippet anotations
      # From v1.9 default value has chaged to false.
      # allow-snippet-annotations: Enables Ingress to parse and add -snippet annotations/directives created by the user.
      allowSnippetAnnotations: true

      config:
        # Open Telemetry
        enable-opentelemetry: "true"
        otlp-collector-host: tempo-distributor.tempo.svc.cluster.local
        otlp-service-name: nginx-internal
        # Print access log to file instead of stdout
        # Separating acces logs from the rest
        access-log-path: "/data/access.log"
        log-format-escape-json: "true"
        log-format-upstream: '{"source": "nginx", "time": $msec, "resp_body_size": $body_bytes_sent, "request_host": "$http_host", "request_address": "$remote_addr", "request_length": $request_length, "request_method": "$request_method", "uri": "$request_uri", "status": $status,  "user_agent": "$http_user_agent", "resp_time": $request_time, "upstream_addr": "$upstream_addr", "trace_id": "$opentelemetry_trace_id", "span_id": "$opentelemetry_span_id"}'
      # controller extra Volume
      extraVolumeMounts:
        - name: data
          mountPath: /data
      extraVolumes:
        - name: data
          emptyDir: {}
      extraContainers:
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

      # Set specific LoadBalancer IP address for Ingress service
      service:
        annotations:
          io.cilium/lb-ipam-ips: ${NGINX_LOAD_BALANCER_IP}
    ```
    {{site.data.alerts.note}}
    Substitute variables (`${var}`) in the above yaml file before deploying manifest.
    -   Replace `${NGINX_LOAD_BALANCER_IP}` by Load balancer IP. IP belonging to Cilium's Load Balancer address pool range (i.e. 10.0.0.100).
    {{site.data.alerts.end}}

-   Step 5: Install Ingress Nginx

    ```shell
    helm install ingress-nginx ingress-nginx/ingress-nginx -f nginx-values.yml --namespace nginx
    ```

-   Step 6: Confirm that the deployment succeeded, run:

    ```shell
    kubectl -n nginx get pod
    ```

### Helm chart configuration details


#### Enabling Prometheus metrics

By default helm installation does not enable NGINX's metrics for Prometheus.

To enable that the following configuration must be provided to Helm chart:

```yml
controller:
  metrics:
    enabled: true
```
This configuration makes NGINX pod to open its metric port at TCP port 10254


#### Assign a static IP address from LoadBalancer pool to Ingress service

Ingress NGINX service of type LoadBalancer created by Helm Chart does not specify any static external IP address. To assign a static IP address belonging to LB pool, helm chart parameters shoud be specified:

In case of using Cilium LB-IPAM, the following need to be configured

```yml
# Set specific LoadBalancer IP address for Ingress service
controller:
  service:
    annotations:
      io.cilium/lb-ipam-ips: ${NGINX_LOAD_BALANCER_IP}
```

In case of using Metal LB, the following need to be configured:

```yml
# Set specific LoadBalancer IP address for Ingress service
controller:
  service:
    annotations:
      metallb.universe.tf/loadBalancerIPs: ${NGINX_LOAD_BALANCER_IP}
```

With this configuration ip ${NGINX_LOAD_BALANCER_IP} is assigned to NGINX proxy and so, for all services exposed by the cluster.

#### Enabling Ingress snippet annotations

Since nginx-ingress 1.9, by default is not allowed to include in Ingress resources `nginx.ingress.kubernetes.io/configuration-snippet` annotation. It need to be enabled in the helm chart configuration

```yml
controller:
  # Allow snpippet anotations
  # From v1.9 default value has chaged to false.
  # allow-snippet-annotations: Enables Ingress to parse and add -snippet annotations/directives created by the user.
  allowSnippetAnnotations: true

```

## Observability

### Logs

#### Enabling Access log

Access logs are enabled by default for all Ingress resources.

It can be disabled annotating Ingress resource with `nginx.ingress.kubernetes.io/enable-access-log: "false"`.

See [Ingress Nginx Annotations documentation](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/#enable-access-log)

NGINX writes the logs to `stdout` by default, mixing the access logs with NGINX-generated application logs.

To avoid this, the access log default configuration must be changed to write logs to a specific file `/data/access.log` (`controller.config.access-log-path`), adding to nginx deployment a sidecar container to tail on the access.log file. This container will print access.log to `stdout` but not missing it with the rest of logs.

Default access format need to be changed as well to use JSON format (`controlle.config.log-format-escape-json`). That way those logs can be further parsed by Fluentbit and log JSON payload automatically decoded extracting all fields from the log. See Fluentbit's Kubernetes Filter `MergeLog` configuration option in the [documentation](https://docs.fluentbit.io/manual/pipeline/filters/kubernetes).

Following Ingress NGINX helm chart values need to be provided:

```yml
controller:
  
  config:
    # Print access log to file instead of stdout
    # Separating acces logs from the rest
    access-log-path: "/data/access.log"
    log-format-escape-json: "true"
    log-format-upstream: '{"source": "nginx", "time": $msec, "resp_body_size": $body_bytes_sent, "request_host": "$http_host", "request_address": "$remote_addr", "request_length": $request_length, "request_method": "$request_method", "uri": "$request_uri", "status": $status,  "user_agent": "$http_user_agent", "resp_time": $request_time, "upstream_addr": "$upstream_addr"}'
  # controller extra Volume
  extraVolumeMounts:
    - name: data
      mountPath: /data
  extraVolumes:
    - name: data
      emptyDir: {}
  extraContainers:
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

This configuration enables NGINX access log writing to `/data/acess.log` file in JSON format. It creates also the sidecar container `stream-access-log` tailing the log file.

### Metrics

By default helm installation does not enable NGINX's metrics for Prometheus.

The following configuration must be provided to Helm chart:

```yml
controller:
  metrics:
    enabled: true
```
This configuration makes NGINX pod to open its metric port at TCP port 10254


#### Prometheus Integration

Also `ServiceMonitoring`, Prometheus Operator's CRD, resource can be automatically created so Kube-Prometheus-Stack is able to automatically start collecting metrics from NGINX Ingress Controller.

The following configuration must be provided to Helm chart:

```yaml
controller:
  # Enabling Promethues metrics and Service Monitoring
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
```

#### Grafana Dashboard
Ingress NGINX grafana dashboards in JSON format can be found here: [Kubernetes Ingress-nginx Github repository: `grafana`](https://github.com/kubernetes/ingress-nginx/tree/main/deploy/grafana/dashboards).

Dashboard can be automatically added using Grafana's dashboard providers configuration. See further details in ["PiCluster - Observability Visualization (Grafana): Automating installation of community dasbhoards](/docs/grafana/#automating-installation-of-grafana-community-dashboards)

Add following configuration to Grafana's helm chart values file, so a NGINX's dashboard provider can be created and dashboards can be automatically downloaded from GitHub repository

```yaml
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: nginx
        orgId: 1
        folder: Nginx
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/nginx-folder
# Dashboards
dashboards:
  nginx:
    nginx:
      url: https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/grafana/dashboards/nginx.json
      datasource: Prometheus
    nginx-request-handling-performance:
      url: https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/grafana/dashboards/request-handling-performance.json
      datasource: Prometheus
```


### Traces

Ingress Contoller is a key component for a distributed tracing solution because it is responsible for creating the root span of each trace and for deciding if that trace should be sampled or not.

Distributed tracing systems all rely on propagate the trace context through the chain of involved services. This trace contex is encoding in HTTP request headers. There is two key protocols used to propagate tracing context: W3C, used by OpenTelemetry, and B3, used by OpenTracing.

Since release 1.10, Ingress Nginx has deprecated OpenTracing and Zipkin modules, being OpenTelemetry the only supported. See [Ingress Nginx 1.10 release notes](https://github.com/kubernetes/ingress-nginx/releases/tag/controller-v1.10.0)

Ingress Nginx's OpenTelemetry module only supports W3C context propagation. B3 context propagation is not supported. See [nginx ingress open issue #10324](https://github.com/kubernetes/ingress-nginx/issues/10324).


To enable OTel traces the following need to be added:


```yaml
controller:
  # Enabling OTEL traces
  opentelemetry:
   enabled: true
  config:
    # Open Telemetry
    enable-opentelemetry: "true"
    otlp-collector-host: tempo-distributor.tempo.svc.cluster.local
    otlp-service-name: nginx-internal
    # Print access log to file instead of stdout
    # Separating acces logs from the rest
    access-log-path: "/data/access.log"
    log-format-escape-json: "true"
    log-format-upstream: '{"source": "nginx", "time": $msec, "resp_body_size": $body_bytes_sent, "request_host": "$http_host", "request_address": "$remote_addr", "request_length": $request_length, "request_method": "$request_method", "uri": "$request_uri", "status": $status,  "user_agent": "$http_user_agent", "resp_time": $request_time, "upstream_addr": "$upstream_addr", "trace_id": "$opentelemetry_trace_id", "span_id": "$opentelemetry_span_id"}' 
```

OTEL collector need to be specified (`controller.config.otlp-collector-host`) and the access log format (`controller.config.log-format-upstream` can be configured to add W3C context: `$opentelemetry_trace_id` and `$opentelemetry_span_id` appears as field in the logs: `trace_id` and `span_id`

## Ingress Resources Configuration

Standard kuberentes resource, `Ingress` can be used to configure the access to cluster services through HTTP proxy capabilities provide by Ingress NGINX.

Following instructions details how to configure access to cluster service using standard `Ingress` resources where Nginx configuration is specified using annotations.


### Enabling HTTPS and TLS 

All externally exposed frontends deployed on the Kubernetes cluster should be accessed using secure and encrypted communications, using HTTPS protocol and TLS certificates. If possible those TLS certificates should be valid public certificates.


#### Enabling TLS in Ingress resources

As stated in [Kubernetes documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls), Ingress access can be secured using TLS by specifying a `Secret` that contains a TLS private key and certificate. The Ingress resource only supports a single TLS port, 443, and assumes TLS termination at the ingress point (traffic to the Service and its Pods is in plaintext).

See further details in [Nginx documentation](https://kubernetes.github.io/ingress-nginx/user-guide/tls/).

A valid hostname (`hosts`) and its corresponding TLS certificate need to be used:

```yml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myingress
spec:
  ingressClassName: nginx
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

By default the controller redirects HTTP clients to the HTTPS port 443 using a 308 Permanent Redirect response if TLS is enabled for that Ingress. So no need to implement further configuraition if TLS is enabled in Ingress Resource

This default configuration can be disabled globally using `ssl-redirect: "false"` in the NGINX config map, or per-Ingress with the `nginx.ingress.kubernetes.io/ssl-redirect: "false"` annotation in the particular resource.


### Providing HTTP basic authentication

In case that the backend does not provide authentication/autherization functionality (i.e: longhorn ui), Ingress NGINX can be configured to provide HTTP authentication mechanism (basic authentication or external OAuth 2.0 authentication).

See [NGINX documentation-Basic Auth](https://kubernetes.github.io/ingress-nginx/examples/auth/basic/) for details about how to configure basic auth HTTP authentication.

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
  namespace: nginx
data:
  auth: |2
    <base64 encoded username:password pair>
```

`data` field within the Secret resouce contains just a field `auth`, which is an array of authorized users. Each user must be declared using the `name:hashed-password` format. Additionally all data included in Secret resource must be base64 encoded.

For more details see [NGINX documentation-Basic Auth](https://kubernetes.github.io/ingress-nginx/examples/auth/basic/).

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
  name: basic-auth
  namespace: nginx
data:
  auth: |2
    b3NzOiRhcHIxJDNlZTVURy83JFpmY1NRQlV6SFpIMFZTak9NZGJ5UDANCg0K
```


#### Configuring Ingress resource

Following annotations need to be added to Ingress resource:

- `nginx.ingress.kubernetes.io/auth-type: basic` : to set basic authentication
- `nginx.ingress.kubernetes.io/auth-secret: basic-auth` : to specify the secret name
. `nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required - foo'`: to specify context message


```yml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  namespace: whoami
  annotations:
    # type of authentication
    nginx.ingress.kubernetes.io/auth-type: basic
    # name of the secret that contains the user/password definitions
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    # message to display with an appropriate context why the authentication is required
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required - foo'
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - whoami
    secretName: whoami-tls
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
