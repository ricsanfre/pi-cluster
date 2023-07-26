---
title: Ingress Controller (NGINX)
permalink: /docs/nginx/
description: How to configure Nginx Ingress Contoller in our Pi Kuberentes cluster.
last_modified_at: "26-07-2023"
---

All HTTP/HTTPS traffic comming to K3S exposed services should be handled by a Ingress Controller.
K3S default installation comes with Traefik HTTP reverse proxy which is a Kuberentes compliant Ingress Controller.

Instead of using Traefik, [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/) can be deployed. Ingress nginx is an Ingress controller for Kubernetes using (NGINX)[https://nginx.org/] as a reverse proxy and load balancer.

{{site.data.alerts.note}}

Traefik K3S add-on is disabled during K3s installation, so NGINX Ingress controller can be installed manually.

{{site.data.alerts.end}}

## Ingress Nginx Installation

Installation using `Helm` (Release 3):

- Step 1: Add Ingress Nginx's Helm repository:

    ```shell
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    ```
- Step2: Fetch the latest charts from the repository:

    ```shell
    helm repo update
    ```
- Step 3: Create namespace

    ```shell
    kubectl create namespace nginx
    ```
- Step 4: Create helm values file `nginx-values.yml`

  ```yml
  # Set specific LoadBalancer IP address for Ingress service
  service:
    spec:
      loadBalancerIP: 10.0.0.100
  ```

- Step 5: Install Ingress Nginx

    ```shell
    helm install ingress-nginx ingress-nginx/ingress-nginx -f nginx-values.yml --namespace nginx
    ```

- Step 6: Confirm that the deployment succeeded, run:

    ```shell
    kubectl -n nginx get pod
    ```

### Helm chart configuration details


#### Enabling Prometheus metrics

TBD


#### Assign a static IP address from LoadBalancer pool to Ingress service

Ingress NGINX service of type LoadBalancer created by Helm Chart does not specify any static external IP address. To assign a static IP address belonging to Metal LB pool, helm chart parameters shoud be specified:

```yml
service:
  spec:
    loadBalancerIP: 10.0.0.100
```

With this configuration ip 10.0.0.100 is assigned to Traefik proxy and so, for all services exposed by the cluster.

#### Enabling Access log

TBD


## Configuring access to cluster services with Ingress NGINX

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
  namespace: traefik
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

Following annotations need to be added to Ingress resourece:

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
  ingressClass: nginx
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
