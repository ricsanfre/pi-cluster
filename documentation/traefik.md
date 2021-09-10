# Traefik Ingress Controller


## Middleware integration into Kubernetes Ingress Rules

Annotation `traefik.ingress.kubernetes.io/router.middlewares` need to be added referencing the middeware with value
`<middleware-namespace>-<middleware-name>@kubernetescrd`

```yml
---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: stripprefix
  namespace: appspace
spec:
  stripPrefix:
    prefixes:
      - /stripit

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress
  namespace: appspace
  annotations:
    # referencing a middleware from Kubernetes CRD provider: 
    # <middleware-namespace>-<middleware-name>@kubernetescrd
    "traefik.ingress.kubernetes.io/router.middlewares": appspace-stripprefix@kubernetescrd
spec:
  # ... regular ingress definition
```

## Basic Authentication Middleware

Basic HTTP authentication can be used as Traefik Middleware

- Step 1. Install apache2-utils
      sudo apt install apache2-utils

- Step 2. Create a base64 encoded htpasswd
    htpasswd -nb <user> <passwd> | openssl base 4

    htpasswd -nb oss s1cret0 | openssl base 4
    
- Step 3. Create manifest for the Basic-Auth Middleware and Ingress

```yml
---
apiVersion: v1
kind: Secret
metadata:
  name: longhorn-dashboard-auth
  namespace: longhorn-system
data:
  users: |2
    b3NzOiRhcHIxJFJvM0NuTi5OJEZVdW94QVhoWldRN1lwUk1Bc3NyNjAKCg==
---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: longhorn-dashboard-basicauth
  namespace: longhorn-system
spec:
  basicAuth:
    secret: longhorn-dashboard-auth
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: longhorn-ingress
  namespace: longhorn-system
  annotations:
    kubernetes.io/ingress.class: traefik
    traefik.ingress.kubernetes.io/router.middlewares: longhorn-system-longhorn-dashboard-basicauth@kubernetescrd
spec:
  rules:
  - host: storage.picluster.ricsanfre.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: longhorn-frontend
            port:
              number: 80

```

- Step 4. Apply the manifest

    kubectl 