---
title: Ingress Controller (Traefik)
permalink: /docs/traefik/
description: How to configure Ingress Contoller based on Traefik in our Raspberry Pi Kuberentes cluster.
last_modified_at: "08-09-2022"
---

All HTTP/HTTPS traffic comming to K3S exposed services should be handled by a Ingress Controller.
K3S default installation comes with Traefik HTTP reverse proxy which is a Kuberentes compliant Ingress Controller.

Traefik is a modern HTTP reverse proxy and load balancer made to deploy microservices with ease. It simplifies networking complexity while designing, deploying, and running applications.

## Enabling HTTPS and TLS 

All externally exposed frontends deployed on the Kubernetes cluster should be SSL encrypted and access through HTTPS. If possible those certificates should be valid public certificates.

### Enabling TLS in Ingress resources

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

This manual step can be avoided using Cert-manager and annotating the Ingress resource: `cert-manager.io/cluster-issuer: <issuer_name>`. See further details in [SSL certification management documentation](/docs/certmanager/).



### Redirecting HTTP traffic to HTTPS

Middlewares are a means of tweaking the requests before they are sent to the service (or before the answer from the services are sent to the clients)
Traefik's [HTTP redirect scheme Middleware](https://doc.traefik.io/traefik/middlewares/http/redirectscheme/) can be used for redirecting HTTP traffic to HTTPS.

```yml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: redirect
  namespace: traefik-system
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
    traefik.ingress.kubernetes.io/router.middlewares: traefik-system-redirect@kubernetescrd
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

## Providing HTTP basic authentication

In case that the backend does not provide authentication/autherization functionality (i.e: longhorn ui), Traefik can be configured to provide HTTP authentication mechanism (basic authentication, digest and forward authentication).

Traefik's [Basic Auth Middleware](https://doc.traefik.io/traefik/middlewares/http/basicauth/) can be used for providing basic auth HTTP authentication.

### Configuring Secret for basic Authentication

Kubernetes Secret resource need to be configured using manifest file like the following:

```yml
# Note: in a kubernetes secret the string (e.g. generated by htpasswd) must be base64-encoded first.
# To create an encoded user:password pair, the following command can be used:
# htpasswd -nb user password | base64
apiVersion: v1
kind: Secret
metadata:
  name: basic-auth-secret
  namespace: traefik-system
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
  namespace: traefik-system
data:
  users: |2
    b3NzOiRhcHIxJDNlZTVURy83JFpmY1NRQlV6SFpIMFZTak9NZGJ5UDANCg0K
```
### Middleware configuration

A Traefik Middleware resource must be configured referencing the Secret resource previously created

```yml
# Basic-auth middleware
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: basic-auth
  namespace: traefik-system
spec:
  basicAuth:
    secret: basic-auth-secret
```

### Configuring Ingress resource

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
    traefik.ingress.kubernetes.io/router.middlewares: traefik-system-basic-auth@kubernetescrd
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

## Monitoring Traefik

Follow this procedure to enable Traefik dashboard and metrics monitoring with Prometheus.

### Enabling Prometheus metrics

By default Traefik deployed by K3S does not enable Traefik metrics for Prometheus. The Helm chart used to deploy Traefik must be configured providing the following values file:

```yml
additionalArguments:
  - "--metrics.prometheus=true"
```
This configuration makes the traefik pod to open its metric port at TCP port 9100

{{site.data.alerts.important}}
Since Traefik helm deployment is managed directly by K3S, a specific K3S procedure need to be followed to change the configuration of the Helm chart. See section [below](#traefik-helmchart-configuration).
{{site.data.alerts.end}}

### Creating Traefik-metric Service

A Kuberentes Service must be created for enabling the access to Prometheus metrics

- Create Manfifest file for the dashboard service
  
  ```yml
  apiVersion: v1
  kind: Service
  metadata:
    name: traefik-metrics
    namespace: kube-system
    labels:
      app.kubernetes.io/instance: traefik
      app.kubernetes.io/name: traefik
      app.kubernetes.io/component: traefik-metrics
  spec:
    type: ClusterIP
    ports:
      - name: metrics
        port: 9100
        targetPort: metrics
        protocol: TCP
    selector:
      app.kubernetes.io/instance: traefik
      app.kubernetes.io/name: traefik
  ```
- Apply manifest files

- Check metrics end-point is available

  ```shell
  curl http://<traefik-dashboard-service>:9100/metrics
  ```

### Creating Traefik-Dashboard Service

A Kuberentes Service must be created for enabling the access to UI Dashboard

- Create Manfifest file for the dashboard service
  
  ```yml
  ---
  apiVersion: v1
  kind: Service
  metadata:
    name: traefik-dashboard
    namespace: kube-system
    labels:
      app.kubernetes.io/instance: traefik
      app.kubernetes.io/name: traefik
      app.kubernetes.io/component: traefik-dashboard
  spec:
    type: ClusterIP
    ports:
      - name: traefik
        port: 9000
        targetPort: traefik
        protocol: TCP
    selector:
      app.kubernetes.io/instance: traefik
      app.kubernetes.io/name: traefik
  ```

- Create Ingress rules for accesing through HTTPS dashboard UI, using certificates automatically created by certmanager and providing a basic authentication mechanism.
  
  ```yml
  ---
  # HTTPS Ingress
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: traefik-ingress
    namespace: kube-system
    annotations:
      # HTTPS as entry point
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      # Enable TLS
      traefik.ingress.kubernetes.io/router.tls: "true"
      # Use Basic Auth Midleware configured
      traefik.ingress.kubernetes.io/router.middlewares: traefik-system-basic-auth@kubernetescrd
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      cert-manager.io/cluster-issuer: ca-issuer
      cert-manager.io/common-name: traefik.picluster.ricsanfre.com
  spec:
    tls:
      - hosts:
          - traefik.picluster.ricsanfre.com
        secretName: traefik-tls
    rules:
      - host: traefik.picluster.ricsanfre.com
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: traefik-dashboard
                  port:
                    number: 9000
  ---
  # http ingress for http->https redirection
  kind: Ingress
  apiVersion: networking.k8s.io/v1
  metadata:
    name: traefik-redirect
    namespace: kube-system
    annotations:
      # Use redirect Midleware configured
      traefik.ingress.kubernetes.io/router.middlewares: traefik-system-redirect@kubernetescrd
      # HTTP as entrypoint
      traefik.ingress.kubernetes.io/router.entrypoints: web
  spec:
    rules:
      - host: traefik.picluster.ricsanfre.com
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: traefik-dashboard
                  port:
                    number: 9000
  ```
- Apply manifests files

- Acces UI through configured dns: `https://traefik.picluster.ricsanfre.com/dashboard/`

## Assign a static IP address from LoadBalancer pool to Ingress service

Traefik service of type LoadBalancer created by Helm Chart does not specify any static external IP address. To assign a static IP address belonging to Metal LB pool, heml chart parameters shoud be specified:

```yml
service:
  spec:
    loadBalancerIP: 10.0.0.100
```

{{site.data.alerts.important}}
Since Traefik helm deployment is managed directly by K3S, a specific K3S procedure need to be followed to change the configuration of the Helm chart. See section [below](#traefik-helmchart-configuration).
{{site.data.alerts.end}}

## Enabling Access log

Traefik access logs contains detailed information about every request it handles. By default, these logs are not enabled. When they are enabled (throug parameter `--accesslog`), Traefik writes the logs to `stdout` by default, mixing the access logs with Traefik-generated application logs.

To avoid this, the access log default configuration must be changed to write logs to a specific file `/data/access.log` (`--accesslog.filepath`), adding to traekik deployment a sidecar container to tail on the access.log file. This container will print access.log to `stdout` but not missing it with the rest of logs.

Default access format need to be changed as well to use JSON format (`--accesslog.format=json`). That way those logs will be parsed by Fluentbit and log JSON payload automatically decoded extracting all fields from the log. See Fluentbit's Kubernetes Filter `MergeLog` configuration option in the [documentation](https://docs.fluentbit.io/manual/pipeline/filters/kubernetes).

Following Traefik helm chart values need to be provided:

```yml
additionalArguments:
  - "--accesslog"
  - "--accesslog.format=json"
  - "--accesslog.filepath=/data/access.log"
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

{{site.data.alerts.important}}
Since Traefik helm deployment is managed directly by K3S, a specific K3S procedure need to be followed to change the configuration of the Helm chart. See section [below](#traefik-helmchart-configuration).
{{site.data.alerts.end}}


## Enabling cross-namespaces references in IngressRoute resources

As alternative to standard `Ingress` kuberentes resources, Traefik's specific CRD, `IngressRoute` can be used. This CRD allows advanced routing configurations not possible to do with `Ingress` available Traefik's annotations.

`IngressRoute` resources only can reference other Traefik's resources, i.e: `Middleware` located in the same namespace.
To change this, and allow IngresRoute access resources defined in other namespaces, [`allowCrossNamespace`](https://doc.traefik.io/traefik/providers/kubernetes-crd/#allowcrossnamespace) Traefik helm chart value must be set to true.


{{site.data.alerts.important}}
Since Traefik helm deployment is managed directly by K3S, a specific K3S procedure need to be followed to change the configuration of the Helm chart. See section [below](#traefik-helmchart-configuration).
{{site.data.alerts.end}}

## Traefik HelmChart Configuration

Traefik is a K3S embedded components that is auto-deployed using Helm. In order to configure Helm chart configuration parameters the official [document](https://rancher.com/docs/k3s/latest/en/helm/#customizing-packaged-components-with-helmchartconfig) must be followed.

- Create a file `traefik-config.yml` of the customized resource `HelmChartConfig` 
   
  ```yml
  ---
  apiVersion: helm.cattle.io/v1
  kind: HelmChartConfig
  metadata:
    name: traefik
    namespace: kube-system
  spec:
    valuesContent: |-
      additionalArguments:
        - "--metrics.prometheus=true"
        - "--accesslog"
        - "--accesslog.format=json"
        - "--accesslog.filepath=/data/access.log"
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
      service:
        spec:
          loadBalancerIP: 10.0.0.100
      # Enable cross namespace references
      providers:
        kubernetesCRD:
          enabled: true
          allowCrossNamespace: true
  ```
   
- Copy file `traefik-config.yml` file to `/var/lib/rancher/k3s/server/manifests/` in the master node.

  K3S automatically will re-deploy Traefik chart with the configuration changes.

## Automating with Ansible

Ansible role **traefik** creates the redirect and basic auth Middleware resources that can be used globally by any Ingress resource. It also enables Prometheus metrics endopoint and Traefik dashboard service access.