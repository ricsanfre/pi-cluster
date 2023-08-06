---
title: Monitoring (Prometheus)
permalink: /docs/prometheus/
description: How to deploy kuberentes cluster monitoring solution based on Prometheus. Installation based on Prometheus Operator using kube-prometheus-stack project.
last_modified_at: "29-07-2023"
---

Prometheus stack installation for kubernetes using Prometheus Operator can be streamlined using [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus) project maintaned by the community.

That project collects Kubernetes manifests, Grafana dashboards, and Prometheus rules combined with documentation and scripts to provide easy to operate end-to-end Kubernetes cluster monitoring with Prometheus using the Prometheus Operator.

Components included in kube-stack package are:

- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
- Highly available [Prometheus](https://prometheus.io/)
- Highly available [Alertmanager](https://github.com/prometheus/alertmanager)
- [prometheus-node-exporter](https://github.com/prometheus/node_exporter) to collect metrics from each cluster node
- [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics) to collect metrics about the state of kubernetes' objects.
- [Grafana](https://grafana.com/)

This stack is meant for cluster monitoring, so it is pre-configured to collect metrics from all Kubernetes components.

The architecture of components deployed is showed in the following image.

![kube-prometheus-stack](/assets/img/prometheus-stack-architecture.png)

## About Prometheus Operator

Prometheus operator manages Prometheus and AlertManager deployments and their configuration through the use of Kubernetes CRD (Custom Resource Definitions):

- `Prometheus` and `AlertManager` CRDs: declaratively defines a desired Prometheus/AlertManager setup to run in a Kubernetes cluster. It provides options to configure the number of replicas and persistent storage.
- `ServiceMonitor`/`PodMonitor`/`Probe` CRDs: manages Prometheus service discovery configuration, defining how a dynamic set of services/pods/static-targets should be monitored.
- `PrometheusRules` CRD: defines Prometheus' alerting and recording rules. Alerting rules, to define alert conditions to be notified (via AlertManager), and recording rules, allowing Prometheus to precompute frequently needed or computationally expensive expressions and save their result as a new set of time series.
- `AlertManagerConfig` CRD defines Alertmanager configuration, allowing routing of alerts to custom receivers, and setting inhibition rules. 

{{site.data.alerts.note}}

More details about Prometheus Operator CRDs can be found in [Prometheus Operator Design Documentation](https://prometheus-operator.dev/docs/operator/design/).

Spec of the different CRDs can be found in [Prometheus Operator API reference guide](https://prometheus-operator.dev/docs/operator/api/)

{{site.data.alerts.end}}

## Kube-Prometheus Stack installation

### Helm chart installation

Kube-prometheus stack can be installed using helm [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) maintaind by the community

- Step 1: Add the Prometheus repository

  ```shell
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  ```
- Step2: Fetch the latest charts from the repository

  ```shell
  helm repo update
  ```
- Step 3: Create namespace

  ```shell
  kubectl create namespace monitoring
  ```
- Step 3: Create values.yml 

  ```yml
  prometheusOperator:
    # Relabeling job name for operator metrics
    serviceMonitor:
      relabelings:
      # Replace job value
      - sourceLabels:
        - __address__
        action: replace
        targetLabel: job
        replacement: prometheus-operator
    # Disable creation of kubelet service
    kubeletService:
      enabled: false
  alertmanager:
    alertmanagerSpec:
      # Subpath /alertmanager configuration
      externalUrl: http://monitor.picluster.ricsanfre.com/alertmanager/
      routePrefix: /
      # PVC configuration
      storage:
        volumeClaimTemplate:
          spec:
            storageClassName: longhorn
            accessModes: ["ReadWriteOnce"]
            resources:
              requests:
                storage: 50Gi
    # ServiceMonitor job relabel
    serviceMonitor:
      relabelings:
        # Replace job value
        - sourceLabels:
          - __address__
          action: replace
          targetLabel: job
          replacement: alertmanager
  prometheus:
    prometheusSpec:
      # Subpath /prometheus configuration
      externalUrl: http://monitoring.picluster.ricsanfre.com/prometheus/
      routePrefix: /
      # Resources request and limits
      resources:
        requests:
          memory: 1Gi
        limits:
          memory: 1Gi
      # PVC configuration
      storageSpec:
        volumeClaimTemplate:
          spec:
            storageClassName: longhorn
            accessModes: ["ReadWriteOnce"]
            resources:
              requests:
                storage: 50Gi
      # Retention period
      retention: 7d

      # Removing default filter Prometheus selectors
      # Default selector filters
      # matchLabels:
      #   release: <helm-release-name>
      # ServiceMonitor, PodMonitor, Probe and Rules need to have label 'release' equals to kube-prom helm release

      ruleSelectorNilUsesHelmValues: false
      serviceMonitorSelectorNilUsesHelmValues: false
      podMonitorSelectorNilUsesHelmValues: false
      probeSelectorNilUsesHelmValues: false

    # ServiceMonitor job relabel
    serviceMonitor:
      relabelings:
        # Replace job value
        - sourceLabels:
          - __address__
          action: replace
          targetLabel: job
          replacement: prometheus
  grafana:
    # Configuring /grafana subpath
    grafana.ini:
      server:
        domain: monitoring.picluster.ricsanfre.com
        root_url: "%(protocol)s://%(domain)s:%(http_port)s/grafana/"
        serve_from_sub_path: true
    # Admin user password
    adminPassword: "admin_password"
    # List of grafana plugins to be installed
    plugins:
      - grafana-piechart-panel
    # ServiceMonitor label and job relabel
    serviceMonitor:
      labels:
        release: kube-prometheus-stack
      relabelings:
        # Replace job value
        - sourceLabels:
          - __address__
          action: replace
          targetLabel: job
          replacement: grafana
    # Additional data source: Loki
    additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki-gateway.logging.svc.cluster.local

    # Additional configuration to grafana dashboards sidecar
    # Search in all namespaces for configMaps containing label `grafana_dashboard`
    sidecar:
      dashboards:
        searchNamespace: ALL

  # Disabling monitoring of K8s services.
  # Monitoring of K3S components will be configured out of kube-prometheus-stack
  kubelet:
    enabled: false
  kubeApiServer:
    enabled: false
  kubeControllerManager:
    enabled: false
  kubeScheduler:
    enabled: false
  kubeProxy:
    enabled: false
  kubeEtcd:
    enabled: false
  # Disable K8S Prometheus Rules
  # Rules for K3S components will be configured out of kube-prometheus-stack
  defaultRules:
    create: true
    rules:
      etcd: false
      k8s: false
      kubeApiserverAvailability: false
      kubeApiserverBurnrate: false
      kubeApiserverHistogram: false
      kubeApiserverSlos: false
      kubeControllerManager: false
      kubelet: false
      kubeProxy: false
      kubernetesApps: false
      kubernetesResources: false
      kubernetesStorage: false
      kubernetesSystem: false
      kubeScheduler: false
  ```

  The above chart values.yml:

  - Configures AlerManager and Prometheus' PODs persistent volumes to use longhorn
  (`alertmanager.alertmanagerSpec.storage.volumeClaimTemplate` and `prometheus.   prometheusSpec.storageSpec.volumeClaimTemplate`)

  - Configure prometheus and alertmanager to run behind a proxy http under subpaths `/prometheus` and `/alertmanager` (`prometheus.prometheusSpec.externalUrl`/`alertmanager.alertManagerSpec.externalUrl`  and `prometheus.prometheusSpec.routePrefix`/`alertmanager.alertManagerSpec.routePrefix`)
  
  - Set memory resource limits for Prometheus POD `prometheus.prometheusSpec.resources`

  - Set retention period for Prometheus data `prometheus.prometheusSpec.retention`

  - Sets Grafana's specific configuration (admin password `grafana.adminPassword` and list of plugins to be installed: `grafana.plugins`).
  
  - Configure Grafana to run behind a proxy http under a subpath `/grafana` (`grafana.grafana.ini.server`).

    {{site.data.alerts.note}}

    Linkerd-viz dashboard integration with Grafana, only works if Grafana runs behind /grafana subpath, so this configuration makes that integration work.

    {{site.data.alerts.end}}

  - Configure Grafana to discover ConfigMaps containing dashobards definitions in all namespaces (`grafana.sidecar.dashboards.searchNamespaces`)

  - Disables monitoring of kubernetes components (apiserver, etcd, kube-scheduler, kube-controller-manager, kube-proxy and kubelet): `kubeApiServer.enabled`, `kubeControllerManager.enabled`, `kubeScheduler.enabled`, `kubeProxy.enabled` , `kubelet.enabled` and `kubeEtcd.enabled`.
    
    Monitoring of K3s components will be configured outside kube-prometheus-stack. See explanation in section [K3S components monitoring](#k3s-components-monitoring) below.


  - Sets specific configuration for the ServiceMonitor objects associated with Prometheus, Prometheus Operator and Grafana monitoring.

    Relabeling the job name (`grafana.serviceMonitor.relabelings`, `prometheus.serviceMonitor.relabelings` and `prometheusOperator.serviceMonitor.relabelings`) and setting the proper label for Grafana's ServiceMonitor (`grafana.serviceMonitor.labels.release`) to match the selector of Prometheus Operator (otherwise Grafana is not monitored).

    Removing default filter for selectors, in PrometheusOperator's Rules, ServiceMonitor, PodMonitor and Probe resources, so they do not need to have specific `release` label to be managed by Prometheus.

    ```yml
    # Default selector filters
    # matchLabels:
    #   release: <helm-release-name>
    # ServiceMonitor, PodMonitor, Probe and Rules need to have label 'release' equals to kube-prom helm release

    ruleSelectorNilUsesHelmValues: false
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    probeSelectorNilUsesHelmValues: false
    ```

- Step 4: Install kube-Prometheus-stack in the monitoring namespace with the overriden values

  ```shell
  helm install -f values.yml kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring
  ```

### Ingress resources configuration

Enable external access to Prometheus, Grafana and AlertManager through Ingress Controller.

Instead of using separate DNS domains to access the three components, Prometheus, Alertmanager and Grafana are configured to run behind NGINX HTTP Proxy using a unique domain,`monitoring.picluster.ricsanfre.com`, with different subpath for each component:

- Grafana: `https://monitoring.picluster.ricsanfre.com/grafana`
- Prometheus: `https://monitoring.picluster.ricsanfre.com/prometheus`
- Alertmanager: `https://monitoring.picluster.ricsanfre.com/alertmanager`

DNS domain `monitoring.picluster.ricsanfre.com` must be mapped, in cluster DNS server configuration, to NGINX Load Balancer service extenal IP.

Prometheus, Grafana and alertmanager backend are not providing secure communications (HTTP traffic) and thus Ingress resource will be configured to enable HTTPS (NGINX TLS end-point) and redirect all HTTP traffic to HTTPS.

Since prometheus and alertmanager frontends does not provide any authentication mechanism, NGINX HTTP basic authentication will be configured.

Ingress [NGINX rewrite rules](https://kubernetes.github.io/ingress-nginx/examples/rewrite/) rules are configured in Ingress resources.


- Step 1. Create Ingress resources manifest file `monitoring_ingress.yml`

  ```yml
  ---
  # Ingress Grafana
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: ingress-grafana
    namespace: monitoring
    annotations:
      # Linkerd configuration. Configure Service as Upstream
      nginx.ingress.kubernetes.io/service-upstream: "true"
      # Rewrite target
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/rewrite-target: /$1
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      cert-manager.io/cluster-issuer: ca-issuer
      cert-manager.io/common-name: monitoring.picluster.ricsanfre.com
  spec:
    ingressClassName: nginx
    tls:
      - hosts:
          - monitoring.picluster.ricsanfre.com
        secretName: monitoring-tls
    rules:
      - host: monitoring.picluster.ricsanfre.com
        http:
          paths:
            - path: /grafana/(.*)
              pathType: Prefix
              backend:
                service:
                  name: kube-prometheus-stack-grafana
                  port:
                    number: 80
  ---
  # Ingress Prometheus
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: ingress-prometheus
    namespace: monitoring
    annotations:
      # Linkerd configuration. Configure Service as Upstream
      nginx.ingress.kubernetes.io/service-upstream: "true"
      # Rewrite target
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/rewrite-target: /$1
      # Enable basic auth
      nginx.ingress.kubernetes.io/auth-type: basic
      # Secret defined in nginx namespace
      nginx.ingress.kubernetes.io/auth-secret: nginx/basic-auth-secret
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      cert-manager.io/cluster-issuer: ca-issuer
      cert-manager.io/common-name: monitoring.picluster.ricsanfre.com
  spec:
    ingressClassName: nginx
    tls:
      - hosts:
          - monitoring.picluster.ricsanfre.com
        secretName: monitoring-tls
    rules:
      - host: monitoring.picluster.ricsanfre.com
        http:
          paths:
            - path: /prometheus/(.*)
              pathType: Prefix
              backend:
                service:
                  name: kube-prometheus-stack-prometheus
                  port:
                    number: 9090
  ---
  # Ingress AlertManager
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: ingress-alertmanager
    namespace: monitoring
    annotations:
      # Linkerd configuration. Configure Service as Upstream
      nginx.ingress.kubernetes.io/service-upstream: "true"
      # Rewrite target
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/rewrite-target: /$1
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      cert-manager.io/cluster-issuer: ca-issuer
      cert-manager.io/common-name: monitoring.picluster.ricsanfre.com
  spec:
    ingressClassName: nginx
    tls:
      - hosts:
          - monitoring.picluster.ricsanfre.com
        secretName: monitoring-tls
    rules:
      - host: monitoring.picluster.ricsanfre.com
        http:
          paths:
            - path: /alertmanager/(.*)
              pathType: Prefix
              backend:
                service:
                  name: kube-prometheus-stack-alertmanager
                  port:
                    number: 9093
  ```

 
- Step 2. Apply the manifest file

  ```shell
  kubectl apply -f monitoring_ingress.yml
  ```

## What has been deployed by kube-stack?

### Prometheus Operator 

The above installation procedure, deploys Prometheus Operator and creates the needed `Prometheus` and `AlertManager` Objects, which make the operator to deploy the corresponding Prometheus and AlertManager PODs (as StatefulSets).

Note that the final specification can be changed in helm chart values (`prometheus.prometheusSpec` and `alertmanager.alertmanagerSpec`)

#### Prometheus Object

This object contain the desirable configuration of the Prometheus Server

```yml
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  annotations:
    meta.helm.sh/release-name: kube-prometheus-stack
    meta.helm.sh/release-namespace: monitoring
  labels:
    app: kube-prometheus-stack-prometheus
    app.kubernetes.io/instance: kube-prometheus-stack
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/part-of: kube-prometheus-stack
    app.kubernetes.io/version: 39.2.1
    chart: kube-prometheus-stack-39.2.1
    heritage: Helm
    release: kube-prometheus-stack
  name: kube-prometheus-stack-prometheus
  namespace: monitoring
spec:
  alerting:
    alertmanagers:
    - apiVersion: v2
      name: kube-prometheus-stack-alertmanager
      namespace: monitoring
      pathPrefix: /
      port: http-web
  enableAdminAPI: false
  evaluationInterval: 30s
  externalUrl: http://kube-prometheus-stack-prometheus.monitoring:9090
  image: quay.io/prometheus/prometheus:v2.37.0
  listenLocal: false
  logFormat: logfmt
  logLevel: info
  paused: false
  podMonitorNamespaceSelector: {}
  podMonitorSelector:
    matchLabels:
      release: kube-prometheus-stack
  portName: http-web
  probeNamespaceSelector: {}
  probeSelector:
    matchLabels:
      release: kube-prometheus-stack
  replicas: 1
  retention: 10d
  routePrefix: /
  ruleNamespaceSelector: {}
  ruleSelector:
    matchLabels:
      release: kube-prometheus-stack
  scrapeInterval: 30s
  securityContext:
    fsGroup: 2000
    runAsGroup: 2000
    runAsNonRoot: true
    runAsUser: 1000
  serviceAccountName: kube-prometheus-stack-prometheus
  serviceMonitorNamespaceSelector: {}
  serviceMonitorSelector:
    matchLabels:
      release: kube-prometheus-stack
  shards: 1
  storage:
    volumeClaimTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
        storageClassName: longhorn
  version: v2.37.0
```

This `Prometheus` object specifies the following Prometheus configuration:

- Prometheus version and image installed (v2.37.0) (`spec.version` and `spec.image`).

- HA Configuration. Number of shards and replicas per shard (`spec.shards` and `spec.replicas`).

  Prometheus basic HA mechanism is implemented through replication. Two (or more) instances (replicas) need to be running with the same configuration except that they will have one external label with a different value to identify them. The Prometheus instances scrape the same targets and evaluate the same rules.
 
  There is additional HA mechanims, Prometheus' sharding, which splits targets to be scraped into shards and each shard is assigned to a Prometheus server instance (or to a set, number of replicas).

  The main drawback of this sharding solution is that, to query all data, query federation (e.g. Thanos Query) and distributed rule evaluation engine (e.g. Thanos Ruler) should be deployed.

  Number of shards matches the number of StatefulSet objects to be deployed and numner of replicas are the number of PODs of each StatefulSet.

  {{site.data.alerts.note}}

  In my cluster, mainly due to lack of resources, HA mechanism is not configured (only one shard and one replica are specified).

  For details about HA configuration check [Prometheus Operator: High Availability](https://prometheus-operator.dev/docs/operator/high-availability/#prometheus)

  {{site.data.alerts.end}}

- AlertManager server connected to this instance of Prometheus for perfoming the alerting (`spec.alerting.alertManager`). The connection parameters specified by default matches the `AlertManager` object created by kube-prometheus-stack

- Default scrape interval, how often Prometheus scrapes targets (`spec.scrapeInterval`: 30sg). It can be overwitten in PodMonitor/ServiceMonitor/Probe particular configuration.

- Rules evaluation period, how often Prometheus evaluates rules (`evaluationInterval: 30s`)

- Data retention policy (`retention`: 10d)

- Persistent volume specification (`storage:
    volumeClaimTemplate:`) used by the Statefulset objects deployed. In my case volume claim from Longhorn.

- Rules for filtering the Objects (`PodMonitor`, `ServiceMonitor`, `Probe` and `PrometheusRule`) that applies to this particular instance of Prometheus services:  `spec.podMonitorSelector`, `spec.serviceMonitorSelector`, `spec.probeSelector`, and `spec.rulesSelector` introduces a filtering rule. By default kube-prometheus-stack defines a default filter rule:
  ```yml
  matchLabels:
    release: `kube-prometheus-stack`
  ```
  
  All PodMonitor/ServiceMonitor/Probe/Prometheus rules  must have a label: `release: kube-prometheus-stack` for being managed

  This default filtes can be removed providing the following values to helm chart:

  ```yml
  prometheusSpec:
    ruleSelectorNilUsesHelmValues: false
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    probeSelectorNilUsesHelmValues: false
  ```


  The following diagram, from official prometheus operator documentation, shows an example of how the filtering rules are applied. A Deployment and Service called my-app is being monitored by Prometheus based on a ServiceMonitor named my-service-monitor: 

  |![prometheus-operator-crds](/assets/img/prometheus-custom-metrics-elements-1024x555.png) |
  |:---:|
  | *[Source](https://prometheus-operator.dev/docs/operator/troubleshooting/#overview-of-servicemonitor-tagging-and-related-elements): Prometheus Operator Documentation* |

#### AlertManager Object

This object contain the desirable configuration of the AlertManager Server

```yml
apiVersion: monitoring.coreos.com/v1
kind: Alertmanager
metadata:
  annotations:
    meta.helm.sh/release-name: kube-prometheus-stack
    meta.helm.sh/release-namespace: monitoring
  labels:
    app: kube-prometheus-stack-alertmanager
    app.kubernetes.io/instance: kube-prometheus-stack
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/part-of: kube-prometheus-stack
    app.kubernetes.io/version: 39.4.0
    chart: kube-prometheus-stack-39.4.0
    heritage: Helm
    release: kube-prometheus-stack
  name: kube-prometheus-stack-alertmanager
  namespace: monitoring
spec:
  alertmanagerConfigNamespaceSelector: {}
  alertmanagerConfigSelector: {}
  externalUrl: http://kube-prometheus-stack-alertmanager.monitoring:9093
  image: quay.io/prometheus/alertmanager:v0.24.0
  listenLocal: false
  logFormat: logfmt
  logLevel: info
  paused: false
  portName: http-web
  replicas: 1
  retention: 120h
  routePrefix: /
  securityContext:
    fsGroup: 2000
    runAsGroup: 2000
    runAsNonRoot: true
    runAsUser: 1000
  serviceAccountName: kube-prometheus-stack-alertmanager
  storage:
    volumeClaimTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
        storageClassName: longhorn
  version: v0.24.0
```

This `AlartManager` object specifies the following Alert Manager configuration:

- A version and image: v0.24.0 (`spec.version` and `spec.image`)

- HA Configuration. Number of replicas (`spec.shards` and `spec.replicas`).

- Data retention policy (`retention`: 120h)

- Persistent volume specification (`storage:
    volumeClaimTemplate:`) used by the Statefulset objects deployed. In my case volume claim from Longhorn.

#### ServiceMonitor Objects

`kube-prometheus-stack` creates several ServiceMonitor objects to start scraping metrics from all the components deployed:

- Node Exporter
- Grafana
- Kube-State-Metrics
- Prometheus
- AlertManager
- Prometheus Operator

and the following Kubernetes services and processes depending on the configuration of the helm chart.

- coreDNS
- Kube Api server
- kubelet
- Kube Controller Manager
- Kubernetes Scheduler
- Kubernetes etc
- Kube Proxy

In the chart configuration, monitoring of kube-controller-manager, kube-scheduler, kube-proxy, kubelet components has been disabled.
Only the monitoring of `coreDNS` component has not been disabled.

See below section, ["K3S components monitoring"](#k3s-components-monitoring), to know why monitoring of kubernetes components has been disabled in kube-prometheus-stack and how to configure manually the monitoring of K3s.

#### PrometheusRule Objects

`kube-prometheus-stack` creates several `PrometheusRule` objects to specify the alerts and the metrics that Prometheus generated based on the scraped metrics (alerting and record rules)

The rules provisioned can be found here: [Prometheus rules created by kube-prometheus-stack chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack/templates/prometheus/rules-1.14).

Since monitoring of K8S components (kube-controller-manager, kube-scheduler, kube-proxy, kubelet) has been disabled in the chart configuration, correponding PrometheusRules objects are not created.

See below section, ["K3S components monitoring"](#k3s-components-monitoring), to know how to configure manually those rules.

### Grafana

[Grafana helm chart](https://github.com/grafana/helm-charts/tree/main/charts/grafana) is deployed as a subchart of the kube-prometheus-stack helm chart.

Kube-prometheus-stack's helm chart `grafana` value is used to pass the configuration to grafana's chart.

The following chart configuration is provided:

- Grafana front-ed configured to run behind HTTP proxy in /grafana subpath (`grafana.ini.server`)
- Admin password is specified (`grafana.adminPassword`)
- Additional plugin(`grafana.plugins`), `grafana-piechart-panel` needed in by Traefik's dashboard is installed.
- Loki data source is added (`grafana.additionalDataSource`)
- Grafana ServiceMonitor label and job label is configured (`serviceMonitor`)
- Grafana sidecar dashboard provisioner, additional configuration (on top of the one added by kube-prometheus-stack, to search in all namespaces (`sidecar.dashboards.searchNamespace`) 

```yml
grafana:
  # Configuring /grafana subpath
  grafana.ini:
    server:
      domain: monitoring.picluster.ricsanfre.com
      root_url: "%(protocol)s://%(domain)s:%(http_port)s/grafana/"
      serve_from_sub_path: true
  # Admin user password
  adminPassword: "admin_password"
  # List of grafana plugins to be installed
  plugins:
    - grafana-piechart-panel
  # ServiceMonitor label and job relabel
  serviceMonitor:
    labels:
      release: kube-prometheus-stack
    relabelings:
      # Replace job value
      - sourceLabels:
        - __address__
        action: replace
        targetLabel: job
        replacement: grafana
  # Additional data source: Loki
  additionalDataSources:
  - name: Loki
    type: loki
    url: http://loki-gateway.logging.svc.cluster.local
  # Additional configuration to grafana dashboards sidecar
  # Search in all namespaces for configMaps containing label `grafana_dashboard`
  sidecar:
    dashboards:
      searchNamespace: ALL
```

#### GitOps installation (ArgoCD)

As an alternative, for GitOps deployments (using ArgoCD), instead of hardcoding Grafana's admin password within Helm chart values, admin credentials can be in stored in an existing Secret.

The following secret need to be created:
```yml
apiVersion: v1
kind: Secret
metadata:
  name: grafana
  namespace: grafana
type: Opaque
data:
  admin-user: < grafana_admin_user | b64encode>
  admin-password: < grafana_admin_password | b64encode>
```
For encoding the admin and passord execute the following commands:
```shell
echo -n "<grafana_admin_user>" | base64
echo -n "<grafana_admin_password>" | base64
```
And the following Helm values has to be provided:

```yml
grafana:
  # Use an existing secret for the admin user.
  adminUser: ""
  adminPassword: ""
  admin:
    existingSecret: grafana
    userKey: admin-user
    passwordKey: admin-password
```

#### Provisioning Dashboards automatically

[Grafana dashboards](https://grafana.com/docs/grafana/latest/dashboards/) can be configured through provider definitions (yaml files) located in a provisioning directory (`/etc/grafana/provisioning/dashboards`). This yaml file contains the directory from where dashboards in json format can be loaded. See Grafana Tutorial: [Provision dashboards and data sources](https://grafana.com/tutorials/provision-dashboards-and-data-sources/)

When Grafana is deployed in Kubernetes using the helm chart, dashboards can be automatically provisioned enabling a sidecar container provisioner.

Grafana helm chart creates the following `/etc/grafana/provisioning/dashboard/provider.yml` file, which makes Grafana load all json dashboards from `/tmp/dashboards`
```yml
apiVersion: 1
providers:
- name: 'sidecarProvider'
  orgId: 1
  folder: ''
  type: file
  disableDeletion: false
  allowUiUpdates: false
  updateIntervalSeconds: 30
  options:
    foldersFromFilesStructure: false
    path: /tmp/dashboards
```

With this sidecar provider enabled, Grafana dashboards can be provisioned automatically creating ConfigMap resources containing the dashboard json definition. A provisioning sidecar container must be enabled in order to look for those ConfigMaps in real time and automatically copy them to the provisioning directory (`/tmp/dashboards`).

Check out ["Grafana chart documentation: Sidecar for Dashboards"](https://github.com/grafana/helm-charts/tree/main/charts/grafana#sidecar-for-dashboards) explaining how to enable/use dashboard provisioning side-car.

`kube-prometheus-stack` configure by default grafana provisioning sidecar to check only for new ConfigMaps containing label `grafana_dashboard`

kube-prometheus-stack default helm chart values is the following

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

For provision automatically a new dashboard, a new `ConfigMap` resource must be created, labeled with `grafana_dashboard: 1` and containing as `data` the json file content.

```yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: sample-grafana-dashboard
  labels:
     grafana_dashboard: "1"
data:
  dashboard.json: |-
  [json_file_content]

```

Additional helm chart configuration is required for enabling the search for ConfigMaps in all namespaces (by default search is limited to grafana's namespace).

```yaml
grafana:
  sidecar:
    dashboards:
      searchNamespace: ALL
```

Following this procedure kube-prometheus-stack helm chart automatically deploy a set of Dashboards for monitoring metrics coming from Kubernetes processes and from Node Exporter. The list of [kube-prometheus-stack grafana dashboards](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack/templates/grafana/dashboards-1.14)

For each dashboard a ConfigMap containing the json definition is created.

For the K8s disabled components kube-prometheus-stack do not deploy the corresponding dashboard, so they need to be added manually. See below section ["K3S components monitoring"](#k3s-components-monitoring) to know how to add manually those dashboards.

You can get all of them running the following command

```shell
kubectl get cm -l "grafana_dashboard=1" -n monitoring
```

{{site.data.alerts.important}}

Most of [Grafana community dashboards available](https://grafana.com/grafana/dashboards/) have been exported from a running Grafana and so they include a input  variable (`DS_PROMETHEUS`) which represent a datasource which is referenced in all dashboard panels (`${DS_PROMETHEUS}`). See details in [Grafana export/import documentation](https://grafana.com/docs/grafana/latest/dashboards/export-import/).

When automatic provisioning those exported dashboards following the procedure described above, an error appear when accessing them in the UI:

```
Datasource named ${DS_PROMETHEUS} was not found
```

There is an open [Grafana´s issue](https://github.com/grafana/grafana/issues/10786), asking for support of dasboard variables in dashboard provisioning.

As a workarround, json files can be modified before inserting them into ConfigMap yaml file, in order to detect DS_PROMETHEUS datasource. See issue [#18](https://github.com/ricsanfre/pi-cluster/issues/18) for more details

Modify each json file, containing `DS_PROMETHEUS` input variable within `__input` json key, adding the following code to `templating.list` key

```json
"templating": {
    "list": [
      {
        "hide": 0,
        "label": "datasource",
        "name": "DS_PROMETHEUS",
        "options": [],
        "query": "prometheus",
        "refresh": 1,
        "regex": "",
        "type": "datasource"
      },
    ...
```
{{site.data.alerts.end}}


#### Provisioning DataSources automatically

[Grafana datasources](https://grafana.com/docs/grafana/latest/datasources/) can be configured through yml files located in a provisioning directory (`/etc/grafana/provisioning/datasources`). See Grafana Tutorial: [Provision dashboards and data sources](https://grafana.com/tutorials/provision-dashboards-and-data-sources/)

When deploying Grafana in Kubernetes, datasources config files can be imported from ConfigMaps. This is implemented by a sidecar container that copies these ConfigMaps to its provisioning directory.

Check out ["Grafana chart documentation: Sidecar for Datasources"](https://github.com/grafana/helm-charts/tree/main/charts/grafana#sidecar-for-datasources) explaining how to enable/use this sidecar container.

`kube-prometheus-stack` enables by default grafana datasource sidecar to check for new ConfigMaps containing label `grafana_datasource`.

```yml
sidecar:
  datasources:
    enabled: true
    defaultDatasourceEnabled: true
    uid: prometheus
    annotations: {}
    createPrometheusReplicasDatasources: false
    label: grafana_datasource
    labelValue: "1"
    exemplarTraceIdDestinations: {}
``` 

This is the ConfigMap, automatically created by `kube-prometheus-stack`, including the datasource definition for connecting Grafana to the Prometheus server: (Datasource name `Prometheus`)

```yml
apiVersion: v1
data:
  datasource.yaml: |-
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      uid: prometheus
      url: http://kube-prometheus-stack-prometheus.monitoring:9090/
      access: proxy
      isDefault: true
      jsonData:
        timeInterval: 30s
kind: ConfigMap
metadata:
  annotations:
    meta.helm.sh/release-name: kube-prometheus-stack
    meta.helm.sh/release-namespace: monitoring
  labels:
    app: kube-prometheus-stack-grafana
    app.kubernetes.io/instance: kube-prometheus-stack
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/part-of: kube-prometheus-stack
    app.kubernetes.io/version: 39.4.0
    chart: kube-prometheus-stack-39.4.0
    grafana_datasource: "1"
    heritage: Helm
    release: kube-prometheus-stack
  name: kube-prometheus-stack-grafana-datasource
  namespace: monitoring
```

The ConfigMap includes the `grafana_datasource` label, so it is loaded by the sidecar container into Grafana's provisioning directory.

### Prometheus Node Exporter

[Prometheus Node exportet helm chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-node-exporter) is deployed as a subchart of the kube-prometheus-stack helm chart.This chart deploys Prometheus Node Exporter in all cluster nodes as daemonset

Kube-prometheus-stack's helm chart `prometheus-node-exporter` value is used to pass the configuration to node exporter's chart.

Default [kube-prometheus-stack's values.yml](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml) file contains the following configuration which is not changed in the installation procedure defined above

```yml
prometheus-node-exporter:
  namespaceOverride: ""
  podLabels:
    ## Add the 'node-exporter' label to be used by serviceMonitor to match standard common usage in rules and grafana dashboards
    ##
    jobLabel: node-exporter
  extraArgs:
    - --collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/.+)($|/)
    - --collector.filesystem.fs-types-exclude=^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tracefs)$
  service:
    portName: http-metrics
  prometheus:
    monitor:
      enabled: true

      jobLabel: jobLabel

      ## Scrape interval. If not set, the Prometheus default scrape interval is used.
      ##
      interval: ""

      ## How long until a scrape request times out. If not set, the Prometheus default scape timeout is used.
      ##
      scrapeTimeout: ""

      ## proxyUrl: URL of a proxy that should be used for scraping.
      ##
      proxyUrl: ""

      ## MetricRelabelConfigs to apply to samples after scraping, but before ingestion.
      ## ref: https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#relabelconfig
      ##
      metricRelabelings: []
      # - sourceLabels: [__name__]
      #   separator: ;
      #   regex: ^node_mountstats_nfs_(event|operations|transport)_.+
      #   replacement: $1
      #   action: drop

      ## RelabelConfigs to apply to samples before scraping
      ## ref: https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#relabelconfig
      ##
      relabelings: []
      # - sourceLabels: [__meta_kubernetes_pod_node_name]
      #   separator: ;
      #   regex: ^(.*)$
      #   targetLabel: nodename
      #   replacement: $1
      #   action: replace
  rbac:
    ## If true, create PSPs for node-exporter
    ##
    pspEnabled: false

```

Default configuration just excludes from the monitoring several mount points and file types (`extraArgs`) and it creates the corresponding ServiceMonitor object to start scrapping metrics from this exporter.

Prometheus-node-exporter's metrics are exposed in TCP port 9100 (`/metrics` endpoint) of each  daemonset PODs.

### Kube State Metrics

[Prometheus Kube State Metrics helm chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-state-metrics) is deployed as a subchart of the kube-prometheus-stack helm chart.

This chart deploys [kube-state-metrics agent](https://github.com/kubernetes/kube-state-metrics). kube-state-metrics (KSM) is a simple service that listens to the Kubernetes API server and generates metrics about the state of the objects.

Kube-prometheus-stack's helm chart `kube-state-metrics` value is used to pass the configuration to kube-state-metrics's chart.

Kube-state-metrics' metrics are exposed in TCP port 8080 (`/metrics` endpoint).

## K3S and Cluster Services Monitoring

In this section, it is detailed the procedures to activate Prometheus monitoring for K3S components and the cluster services deployed.

The procedure includes the creation of Kuberentes resources, `Services`/`Endpoints` and `ServiceMonitor`/`PodMonitor`/`Probe`, that need to be created to configure Prometheus' service discovery and monitoring configuration. It also includes the dashboards, in json format, that need to be imported in Grafana to visualize the metrics of each particular service.

{{site.data.alerts.note}}

For provisioning the dashboards specified in the next sections, a correponding ConfigMap should be created, one per dashboard (json file), following the procedure described above.

```yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: sample-grafana-dashboard
  labels:
     grafana_dashboard: "1"
data:
  dashboard.json: |-
  [json_file_content]

```
{{site.data.alerts.end}}

### K3S components monitoring

[Kuberentes Documentation - System Metrics](https://kubernetes.io/docs/concepts/cluster-administration/system-metrics/) details the Kubernetes components exposing metrics in Prometheus format:

- kube-controller-manager (exposing `metrics` endpoint at TCP 10257)
- kube-proxy (exposing `/metrics` endpoint at TCP 10249)
- kube-apiserver (exposing `/metrics` at Kubernetes API port TCP 6443)
- kube-scheduler (exposing `/metrics` endpoint at TCP 10259)
- kubelet (exposing `/metrics`,  `/metrics/cadvisor`, `/metrics/resource` and `/metrics/probes` endpoints at TCP 10250)

{{site.data.alerts.note}}

TCP ports numbers exposed by kube-scheduler and kube-controller-manager have changed from  kubernetes release 1.22 (from 10251/10252 to 10257/10259). 

Additional change is that https authenticated connection is required too. Thus, Kubernetes authorized service account is needed to access the metrics service.

Only kube-proxy endpoint remains open using HTTP, the rest of the ports are now using HTTPS.

{{site.data.alerts.end}}


{{site.data.alerts.important}}

By default, K3S components (Scheduler, Controller Manager and Proxy) do not expose their endpoints to be able to collect metrics. Their `/metrics` endpoints are bind to 127.0.0.1, exposing them only to localhost, not allowing the remote query.

The following K3S intallation arguments need to be provided, to change this behaviour.

```
--kube-controller-manager-arg 'bind-address=0.0.0.0' 
--kube-proxy-arg 'metrics-bind-address=0.0.0.0'
--kube-scheduler-arg 'bind-address=0.0.0.0
```
{{site.data.alerts.end}}


kube-prometheus-stack creates the kubernetes resources needed to scrape the metrics from all K8S components in a standard distribution of Kubernetes, but these objects are not valid for a K3S cluster.

K3S distribution has a special behavior related to metrics exposure. K3s deploys  one process in each cluster node: `k3s-server` running on master nodes or `k3s-agent` running on worker nodes. All kubernetes components running in the node share the same memory, and so K3s is emitting the same metrics in all `/metrics` endpoints available in a node: api-server, kubelet (TCP 10250), kube-proxy (TCP 10249), kube-scheduler (TCP 10251) and kube-controller-manager (TCP 10257). When polling one of the kubernetes components metrics endpoints, the metrics belonging to other kubernetes components are not filtered out.

`node1`, k3s master, running all kubernetes components, is emitting the same metrics in all the ports. `node2-node4`, k3s workers, only running kubelet and kube-proxy components, emit the same metrics in both TCP 10250 and 10249 ports.

Enabling the scraping of all different metrics TCP ports (10249,10250,10251, 10257 and apiserver) causes the ingestion of duplicated metrics. Duplicated metrics in Prometheus need to be avoided so memory and CPU consumption can be reduced.

By the other hand, kubelet additional metrics endpoints (`/metrics/cadvisor`, `/metrics/resource` and `/metrics/probes`) are only available at TCP 10250.

Thus, the solution is to scrape only the metrics endpoints available in kubelet port (TCP 10250): `/metrics`, `/metrics/cadvisor`, `/metrics/resource` and `/metrics/probes`

{{site.data.alerts.note}}

See issue [#67](https://github.com/ricsanfre/pi-cluster/issues/67) for details about the analysis of the duplicates and the proposed solution

{{site.data.alerts.end}}

This is the reason why monitoring of K8s kuberentes components has been disabled in kube-prometheus-stack chart configuration.

```yml
# Disable creation of kubelet service
prometheusOperator:
  kubeletService:
    enabled: false
# Disabling monitoring of K8s services.
# Monitoring of K3S components will be configured out of kube-prometheus-stack
kubelet:
  enabled: false
kubeApiServer:
  enabled: false
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false
kubeEtcd:
  enabled: false
# Disable K8S Prometheus Rules
# Rules for K3S components will be configured out of kube-prometheus-stack
defaultRules:
  create: true
  rules:
    etcd: false
    k8s: false
    kubeApiserverAvailability: false
    kubeApiserverBurnrate: false
    kubeApiserverHistogram: false
    kubeApiserverSlos: false
    kubeControllerManager: false
    kubelet: false
    kubeProxy: true
    kubernetesApps: false
    kubernetesResources: false
    kubernetesStorage: false
    kubernetesSystem: true
    kubeScheduler: false
```

With this configuration, the kubernetes resources (headless `Service`, `ServiceMonitor` and `PrometheusRules`) are not created for activate K8S components monitoring and correponding Grafana's dashboards are not deployed. 

To configure manually all kubernetes resources needed to scrape the available metrics from kubelet metrics endpoints, follow this procedure:

- Create a manifest file `k3s-metrics-service.yml` for creating the Kuberentes service used by Prometheus to scrape all K3S metrics.

  This service must be a [headless service](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services), `spec.clusterIP=None`, allowing Prometheus to discover each of the pods behind the service. Since the metrics are exposed not by a pod but by a k3s process, the service need to be defined [`without selector`](https://kubernetes.io/docs/concepts/services-networking/service/#services-without-selectors) and the `endpoints` must be defined explicitly.

  The service will be use the kubelet endpoint (TCP port 10250) for scraping all K3S metrics available in each node. 
  
  ```yml
  ---
  # Headless service for K3S metrics. No selector
  apiVersion: v1
  kind: Service
  metadata:
    name: k3s-metrics-service
    labels:
      app.kubernetes.io/name: kubelet
    namespace: kube-system
  spec:
    clusterIP: None
    ports:
    - name: https-metrics
      port: 10250
      protocol: TCP
      targetPort: 10250
    type: ClusterIP
  ---
  # Endpoint for the headless service without selector
  apiVersion: v1
  kind: Endpoints
  metadata:
    name: k3s-metrics-service
    namespace: kube-system
  subsets:
  - addresses:
    - ip: 10.0.0.11
    - ip: 10.0.0.12
    - ip: 10.0.0.13
    - ip: 10.0.0.14
    - ip: 10.0.0.15
    ports:
    - name: https-metrics
      port: 10250
      protocol: TCP
  ```

- Create manifest file for defining the service monitor resource for let Prometheus discover these targets

  The Prometheus custom resource definition (CRD), `ServiceMonitoring` will be used to automatically discover K3S metrics endpoint as a Prometheus target.

  A single ServiceMonitor resource to enable the collection of all k8s components metrics from unique port TCP 10250.

  This `ServiceMonitor` includes all Prometheus' relabeling/dropping rules defined by the ServiceMonitor resources that kube-prometheus-stack chart would have created if monitoring of all k8s component were activated.

  ```yml
  apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    labels:
      release: kube-prometheus-stack
    name: k3s-monitoring
    namespace: monitoring
  spec:
    endpoints:
    # /metrics endpoint
    - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
      honorLabels: true
      metricRelabelings:
      # apiserver
      - action: drop
        regex: apiserver_request_duration_seconds_bucket;(0.15|0.2|0.3|0.35|0.4|0.45|0.6|0.7|0.8|0.9|1.25|1.5|1.75|2|3|3.5|4|4.5|6|7|8|9|15|25|40|50)
        sourceLabels:
        - __name__
        - le
      port: https-metrics
      relabelings:
      - action: replace
        sourceLabels:
        - __metrics_path__
        targetLabel: metrics_path
      scheme: https
      tlsConfig:
        caFile: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        insecureSkipVerify: true
    # /metrics/cadvisor
    - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
      honorLabels: true
      metricRelabelings:
      - action: drop
        regex: container_cpu_(cfs_throttled_seconds_total|load_average_10s|system_seconds_total|user_seconds_total)
        sourceLabels:
        - __name__
      - action: drop
        regex: container_fs_(io_current|io_time_seconds_total|io_time_weighted_seconds_total|reads_merged_total|sector_reads_total|sector_writes_total|writes_merged_total)
        sourceLabels:
        - __name__
      - action: drop
        regex: container_memory_(mapped_file|swap)
        sourceLabels:
        - __name__
      - action: drop
        regex: container_(file_descriptors|tasks_state|threads_max)
        sourceLabels:
        - __name__
      - action: drop
        regex: container_spec.*
        sourceLabels:
        - __name__
      path: /metrics/cadvisor
      port: https-metrics
      relabelings:
      - action: replace
        sourceLabels:
        - __metrics_path__
        targetLabel: metrics_path
      scheme: https
      tlsConfig:
        caFile: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        insecureSkipVerify: true
      # /metrics/probes
    - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
      honorLabels: true
      path: /metrics/probes
      port: https-metrics
      relabelings:
      - action: replace
        sourceLabels:
        - __metrics_path__
        targetLabel: metrics_path
      scheme: https
      tlsConfig:
        caFile: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        insecureSkipVerify: true
    jobLabel: app.kubernetes.io/name
    namespaceSelector:
      matchNames:
      - kube-system
    selector:
      matchLabels:
        app.kubernetes.io/name: kubelet
    ```

  {{site.data.alerts.note}}

  This ServiceMonitor configures a single Prometheus' scrapping job (job="kubelet").

  "kubelet" job label is kept so less dahsboards need to be modified. Most of "Computer Resources - X" dashboards are using kubelet metrics and the promQL queries in the dashboard are filter metrics by label job="kubelet".

  {{site.data.alerts.end}}

- kube-prometheus-stack's Prometheus rules associated to K8s components are not intalled when disabling their monitoring. Anyway those rules are not valid for K3S since it contains promQL queries filtering metrics by job labels "apiserver", "kubelet", etc. 

  kube-prometheus-stack creates by default different PrometheusRules resources, but all of them are included in single manifest file in prometheus-operator source repository: [kubernetesControlPlane-prometheusRule.yaml](https://github.com/prometheus-operator/kube-prometheus/blob/main/manifests/kubernetesControlPlane-prometheusRule.yaml)

  Modify the yaml file to replace job labels names:

  - Replace job labels names

    Replace the following strings:

    - `job="apiserver"`
    - `job="kube-proxy"`
    - `job="kube-scheduler"`
    - `job="kube-controller-manager"`

    by:

    `job="kubelet"`

  - Add the following label so it match the PrometheusOperator selector for rules

    ```yml
    apiVersion: monitoring.coreos.com/v1
    kind: PrometheusRule
    metadata:
     labels:
       release: kube-prometheus-stack` 
    ```


- Apply manifest file

  ```shell
  kubectl apply -f k3s-metrics-service.yml k3s-servicemonitor.yml kubernetesControlPlane-prometheusRule.yaml
  ```

- Check targets are automatically discovered in Prometheus UI: 

  `http://prometheus/targets`


#### coreDNS monitoring

Enabled by default in kube-prometheus-stack

```yml
coreDns:
  enabled: true
  service:
    port: 9153
    targetPort: 9153
    ...
```

It creates `kube-prometheus-stack-coredns` service in `kube-system` namespace pointing to coreDNS POD.

```yml
---
apiVersion: v1
kind: Service
metadata:
  annotations:
    meta.helm.sh/release-name: kube-prometheus-stack
    meta.helm.sh/release-namespace: monitoring
  creationTimestamp: "2022-08-18T16:22:12Z"
  labels:
    app: kube-prometheus-stack-coredns
    app.kubernetes.io/instance: kube-prometheus-stack
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/part-of: kube-prometheus-stack
    app.kubernetes.io/version: 39.8.0
    chart: kube-prometheus-stack-39.8.0
    heritage: Helm
    jobLabel: coredns
    release: kube-prometheus-stack
  name: kube-prometheus-stack-coredns
  namespace: kube-system
  resourceVersion: "6653"
  uid: 5c0e9f38-2851-450a-b28f-b4baef76e5bb
spec:
  clusterIP: None
  clusterIPs:
  - None
  internalTrafficPolicy: Cluster
  ipFamilies:
  - IPv4
  ipFamilyPolicy: SingleStack
  ports:
  - name: http-metrics
    port: 9153
    protocol: TCP
    targetPort: 9153
  selector:
    k8s-app: kube-dns
  sessionAffinity: None
  type: ClusterIP
status:
  loadBalancer: {}

```

Creates the ServiceMonitor `kube-prometheus-stack-coredns`

```yml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  annotations:
    meta.helm.sh/release-name: kube-prometheus-stack
    meta.helm.sh/release-namespace: monitoring
  creationTimestamp: "2022-08-18T16:22:15Z"
  generation: 1
  labels:
    app: kube-prometheus-stack-coredns
    app.kubernetes.io/instance: kube-prometheus-stack
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/part-of: kube-prometheus-stack
    app.kubernetes.io/version: 39.8.0
    chart: kube-prometheus-stack-39.8.0
    heritage: Helm
    release: kube-prometheus-stack
  name: kube-prometheus-stack-coredns
  namespace: monitoring
  resourceVersion: "6777"
  uid: 065442b6-6ead-447b-86cd-775a673ad071
spec:
  endpoints:
  - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
    port: http-metrics
  jobLabel: jobLabel
  namespaceSelector:
    matchNames:
    - kube-system
  selector:
    matchLabels:
      app: kube-prometheus-stack-coredns
      release: kube-prometheus-stack

```


#### K3S Grafana dashboards

kube-prometheus-stack should install the Grafana dashboards corresponding to K8S components, but since their monitoring is disabled in the helm chart configuration, they need to be intalled manually.

Kubernetes components dashboards can be donwloaded from [grafana.com](https://grafana.com):

- kubelet dashboard: [ID 16361](https://grafana.com/grafana/dashboards/16361-kubernetes-kubelet/)
- apiserver dashboard [ID 12654](https://grafana.com/grafana/dashboards/12654-kubernetes-api-server)
- etcd dashboard [ID 16359](https://grafana.com/grafana/dashboards/16359-etcd/)
- kube-scheduler [ID 12130](https://grafana.com/grafana/dashboards/12130-kubernetes-scheduler/)
- kube-controller-manager [ID 12122](https://grafana.com/grafana/dashboards/12122-kubernetes-controller-manager)
- kube-proxy [ID 12129](https://grafana.com/grafana/dashboards/12129-kubernetes-proxy)

These Grafana's dashboards need to be modified because promQL queries using job name label (kube-scheduler, kube-proxy, apiserver, etc.) that are not used in our configuration. In our configuration only one scrapping job ("kubelet") is configured to scrape metrics from all K3S components.

The following changes need to be applied to json files:

Replace the following strings:

- `job=\"apiserver\"`
- `job=\"kube-proxy\"`
- `job=\"kube-scheduler\"`
- `job=\"kube-controller-manager\"`

by:

`job=\"kubelet\"`

### Ingress NGINX Monitoring
The Prometheus custom resource definition (CRD), `ServiceMonitoring` will be used to automatically discover Ingress NGINX metrics endpoint as a Prometheus target.

- Create a manifest file `nginx-servicemonitor.yml`

```yml
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    app: nginx
    release: kube-prometheus-stack
  name: nginx
  namespace: monitoring
spec:
  jobLabel: app.kubernetes.io/name
  endpoints:
    - port: metrics
      path: /metrics
  namespaceSelector:
    matchNames:
      - nginx
  selector:
    matchLabels:
      app.kubernetes.io/instance: nginx
      app.kubernetes.io/name: ingress-nginx
      app.kubernetes.io/component: controller
``` 
{{site.data.alerts.important}}

`app.kubernetes.io/name` service label will be used as Prometheus' job label (`jobLabel`.

{{site.data.alerts.end}}

- Apply manifest file
  ```shell
  kubectl apply -f nginx-servicemonitor.yml
  ```

- Check target is automatically discovered in Prometheus UI: `http://prometheus/targets`

#### Ingress NGINX Grafana dashboard

Ingress NGINX grafana dashboard in JSON format can be found here: [Kubernetes Ingress-nginx Github repository: `nginx.json`](https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/grafana/dashboards/nginx.json).


### Traefik Monitoring

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
  namespace: monitoring
spec:
  jobLabel: app.kubernetes.io/name
  endpoints:
    - port: traefik
      path: /metrics
  namespaceSelector:
    matchNames:
      - traefik
  selector:
    matchLabels:
      app.kubernetes.io/instance: traefik
      app.kubernetes.io/name: traefik
      app.kubernetes.io/component: traefik-metrics
``` 
{{site.data.alerts.important}}

`app.kubernetes.io/name` service label will be used as Prometheus' job label (`jobLabel`.

{{site.data.alerts.end}}

- Apply manifest file
  ```shell
  kubectl apply -f traefik-servicemonitor.yml
  ```

- Check target is automatically discovered in Prometheus UI: `http://prometheus/targets`

#### Traefik Grafana dashboard

Traefik dashboard can be donwloaded from [grafana.com](https://grafana.com): [dashboard id: 11462](https://grafana.com/grafana/dashboards/11462). This dashboard has as prerequisite to have installed `grafana-piechart-panel` plugin. The list of plugins to be installed can be specified during kube-prometheus-stack helm deployment as values (`grafana.plugins` variable).


### Longhorn Monitoring

As stated by official [documentation](https://longhorn.io/docs/1.2.2/monitoring/prometheus-and-grafana-setup/), Longhorn Backend service is a service pointing to the set of Longhorn manager pods. Longhorn’s metrics are exposed in Longhorn manager pods at the endpoint `http://LONGHORN_MANAGER_IP:PORT/metrics`

Backend endpoint is already exposing Prometheus metrics.

The Prometheus custom resource definition (CRD), `ServiceMonitoring` will be used to automatically discover Longhorn metrics endpoint as a Prometheus target.

- Create a manifest file `longhorm-servicemonitor.yml`
  
  ```yml
  ---
  apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    labels:
      app: longhorn
      release: kube-prometheus-stack
    name: longhorn-prometheus-servicemonitor
    namespace: monitoring
  spec:
    jobLabel: app.kubernetes.io/name
    selector:
      matchLabels:
        app: longhorn-manager
    namespaceSelector:
      matchNames:
      - longhorn-system
    endpoints:
    - port: manager
  ``` 

{{site.data.alerts.important}}

`app.kubernetes.io/name` service label will be used as Prometheus' job label (`jobLabel`).

{{site.data.alerts.end}}

- Apply manifest file

  ```shell
  kubectl apply -f longhorn-servicemonitor.yml
  ```

- Check target is automatically discovered in Prometheus UI:`http://prometheus/targets`


#### Longhorn Grafana dashboard

Longhorn dashboard sample can be donwloaded from [grafana.com](https://grafana.com): [dashboard id: 13032](https://grafana.com/grafana/dashboards/13032).

### Velero Monitoring

By default velero helm chart is configured to expose Prometheus metrics in port 8085
Backend endpoint is already exposing Prometheus metrics.

It can be confirmed checking velero service

```shell
kubectl get svc velero -n velero -o yaml
```
```yml
apiVersion: v1
kind: Service
metadata:
  annotations:
    meta.helm.sh/release-name: velero
    meta.helm.sh/release-namespace: velero
  creationTimestamp: "2021-12-31T11:36:39Z"
  labels:
    app.kubernetes.io/instance: velero
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/name: velero
    helm.sh/chart: velero-2.27.1
  name: velero
  namespace: velero
  resourceVersion: "9811"
  uid: 3a6707ba-0e0f-49c3-83fe-4f61645f6fd0
spec:
  clusterIP: 10.43.3.141
  clusterIPs:
  - 10.43.3.141
  internalTrafficPolicy: Cluster
  ipFamilies:
  - IPv4
  ipFamilyPolicy: SingleStack
  ports:
  - name: http-monitoring
    port: 8085
    protocol: TCP
    targetPort: http-monitoring
  selector:
    app.kubernetes.io/instance: velero
    app.kubernetes.io/name: velero
    name: velero
  sessionAffinity: None
  type: ClusterIP
```
And executing `curl` command to obtain the velero metrics:

```shell
curl 10.43.3.141:8085/metrics
```

The Prometheus custom resource definition (CRD), `ServiceMonitoring` will be used to automatically discover Velero metrics endpoint as a Prometheus target.

- Create a manifest file `velero-servicemonitor.yml`
  
  ```yml
  ---
  apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    labels:
      app: velero
      release: kube-prometheus-stack
    name: velero-prometheus-servicemonitor
    namespace: monitoring
  spec:
    jobLabel: app.kubernetes.io/name
    endpoints:
      - port: http-monitoring
        path: /metrics
    namespaceSelector:
      matchNames:
        - velero
    selector:
      matchLabels:
        app.kubernetes.io/instance: velero
        app.kubernetes.io/name: velero
  ``` 
{{site.data.alerts.important}}

`app.kubernetes.io/name` service label will be used as Prometheus' job label (`jobLabel`.
{{site.data.alerts.end}}

- Apply manifest file
  ```shell
  kubectl apply -f longhorn-servicemonitor.yml
  ```

- Check target is automatically discovered in Prometheus UI

  http://prometheus.picluster.ricsanfre/targets


#### Velero Grafana dashboard

Velero dashboard sample can be donwloaded from [grafana.com](https://grafana.com): [dashboard id: 11055](https://grafana.com/grafana/dashboards/11055).

### Minio Monitoring

For details see [Minio's documentation: "Collect MinIO Metrics Using Prometheus"](https://docs.min.io/minio/baremetal/monitoring/metrics-alerts/collect-minio-metrics-using-prometheus.html).

{{site.data.alerts.note}}
Minio Console Dashboard integration has not been configured, instead a Grafana dashboard is provided.
{{site.data.alerts.end}}

- Generate bearer token to be able to access to Minio Metrics

  ```shell
  mc admin prometheus generate <alias>
  ```
  
  Output is something like this:
  
  ```
  scrape_configs:
  - job_name: minio-job
  bearer_token: eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJleHAiOjQ3OTQ4Mjg4MTcsImlzcyI6InByb21ldGhldXMiLCJzdWIiOiJtaW5pb2FkbWluIn0.mPFKnj3p-sPflnvdrtrWawSZn3jTQUVw7VGxdBoEseZ3UvuAcbEKcT7tMtfAAqTjZ-dMzQEe1z2iBdbdqufgrA
  metrics_path: /minio/v2/metrics/cluster
  scheme: https
  static_configs:
  - targets: ['127.0.0.1:9091']
  ```

  Where: 
  - `bearer_token` is the token to be used by Prometheus for authentication purposes 
  - `metrics_path` is th path to scrape the metrics on Minio server (TCP port 9091)

- Create a manifest file `minio-metrics-service.yml` for creating the Kuberentes service pointing to a external server used by Prometheus to scrape Minio metrics.

  This service. as it happens with k3s-metrics must be a [headless service](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services) and [without selector](https://kubernetes.io/docs/concepts/services-networking/service/#services-without-selectors) and the endpoints must be defined explicitly

  The service will be use the Minio endpoint (TCP port 9091) for scraping all metrics.
  ```yml
  ---
  # Headless service for Minio metrics. No Selector
  apiVersion: v1
  kind: Service
  metadata:
    name: minio-metrics-service
    labels:
      app.kubernetes.io/name: minio
    namespace: kube-system
  spec:
    clusterIP: None
    ports:
    - name: http-metrics
      port: 9091
      protocol: TCP
      targetPort: 9091
    type: ClusterIP
  ---
  # Endpoint for the headless service without selector
  apiVersion: v1
  kind: Endpoints
  metadata:
    name: minio-metrics-service
    namespace: kube-system
  subsets:
  - addresses:
    - ip: 10.0.0.11
    ports:
    - name: http-metrics
      port: 9091
    protocol: TCP
  ```
- Create manifest file for defining the a Secret containing the Bearer-Token an the service monitor resource for let Prometheus discover this target

  The Prometheus custom resource definition (CRD), `ServiceMonitoring` will be used to automatically discover Minio metrics endpoint as a Prometheus target.
  Bearer-token need to be b64 encoded within the Secret resource
  
  ```yml
  ---
  apiVersion: v1
  kind: Secret
  type: Opaque
  metadata:
    name: minio-monitor-token
    namespace: monitoring
  data:
    token: < minio_bearer_token | b64encode >
  ---
  apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    labels:
      app: minio
      release: kube-prometheus-stack
    name: minio-prometheus-servicemonitor
    namespace: monitoring
  spec:
    jobLabel: app.kubernetes.io/name
    endpoints:
      - port: http-metrics
        path: /minio/v2/metrics/cluster
        scheme: https
        tlsConfig:
          insecureSkipVerify: true 
        bearerTokenSecret:
          name: minio-monitor-token
          key: token
    namespaceSelector:
      matchNames:
      - kube-system
    selector:
      matchLabels:
        app.kubernetes.io/name: minio
  ```
- Apply manifest file
  ```shell
  kubectl apply -f minio-metrics-service.yml minio-servicemonitor.yml
  ```
- Check target is automatically discovered in Prometheus UI: `http://prometheus/targets`

#### Minio Grafana dashboard

Minio dashboard sample can be donwloaded from [grafana.com](https://grafana.com): [dashboard id: 13502](https://grafana.com/grafana/dashboards/13502).


### Elasticsearch Monitoring

[prometheus-elasticsearch-exporter](https://github.com/prometheus-community/elasticsearch_exporter) need to be installed in order to have Elastic search metrics in Prometheus format. See documentation ["Prometheus elasticsearh exporter installation"](/docs/elasticsearch/#prometheus-elasticsearh-exporter-installation).

This exporter exposes `/metrics` endpoint in port 9108.

The Prometheus custom resource definition (CRD), `ServiceMonitoring` will be used to automatically discover Fluentbit metrics endpoint as a Prometheus target.

- Create a manifest file `elasticsearch-servicemonitor.yml`
  
  ```yml
  ---
  apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    labels:
      app: prometheus-elasticsearch-exporter
      release: kube-prometheus-stack
    name: elasticsearch-prometheus-servicemonitor
    namespace: monitoring
  spec:
    endpoints:
      - port: http
        path: /metrics
    namespaceSelector:
      matchNames:
        - logging
    selector:
      matchLabels:
        app: prometheus-elasticsearch-exporter
  ```

#### Elasticsearch Grafana dashboard

Elasticsearh exporter dashboard sample can be donwloaded from [prometheus-elasticsearh-grafana](https://github.com/prometheus-community/elasticsearch_exporter/blob/master/examples/grafana/dashboard.json).

### Fluentbit/Fluentd Monitoring

#### Fluentbit Monitoring

Fluentbit, when enabling its HTTP server, it exposes several endpoints to perform monitoring tasks. See details in [Fluentbit monitoring doc](https://docs.fluentbit.io/manual/administration/monitoring).

One of the endpoints (`/api/v1/metrics/prometheus`) provides Fluentbit metrics in Prometheus format.

The Prometheus custom resource definition (CRD), `ServiceMonitoring` will be used to automatically discover Fluentbit metrics endpoint as a Prometheus target.

- Create a manifest file `fluentbit-servicemonitor.yml`
  
  ```yml
  ---
  apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    labels:
      app: fluent-bit
      release: kube-prometheus-stack
    name: fluentbit-prometheus-servicemonitor
    namespace: monitoring
  spec:
    jobLabel: app.kubernetes.io/name
    endpoints:
      - path: /api/v1/metrics/prometheus
        targetPort: 2020
      - params:
          target:
          - http://127.0.0.1:2020/api/v1/storage
        path: /probe
        targetPort: 7979
    namespaceSelector:
      matchNames:
        - logging
    selector:
      matchLabels:
        app.kubernetes.io/instance: fluent-bit
        app.kubernetes.io/name: fluent-bit
  ```

Service monitoring include two endpoints. Fluentbit metrics endpoint (`/api/v1/metrics/prometheus` port TCP 2020) and json-exporter sidecar endpoint (`/probe` port 7979), passing as target parameter fluentbit storage endpoint (`api/v1/storage`)


#### Fluentd Monitoring

In order to monitor Fluentd with Prometheus, `fluent-plugin-prometheus` plugin need to be installed and configured. The custom docker image [fluentd-aggregator](https://github.com/ricsanfre/fluentd-aggregator), I have developed for this project, has this plugin installed.

fluentd.conf file must include configuration of this plugin. It provides '/metrics' endpoint on port 24231.

```
# Prometheus metric exposed on 0.0.0.0:24231/metrics
<source>
  @type prometheus
  @id in_prometheus
  bind "#{ENV['FLUENTD_PROMETHEUS_BIND'] || '0.0.0.0'}"
  port "#{ENV['FLUENTD_PROMETHEUS_PORT'] || '24231'}"
  metrics_path "#{ENV['FLUENTD_PROMETHEUS_PATH'] || '/metrics'}"
</source>

<source>
  @type prometheus_output_monitor
  @id in_prometheus_output_monitor
</source>
```

Check out further details in [Fluentd Documentation: Monitoring by Prometheus] (https://docs.fluentd.org/monitoring-fluentd/monitoring-prometheus).

The Prometheus custom resource definition (CRD), `ServiceMonitoring` will be used to automatically discover Fluentd metrics endpoint as a Prometheus target.

- Create a manifest file `fluentd-servicemonitor.yml`
  
  ```yml
  ---
  apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    labels:
      app: fluentd
      release: kube-prometheus-stack
    name: fluentd-prometheus-servicemonitor
    namespace: monitoring
  spec:
    jobLabel: app.kubernetes.io/name
    endpoints:
      - port: metrics
        path: /metrics
    namespaceSelector:
      matchNames:
        - logging
    selector:
      matchLabels:
        app.kubernetes.io/instance: fluentd
        app.kubernetes.io/name: fluentd
  ```


#### Fluentbit/Fluentd Grafana dashboard

Fluentbit dashboard sample can be donwloaded from [grafana.com](https://grafana.com): [dashboard id: 7752](https://grafana.com/grafana/dashboards/7752).

This dashboard has been modified to include fluentbit's storage metrics (chunks up and down) and to solve some issues with fluentd metrics.


### External Nodes Monitoring

- Install Node metrics exporter

  Instead of installing Prometheus Node Exporter, fluentbit built-in similar functionallity can be used.

  Fluentbit's [node-exporter-metric](https://docs.fluentbit.io/manual/pipeline/inputs/node-exporter-metrics) and [prometheus-exporter](https://docs.fluentbit.io/manual/pipeline/outputs/prometheus-exporter) plugins can be configured to expose `gateway` metrics that can be scraped by Prometheus.

  Add to node's fluent.conf file the following configuration:

  ```
  [INPUT]
      name node_exporter_metrics
      tag node_metrics
      scrape_interval 30
  ```
  
  It configures node exporter input plugin to get node metrics

  ```
  [OUTPUT]
      name prometheus_exporter
      match node_metrics
      host 0.0.0.0
      port 9100
  ```

  It configures prometheuss output plugin to expose metrics endpoint `/metrics` in port 9100.

- Create a manifest file external-node-metrics-service.yml for creating the Kuberentes service pointing to a external server used by Prometheus to scrape External nodes metrics.

  This service. as it happens with k3s-metrics, and Minio must be a headless service and without selector and the endpoints must be defined explicitly.


  The service will be use the Fluentbit metrics endpoint (TCP port 9100) for scraping all metrics.

  ```yml
  ---
  # Headless service for External Node metrics. No Selector
  apiVersion: v1
  kind: Service
  metadata:
    name: external-node-metrics-service
    labels:
      app: prometheus-node-exporter
      release: kube-prometheus-stack
      jobLabel: node-exporter
    namespace: monitoring
  spec:
    clusterIP: None
    ports:
    - name: http-metrics
      port: 9100
      protocol: TCP
      targetPort: 9100
    type: ClusterIP
  ---
  # Endpoint for the headless service without selector
  apiVersion: v1
  kind: Endpoints
  metadata:
    name: external-node-metrics-servcie
    namespace: monitoring
  subsets:
  - addresses:
    - ip: 10.0.0.1
    ports:
    - name: http-metrics
      port: 9100
      protocol: TCP
  ```
  
  The service has been configured with specific labels so it matches the discovery rules configured in the Node-Exporter ServiceMonitoring Object (part of the kube-prometheus installation) and no new service monitoring need to be configured and the new nodes will appear in the corresponing Grafana dashboards.

  
      app: prometheus-node-exporter
      release: kube-prometheus-stack
      jobLabel: node-exporter


  Prometheus-Node-Exporter Service Monitor is the following:
  ```yml
  apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    annotations:
      meta.helm.sh/release-name: kube-prometheus-stack
      meta.helm.sh/release-namespace: monitoring
    generation: 1
    labels:
      app: prometheus-node-exporter
      app.kubernetes.io/managed-by: Helm
      chart: prometheus-node-exporter-3.3.1
      heritage: Helm
      jobLabel: node-exporter
      release: kube-prometheus-stack
    name: kube-prometheus-stack-prometheus-node-exporter
    namespace: monitoring
    resourceVersion: "6369"
  spec:
    endpoints:
    - port: http-metrics
      scheme: http
    jobLabel: jobLabel
    selector:
      matchLabels:
        app: prometheus-node-exporter
        release: kube-prometheus-stack
  ```
  
  `spec.selector.matchLabels` configuration specifies which labels values must contain the services in order to be discovered by this ServiceMonitor object.
  ```yml
  app: prometheus-node-exporter
  release: kube-prometheus-stack
  ```

  `jobLabel` configuration specifies the name of a service label which contains the job_label assigned to all the metrics. That is why `jobLabel` label is added to the new service with the corresponding value (`node-exporter`). This jobLabel is used in all configured Grafana's dashboards, so it need to be configured to reuse them for the external nodes.
  ```yml
  jobLabel: node-exporter
  ```

- Apply manifest file
  ```shell
  kubectl apply -f exterlnal-node-metrics-service.yml
  ```
- Check target is automatically discovered in Prometheus UI: `http://prometheus/targets`

#### Grafana dashboards

Not need to install additional dashboards. Node-exporter dashboards pre-integrated by kube-stack shows the external nodes metrics.
