# Centralized Monitoring with Prometheus

Prometheus stack installation for kubernetes using Prometheus Operator can be streamlined using [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus) project maintaned by the community.

This project collects Kubernetes manifests, Grafana dashboards, and Prometheus rules combined with documentation and scripts to provide easy to operate end-to-end Kubernetes cluster monitoring with Prometheus using the Prometheus Operator.

Components included in this package:

- The Prometheus Operator
- Highly available Prometheus
- Highly available Alertmanager
- Prometheus node-exporter
- Prometheus Adapter for Kubernetes Metrics APIs
- kube-state-metrics
- Grafana

This stack is meant for cluster monitoring, so it is pre-configured to collect metrics from all Kubernetes components.

## Kube-Prometheus Stack installation

Kube-prometheus stack can be installed using helm [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) maintaind by the community

- Step 1: Add the Elastic repository:
    ```
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    ```
- Step2: Fetch the latest charts from the repository:
    ```
    helm repo update
    ```
- Step 3: Create namespace
    ```
    kubectl create namespace monitoring
    ```
- Step 3: Create values.yml for configuring VolumeClaimTemplates using longhorn and Grafana's admin password
  ```yml
      alertmanager:
        alertmanagerSpec:
          storage:
            volumeClaimTemplate:
              spec:
                storageClassName: longhorn
                accessModes: ["ReadWriteOnce"]
                resources:
                  requests:
                    storage: 50Gi
      prometheus:
        prometheusSpec:
          storageSpec:
            volumeClaimTemplate:
              spec:
                storageClassName: longhorn
                accessModes: ["ReadWriteOnce"]
                resources:
                  requests:
                    storage: 50Gi
      grafana:
        adminPassword: "admin_password"
   ```yml

- Step 3: Install kube-Prometheus-stack in the monitoring namespace with the overriden values
    ```
    helm install -f values.yml kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring
    ```

## Ingress resources configuration

Enable external access to Prometheus, Grafana and AlertManager through Ingress Controller

Create a Ingress rule to make prometheus stack front-ends available through the Ingress Controller (Traefik) using a specific URLs (`prometheus.picluster.ricsanfre.com` , `grafana.picluster.ricsanfre.com` and `alertmanager.picluster.ricsanfre.com`), mapped by DNS to Traefik Load Balancer service external IP.

prometheus, Grafana and alertmanager backend are not providing secure communications (HTTP traffic) and thus Ingress resource will be configured to enable HTTPS (Traefik TLS end-point) and redirect all HTTP traffic to HTTPS.
Since prometheus frontend does not provide any authentication mechanism, Traefik HTTP basic authentication will be configured. 


- Step 1. Create a manifest file `prometheus_ingress.yml`

Two Ingress resources will be created, one for HTTP and other for HTTPS. Traefik middlewares, HTTPS redirect and basic authentication will be used. 

```yml
---
# HTTPS Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
  namespace: k3s-monitoring
  annotations:
    # HTTPS as entry point
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    # Enable TLS
    traefik.ingress.kubernetes.io/router.tls: "true"
    # Use Basic Auth Midleware configured
    traefik.ingress.kubernetes.io/router.middlewares: traefik-system-basic-auth@kubernetescrd
    # Enable cert-manager to create automatically the SSL certificate and store in Secret
    cert-manager.io/cluster-issuer: self-signed-issuer
    cert-manager.io/common-name: prometheus
spec:
  tls:
  - hosts:
    - prometheus.picluster.ricsanfre.com
    secretName: prometheus-tls
  rules:
  - host: prometheus.picluster.ricsanfre.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-prometheus
            port:
              number: 9090

---
# http ingress for http->https redirection
kind: Ingress
apiVersion: networking.k8s.io/v1
metadata:
  name: prometheus-redirect
  namespace: k3s-monitoring
  annotations:
    # Use redirect Midleware configured
    traefik.ingress.kubernetes.io/router.middlewares: traefik-system-redirect@kubernetescrd
    # HTTP as entrypoint
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  rules:
    - host: prometheus.picluster.ricsanfre.com
      http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: kube-prometheus-stack-prometheus
              port:
                number: 9090
```
- Step 2. Create a manifest file `grafana_ingress.yml`

Two Ingress resources will be created, one for HTTP and other for HTTPS. Traefik middlewares HTTPS redirect will be used

```yml
---
# HTTPS Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: k3s-monitoring
  annotations:
    # HTTPS as entry point
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    # Enable TLS
    traefik.ingress.kubernetes.io/router.tls: "true"
    # Enable cert-manager to create automatically the SSL certificate and store in Secret
    cert-manager.io/cluster-issuer: self-signed-issuer
    cert-manager.io/common-name: grafana
spec:
  tls:
  - hosts:
    - grafana.picluster.ricsanfre.com
    secretName: grafana-tls
  rules:
  - host: grafana.picluster.ricsanfre.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-grafana
            port:
              number: 80

---
# http ingress for http->https redirection
kind: Ingress
apiVersion: networking.k8s.io/v1
metadata:
  name: grafana-redirect
  namespace: k3s-monitoring
  annotations:
    # Use redirect Midleware configured
    traefik.ingress.kubernetes.io/router.middlewares: traefik-system-redirect@kubernetescrd
    # HTTP as entrypoint
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  rules:
    - host: grafana.picluster.ricsanfre.com
      http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: kube-prometheus-stack-grafana
              port:
                number: 80

```
- Step 3. Create a manifest file `alertmanager_ingress.yml`

Two Ingress resources will be created, one for HTTP and other for HTTPS. Traefik middlewares HTTPS redirect will be used

```yml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: alertmanager-ingress
  namespace: k3s-monitoring
  annotations:
    # HTTPS as entry point
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    # Enable TLS
    traefik.ingress.kubernetes.io/router.tls: "true"
    # Use Basic Auth Midleware configured
    traefik.ingress.kubernetes.io/router.middlewares: traefik-system-basic-auth@kubernetescrd
    # Enable cert-manager to create automatically the SSL certificate and store in Secret
    cert-manager.io/cluster-issuer: self-signed-issuer
    cert-manager.io/common-name: alertmanager
spec:
  tls:
  - hosts:
    - alertmanager.picluster.ricsanfre.com
    secretName: prometheus-tls
  rules:
  - host: alertmanager.picluster.ricsanfre.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-alertmanager
            port:
              number: 9093

---
# http ingress for http->https redirection
kind: Ingress
apiVersion: networking.k8s.io/v1
metadata:
  name: alertmanager-redirect
  namespace: k3s-monitoring
  annotations:
    # Use redirect Midleware configured
    traefik.ingress.kubernetes.io/router.middlewares: traefik-system-redirect@kubernetescrd
    # HTTP as entrypoint
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  rules:
    - host: alertmanager.picluster.ricsanfre.com
      http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: kube-prometheus-stack-alertmanager
              port:
                number: 9093

``` 
- Step 4. Apply the manifest file

    kubectl apply -f prometheus_ingress.yml grafana_ingress.yml alertmanager_ingress.yml

## Traefik Monitoring

The Prometheus custom resource definition (CRD), `ServiceMonitoring` will be used to automatically discover Traefik metrics endpoint as a Prometheus target.

- Create a manifest file `traefik-servicemonitor.yml`

```yml
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    app: traefik
    release: kube-prometheus-stack
  name: traefik
  namespace: k3s-monitoring
spec:
  endpoints:
    - port: traefik
      path: /metrics
  namespaceSelector:
    matchNames:
      - kube-system
  selector:
    matchLabels:
      app.kubernetes.io/instance: traefik
      app.kubernetes.io/name: traefik-dashboard

``` 
> NOTE: Important to set `label.release` to the value specified for the helm release during Prometheus operator installation (`kube-prometheus-stack`).

- Apply manifest file

  kubectl apply -f traefik-servicemonitor.yml


- Check target is automatically discovered in Prometheus UI

  http://prometheus.picluster.ricsanfre/targets


## Configuring Dashboards


Custom Grafana dashboards can be added creating CongigMap resources, containing dashboard definition in json format, because kube-prometheus-stack configure by default grafana sidecar to check for new ConfigMaps containing label `grafana_dashboard`

The default chart values are:

```yml

grafana:
  sidecar:
    dashboards:
      SCProvider: true
      annotations: {}
      defaultFolderName: null
      enabled: true
      folder: /tmp/dashboards
      folderAnnotation: null
      label: grafana_dashboard
      labelValue: null
```

Check grafana chart [documentation](https://github.com/grafana/helm-charts/tree/main/charts/grafana#sidecar-for-dashboards) explaining it.

Config Map resouce containing as data the json dashboard definition 

```yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: sample-grafana-dashboard
  labels:
     grafana_dashboard: "1"
data:
  dashboard.json: |-
  [...]

```