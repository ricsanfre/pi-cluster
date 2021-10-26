# Ingress Controller configuration

All HTTP/HTTPS traffic comming to K3S exposed services should be handled by a Ingress Controller.
K3S default installation comes with Traefik HTTP reverse proxy which is a Kuberentes compliant Ingress Controller.

Traefik is a modern HTTP reverse proxy and load balancer made to deploy microservices with ease. It simplifies networking complexity while designing, deploying, and running applications.

# Enabling HTTPS and TLS 

All externally exposed frontends deployed on the Kubernetes cluster should be SSL encrypted and access through HTTPS. If possible those certificates should be valid public certificates.

### Enabling TLS in Ingress resources

As stated in Kuberentes (documentation)(https://kubernetes.io/docs/concepts/services-networking/ingress/#tls) Ingress access can be secured using TLS by specifying a Secret that contains a TLS private key and certificate. The Ingress resource only supports a single TLS port, 443, and assumes TLS termination at the ingress point (traffic to the Service and its Pods is in plaintext).

Traefik (documentation)[documentation](https://doc.traefik.io/traefik/routing/providers/kubernetes-ingress/), defines several Ingress resource annotations that can be used to tune the behavioir of Traefik when implementing a Ingress rule.

Traefik can be used to terminate SSL connections, serving internal not secure services by using the following annotations:
- `traefik.ingress.kubernetes.io/router.tls: "true"` makes Traefik to end TLS connections
- `traefik.ingress.kubernetes.io/router.entrypoints: websecure` 
With this annotations Traefik will ignore HTTP (non TLS) requests. Traefik will terminate the SSL connections. Depending on protocol (HTTP or HTTPS) used by the backend service, Traefik will send decrypted data to an HTTP pod service or encrypted with SSL using the SSL certificate exposed by the service.

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

SSL certificates can be created manually and stored in Kubernetes `Secrets`. This manual step can be avoided using Cert-manager.

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

Ingress resource annotation `traefik.ingress.kubernetes.io/router.entrypoints: web` indicates the use of HTTP as entrypoint and `traefik.ingress.kubernetes.io/router.middlewares:<namespace>-<middleware_name>@kuberentescrd` indicates to use a middleware when routing the requests.


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

