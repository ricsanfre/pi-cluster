---
title: Minio S3 Object Storage Service
permalink: /docs/minio/
description: How to deploy a Minio S3 object storage service in our Raspberry Pi Kubernetes Cluster.
last_modified_at: "27-03-2026"
---

Minio will be deployed as a Kubernetes service providing Object Store S3-compatile backend for other Kubernetes Services (Loki, Tempo, Mimir, etc. )

Official [Minio Kubernetes installation documentation](https://min.io/docs/minio/kubernetes/upstream/index.html) uses Minio Operator to deploy and configure a multi-tenant S3 cloud service.

Instead of using Minio Operator, [Vanilla Minio helm chart](https://github.com/minio/minio/tree/master/helm/minio) will be used. Not need to support multi-tenant installations and Vanilla Minio helm chart supports also the automatic creation of buckets, policies and users. Minio Operator does not support automate provisioning of such resources.


## Minio installation


Installation using `Helm` (Release 3):

- Step 1: Add the Minio Helm repository:

  ```shell
  helm repo add minio https://charts.min.io/
  ```
- Step2: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```
- Step 3: Create namespace

  ```shell
  kubectl create namespace minio
  ```

- Step 3: Create Minio secret


  The following secret need to be created, containing Minio's root user and password, and keys from others users that are going to be provisioned automatically when installing the helm chart (loki, tempo):
  ```yml
  apiVersion: v1
  kind: Secret
  metadata:
    name: minio-secret
    namespace: minio
  type: Opaque
  data:
    rootUser: < minio_root_user | b64encode >
    rootPassword: < minio_root_key | b64encode >
    lokiPassword: < minio_loki_key | b64encode >
    tempoPassword: < minio_tempo_key | b64encode >
  ```


- Step 4: Create file `minio-values.yml`

  ```yml
  # Get root user/password from secret
  existingSecret: minio-secret

  # Number of drives attached to a node
  drivesPerNode: 1
  # Number of MinIO containers running
  replicas: 3
  # Number of expanded MinIO clusters
  pools: 1

  # Run minio server only on amd64 nodes
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/arch
            operator: In
            values:
            - amd64

  # Persistence
  persistence:
    enabled: true
    storageClass: "longhorn"
    accessMode: ReadWriteOnce
    size: 10Gi

  # Resource request
  resources:
    requests:
      memory: 1Gi

  # Service Monitor
  metrics:
    serviceMonitor:
      enabled: true
      includeNode: true

  # Minio Buckets
  buckets:
    - name: k3s-loki
      policy: none
    - name: k3s-tempo
      policy: none

  # Minio Policies
  policies:
    - name: loki
      statements:
        - resources:
            - 'arn:aws:s3:::k3s-loki'
            - 'arn:aws:s3:::k3s-loki/*'
          actions:
            - "s3:DeleteObject"
            - "s3:GetObject"
            - "s3:ListBucket"
            - "s3:PutObject"
    - name: tempo
      statements:
        - resources:
            - 'arn:aws:s3:::k3s-tempo'
            - 'arn:aws:s3:::k3s-tempo/*'
          actions:
            - "s3:DeleteObject"
            - "s3:GetObject"
            - "s3:ListBucket"
            - "s3:PutObject"
            - "s3:GetObjectTagging"
            - "s3:PutObjectTagging"
  # Minio Users
  users:
    - accessKey: loki
      existingSecret: minio-secret
      existingSecretKey: lokiPassword
      policy: loki
    - accessKey: tempo
      existingSecret: minio-secret
      existingSecretKey: tempoPassword
      policy: tempo

  ```

  In the production overlay used in this repository, MinIO is exposed with Gateway API using a dedicated `route` component instead of Helm-managed `Ingress` resources:

  ```yaml
  apiVersion: gateway.networking.k8s.io/v1
  kind: HTTPRoute
  metadata:
    name: minio
  spec:
    hostnames:
    - s3.${CLUSTER_DOMAIN}
    parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: public-gateway
      namespace: envoy-gateway-system
    rules:
    - backendRefs:
        - name: minio
          port: 9000
      matches:
      - path:
          type: PathPrefix
          value: /
  ---
  apiVersion: gateway.networking.k8s.io/v1
  kind: HTTPRoute
  metadata:
    name: minio-console
  spec:
    hostnames:
    - minio.${CLUSTER_DOMAIN}
    parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: public-gateway
      namespace: envoy-gateway-system
    rules:
    - backendRefs:
       - name: minio-console
         port: 9001
      matches:
      - path:
          type: PathPrefix
          value: /
  ```

  {{site.data.alerts.note}}

  Substitute variables (`${var}`) in the above yaml file before deploying manifest.
  -   Replace `${CLUSTER_DOMAIN}` by the domain name used in the cluster. For example: `homelab.ricsanfre.com`.

  Envoy Gateway exposes the MinIO S3 API as `s3.${CLUSTER_DOMAIN}` and the MinIO console as `minio.${CLUSTER_DOMAIN}`. TLS is terminated at the shared Envoy Gateway listener.

  External-DNS can be configured to automatically publish both hostnames from their `HTTPRoute` resources. Further details in ["DNS (CoreDNS and External-DNS) - Gateway API support"](/docs/kube-dns/#gateway-api-support).

  {{site.data.alerts.end}}

  With this configuration:

  - Minio cluster of 3 nodes (`replicas`) is created with 1 drive per node (`drivesPerNode`) of 10Gb (`persistence`)

  - Root user and passwork is obtained from the secret created in Step 3 (`existingSecret`).

  - Memory resources for each replica is set to 1GB (`resources.requests.memory`). Default config is 16GB which is not possible in a Raspberry Pi.

  - Enable creation of Prometheus ServiceMonitor object (`metrics.serviceMonitor`).

  - Minio PODs are deployed only on x86 nodes (`affinity`). Minio does not work properly when mixing nodes of different architectures. See [issue #137](https://github.com/ricsanfre/pi-cluster/issues/137)

  - Buckets (`buckets`), users (`users`) and policies (`policies`) are created for Loki and Tempo. See [Pi Cluster Loki documentation](/docs/loki/) and [Pi Cluster Tempo documentation](/docs/tracing/) for the details.

  - `HTTPRoute` resource exposes the S3 API at `s3.${CLUSTER_DOMAIN}` through Envoy Gateway.

  - `HTTPRoute` resource exposes the S3 console at `minio.${CLUSTER_DOMAIN}` through Envoy Gateway.

  - DNS records for both hostnames can be published automatically from Gateway API resources by External-DNS.

- Step 5: Install Minio in `minio` namespace
  ```shell
  helm install minio minio -f minio-values.yml --namespace minio
  ```
- Step 6: Check status of Loki pods
  ```shell
  kubectl get pods -l app.kubernetes.io/name=minio -n minio
  ```

## Observability

### Metrics

Minio exposes Prometheus-based metrics

{{site.data.alerts.important}} v2 vs v3 metric endpoints

Starting with MinIO Server [RELEASE.2024-07-15T19-02-30Z](https://github.com/minio/minio/releases/tag/RELEASE.2024-07-15T19-02-30Z) and MinIO Client [RELEASE.2024-07-11T18-01-28Z](https://github.com/minio/mc/releases/tag/RELEASE.2024-07-11T18-01-28Z), metrics version 3 provides additional endpoints. MinIO recommends version 3 for new deployments.
-   Metrics v2 description[^1]
-   Metrics v3 description[^2]

Grafana dashboards only available for v2:
-   It seems Minio is not going to maintain a official dashboard for v3. See [https://github.com/minio/minio/issues/20678](https://github.com/minio/minio/issues/20678)
-   There is a community maintained v3 dashboard at [https://github.com/FedericoAntoniazzi/minio-grafana-dashboard-metrics-v3](https://github.com/FedericoAntoniazzi/minio-grafana-dashboard-metrics-v3)
{{site.data.alerts.end}}

For details see [Minio's documentation: "Collect MinIO Metrics Using Prometheus"](https://docs.min.io/minio/baremetal/monitoring/metrics-alerts/collect-minio-metrics-using-prometheus.html).

#### Prometheus Integration

By default, MinIO requires authentication to scrape the metrics endpoints, but Vanilla Minio Helm Chart, set `MINIO_PROMETHEUS_AUTH_TYPE` environment variable to `public`, and authentication is not needed.

`ServiceMonitoring`, Prometheus Operator's CRD,  resource can be automatically created so Kube-Prometheus-Stack is able to automatically start collecting metrics from Minio

```yaml
# Service Monitor
metrics:
  serviceMonitor:
    enabled: true
    # scrape each node/pod individually for additional metrics
    includeNode: true
```
`ServiceMonitor` resource created by HelmChart only configures Prometheus to get metricds from `/minio/v2/metrics/node`

#### Grafana dashboards

MinIO provides Grafana Dashboards to display metrics collected by Prometheus.

There are 3 Dashboards available:

-   MinIO Server Metrics Dashboard: [Grafana dashboard id: 13502](https://grafana.com/grafana/dashboards/13502-minio-dashboard/)
-   MinIO Bucket Metrics Dashboard: [Grafana dashboard id: 19237](https://grafana.com/grafana/dashboards/19237-minio-bucket-dashboard/)
-   MinIO Node Metrics Dashboard: Available in MiniO GitHub Repo: [mino-node.json](https://raw.githubusercontent.com/minio/minio/master/docs/metrics/prometheus/grafana/node/minio-node.json)
-   MinIO Replication Metrics Dashboard: [Grafana dashbord Id 15305](https://grafana.com/grafana/dashboards/15305-minio-replication-dashboard/)


Dashboard can be automatically added using Grafana's dashboard providers configuration. See further details in ["PiCluster - Observability Visualization (Grafana): Automating installation of community dashboards](/docs/grafana/#automating-installation-of-grafana-community-dashboards)

Add following configuration to Grafana's helm chart values file, so a MinIO's dashboard provider can be created and dashboards can be automatically downloaded from GitHub repository

```yaml
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: minio
        orgId: 1
        folder: Minuo
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/minio-folder
# Dashboards
dashboards:
  minio:
    minio-server:
      # https://grafana.com/grafana/dashboards/13502-minio-dashboard/
      # renovate: depName="MinIO Dashboard"
      gnetId: 13502
      revision: 26
      datasource:
        - { name: DS_PROMETHEUS, value: Prometheus }
    minio-bucket:
      # https://grafana.com/grafana/dashboards/19237-minio-bucket-dashboard/
      # renovate: depName="MinIO Dashboard"
      gnetId: 19237
      revision: 2
      datasource:
        - { name: DS_PROMETHEUS, value: Prometheus }
    minio-node:
      url: https://raw.githubusercontent.com/minio/minio/master/docs/metrics/prometheus/grafana/node/minio-node.json
      datasource: Prometheus
    minio-replication:
      # https://grafana.com/grafana/dashboards/15305-minio-replication-dashboard/
      # renovate: depName="MinIO Dashboard"
      gnetId: 15305
      revision: 5
      datasource:
        - { name: DS_PROMETHEUS, value: Prometheus }
```
---

[^1]: [https://min.io/docs/minio/linux/operations/monitoring/metrics-v2.html](https://min.io/docs/minio/linux/operations/monitoring/metrics-v2.html)
[^2]: [https://min.io/docs/minio/linux/operations/monitoring/metrics-and-alerts.html](https://min.io/docs/minio/linux/operations/monitoring/metrics-and-alerts.html)