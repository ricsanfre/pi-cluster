---
title: Log Aggregation (Loki)
permalink: /docs/loki/
description: How to deploy Grafana Loki in our Raspberry Pi Kubernetes cluster.
last_modified_at: "21-11-2026"

---

## Loki architecture

Loki architecture is displayed in the following picture (source: [Grafana documentation](https://grafana.com/docs/loki/latest/fundamentals/architecture/components)):

![LOKI-Architecture-Components](/assets/img/loki_architecture_components.svg)

All Loki components are included within a single binary (docker image) that  supports three different deployments modes where the above components can be started in different PODs 

- Monolithic

  In this mode, all Loki components are running in a single process (container).

- Simple scalable mode

  In this deployment, Loki is deployed in HA, deploying replicas of write and read nodes (processes)
  - Write nodes: supporting write path. *Distributor* and *Ingestor* components, responsible to store logs and indexes in the back-end storage (S3 storage)
  - Read nodes: supporting read path. *Ruler*, *Querier* and *Frontend Querier* components, responsible to answer to log queries.
  - Backend nodes: loki backend services *Compactor*, *Index gateways* and *Query scheduler – Ruler*
  - Gateway node: a load balancer in front of Loki (nginx based), which directs `/loki/api/v1/push` traffic to the write nodes. All other requests go to the read nodes. Traffic should be sent in a round robin fashion.

- Microservices
  In this deployment each individual Loki component can be started in an independent process (container).
  

Further details in Loki architecture documentation: [Loki components](https://grafana.com/docs/loki/latest/fundamentals/architecture/components/) and [deployment modes](https://grafana.com/docs/loki/latest/fundamentals/architecture/deployment-modes/)

Loki will be installed using Simple scalable deployment mode using an S3 Object Storage Server as backend.


![K3S-LOKI-Architecture](/assets/img/loki-architecture.png)

## Configure S3 Server

The S3 storage server is used as Loki long-term data storage. 

Grafana Loki needs to store two different types of data: chunks and indexes. Both of them can be stored in an S3-compatible server.

{{site.data.alerts.note}}

Loki helm chart is able to install an S3 service as a subchart, but its installation will be disabled and the S3 Storage Service already deployed in the cluster will be used as Loki's backend. 

As part of the S3 Storage Service installation, loki's S3 bucket, policy and user is already configured.
See documentation: ["PiCluster - S3 Backup Backend"](/docs/rustfs/).

{{site.data.alerts.end}}

### Create S3 user and bucket

Use RustFS CLI (`rc`) to create the loki bucket and user:

```shell
rc mb <s3_alias>/k3s-loki 
rc admin user add <s3_alias> loki <user_password>
```
{{site.data.alerts.note}}

As the Loki's documentation said, when using S3 as object storage, the following permissions are needed:

- s3:ListBucket
- s3:PutObject
- s3:GetObject
- s3:DeleteObject (if running the Single Store (boltdb-shipper) compactor)

Over the resources: arn:aws:s3:::<bucket_name>, arn:aws:s3:::<bucket_name>/*

{{site.data.alerts.end}}

Apply policy to user `loki` so it has the proper persmissions on `k3s-loki` bucket.

```shell
  rc admin policy create <s3_alias> loki user_policy.json
  rc admin policy attach <s3_alias> loki loki
```

Where `user_policy.json`, contains the following AWS access policies definition:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Effect": "Allow",
        "Action": [
            "s3:DeleteObject",
            "s3:GetObject",
            "s3:ListBucket",
            "s3:PutObject"
        ],
        "Resource": [
            "arn:aws:s3:::k3s-loki",
            "arn:aws:s3:::k3s-loki/*"
        ]
    }  
  ]
}
``` 

See further details in [Loki-Storage documentation](https://grafana.com/docs/loki/latest/operations/storage/)

## Loki installation

Installation from helm chart. There are two alternatives:

- [Loki-stack helm chart](https://github.com/grafana/helm-charts/tree/main/charts/loki-stack). With this helm chart the complete PLG stack can be installed.
  
  This helm chart will not be used because we are only interested in deploying Loki component. Promtail will not be used and Grafana will be deployed as part of kube-prometheus-stack.

- [Loki-helm chart v3.x](https://github.com/grafana/loki/tree/main/production/helm/loki). Used for [Monolithic](https://grafana.com/docs/loki/latest/fundamentals/architecture/deployment-modes/#monolithic-mode) and Simple scalable deployment modes](https://grafana.com/docs/loki/latest/fundamentals/architecture/deployment-modes/#simple-scalable-deployment-mode).

  This is the helm chart we will use to deploy Loki in HA (simple scalable deployment mode).

- Step 1: Add the Grafana repository:
  ```shell
  helm repo add grafana https://grafana.github.io/helm-charts
  ```
- Step2: Fetch the latest charts from the repository:
  ```shell
  helm repo update
  ```
- Step 3: Create namespace
  ```shell
  kubectl create namespace loki
  ```
- Step 4: Create file `loki-values.yml`

  ```yml
  # Setting simple scalable deployment mode
  deploymentMode: SimpleScalable

  loki:
    # Disable multi-tenant support
    auth_enabled: false

    limits_config:
      max_query_lookback: 168h
      retention_period: 168h

    compactor:
      compaction_interval: 10m
      delete_request_store: s3
      retention_delete_delay: 2h
      retention_enabled: true
      working_directory: /var/loki/retention

    # S3 backend storage configuration
    storage:
      bucketNames:
        chunks: <s3_loki_bucket>
        ruler: <s3_loki_bucket>
      type: s3
      s3:
        endpoint: <s3_endpoint>
        region: <s3_site_region>
        secretAccessKey: <s3_loki_key>
        accessKeyId: <s3_loki_user>
        s3ForcePathStyle: true
        insecure: false
        http_config:
          idle_conn_timeout: 90s
          response_header_timeout: 0s
          insecure_skip_verify: false
    # Storage Schema
    schemaConfig:
      configs:
      - from: 2024-04-01
        store: tsdb
        index:
          prefix: loki_index_
          period: 24h
        object_store: s3
        schema: v13

  # Configuration for the write
  write:
    # Number of replicas for the write
    replicas: 3
    persistence:
      # -- Size of persistent disk
      size: 10Gi
      # -- Storage class to be used.
      storageClass: longhorn

  # Configuration for the read
  read:
    # Number of replicas for the read
    replicas: 3
    persistence:
      # -- Size of persistent disk
      size: 10Gi
      # -- Storage class to be used.
      storageClass: longhorn

  # Configuration for the backend
  backend:
    # Number of replicas for the backend
    replicas: 3
    persistence:
      # -- Size of persistent disk
      size: 10Gi
      # -- Storage class to be used.
      storageClass: longhorn

  # Configuration for the gateway
  gateway:
    # -- Specifies whether the gateway should be enabled
    enabled: true
    # -- Number of replicas for the gateway
    replicas: 1

  # Disable S3 server subchart
  minio:
    enabled: false

  # Disable self-monitoring
  monitoring:
    selfMonitoring:
      enabled: false
      grafanaAgent:
        installOperator: false
      lokiCanary:
          enabled: false

  # Disable helm-test
  test:
    enabled: false
  ```

  This configuration:

  - Set simple scalable deployment mode (`deploymentMode: SimpleScalable`)

  - Disable multi-tenant support (`auth_enabled: false`) so it is not needed to provide org_id in HTTP headers.

  - Enable S3 as storage backend, providing S3 credentials and bucket. (`loki.storage`).

  - Configure TSDB as storage schema (`loki.schemaConfig`). See [Loki Storage Schema doc](https://grafana.com/docs/loki/latest/operations/storage/schema/) and [TSDB Storage](https://grafana.com/docs/loki/latest/operations/storage/tsdb/)

  - Configure log retention in `limits_config`, keeping logs for 7 days (`168h`) and limiting queries to the same time window.

  - Enable the compactor so retention is actually enforced when using S3 object storage. The compactor runs every 10 minutes, stores delete requests in S3, and uses `/var/loki/retention` as local working directory.

  - Configure three replicas for write (`write`), read (`read`) and backend (`backend`)components and persistent volumes using Longhorn

  - Enable one replica for gateway component (`gateway`)

  - Disable built-in S3 server subchart (`minio.enabled`)

  - Disable self-monitoring (`monitoring.selfmonitoring`) and helm-test validation (`test.enabled`)

- Step 5: Install Loki in `loki` namespace
  ```shell
  helm install loki grafana/loki -f loki-values.yml --namespace loki
  ```
- Step 6: Check status of Loki pods
  ```shell
  kubectl get pods -l app.kubernetes.io/name=loki -n loki
  ```

### Compactor and data retention

When Loki uses TSDB with S3-compatible object storage, object storage alone does not enforce log retention. Retention only becomes effective when the compactor is enabled and `limits_config.retention_period` is set.

In this repository, Loki keeps logs for 7 days:

```yml
loki:
  limits_config:
    max_query_lookback: 168h
    retention_period: 168h

  compactor:
    compaction_interval: 10m
    delete_request_store: s3
    retention_delete_delay: 2h
    retention_enabled: true
    working_directory: /var/loki/retention
```

This configuration means:

- `retention_period: 168h` keeps log data for 7 days.
- `max_query_lookback: 168h` prevents queries from scanning data older than the retention window.
- `retention_enabled: true` activates retention processing in the compactor.
- `delete_request_store: s3` stores retention delete markers in the same S3 backend.
- `working_directory: /var/loki/retention` is local disk used by the compactor while processing retention operations.

Even when an S3 backend is used for long-term storage, Loki still needs local persistent storage on write and backend pods for TSDB working data and compactor processing.

### Homelab footprint optimization

For a small homelab cluster where high availability is not required, Loki can be tuned down to a single replica per component. The prod overlay used in this repository applies the following resource-saving configuration:

```yaml
# loki helm values (prod overlay)

loki:
  commonConfig:
    replication_factor: 1

write:
  replicas: 1
  persistence:
    size: 1Gi
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

read:
  replicas: 1
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

backend:
  replicas: 1
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

# Reduce memcached cache sizes from defaults (8GB chunks / 1GB results)
chunksCache:
  allocatedMemory: 256
  allocatedCPU: 100m

resultsCache:
  allocatedMemory: 128
  allocatedCPU: 100m
```

{{site.data.alerts.important}} **Replication factor must match write replicas**

Loki's `commonConfig.replication_factor` defaults to `3` in the Helm chart. When `write.replicas` is reduced to `1`, the replication factor must be set to `1` — otherwise the write ring rejects all push requests with HTTP 500 (`at least 2 live replicas required, could only find 1`). This is set via `loki.commonConfig.replication_factor: 1`.
{{site.data.alerts.end}}

Key changes from the defaults:

- **Single replica** for all components (`write`, `read`, `backend`) — sufficient for homelab workloads
- **`replication_factor: 1`** — matches the single write replica so the ingester ring accepts writes
- **Reduced persistence** to 1 Gi per component instead of the default 10 Gi
- **CPU and memory limits** appropriate for ARM64 Raspberry Pi nodes
- **Ingester (`write`) sized for WAL replay** — on restart the ingester loads its WAL into memory *on top
  of* its ~230 Mi steady state (~600 streams). At the previous 256 Mi limit the replay always crossed the
  limit, so the pod OOM-looped without ever draining the WAL, taking the write path and the fluentd Loki
  output down with it. `cpu 500m` / `memory 512Mi` is the value measured on this cluster; do not shrink it
  back to the pre-replay baseline.
- **Querier (`read`) sized for query load** — the canary's `count_over_time` and multi-hour `offset` queries
  plus Grafana Explore keep the querier busy. At 256 Mi it ran pinned at the limit, GC pressure throttled the
  CPU to 100 % and the 1 s readiness probe could not be served, so the Service lost its endpoints whenever
  the write path was healthy enough to give it work. `cpu 500m` / `memory 512Mi` for the same reason.
- **Smaller memcached caches** — 256 Mi chunks cache and 128 Mi results cache vs. defaults of 8 Gi and 1 Gi

### GitOps installation

As an alternative, for GitOps deployments, instead of hardcoding S3 credentials within Helm chart values, a external secret can be configured leveraging [Loki's capability of using environment variables in config file](https://grafana.com/docs/loki/latest/configuration/#use-environment-variables-in-the-configuration).


The following secret need to be created:
```yml
apiVersion: v1
kind: Secret
metadata:
  name: loki-s3-secret
  namespace: loki
type: Opaque
data:
  S3_ACCESS_KEY_ID: < minio_loki_user | b64encode >
  S3_SECRET_ACCESS_KEY: < minio_loki_key | b64encode >
```

And the following Helm values has to be provided:

```yml
loki:
  # Disable multi-tenant support
  auth_enabled: false

  limits_config:
    max_query_lookback: 168h
    retention_period: 168h

  compactor:
    compaction_interval: 10m
    delete_request_store: s3
    retention_delete_delay: 2h
    retention_enabled: true
    working_directory: /var/loki/retention

  # S3 backend storage configuration
  storage:
    bucketNames:
      chunks: k3s-loki
      ruler: k3s-loki
    type: s3
    s3:
      endpoint: s3.picluster.ricsanfre.com:9091
      region: eu-west-1
      secretAccessKey: ${S3_SECRET_ACCESS_KEY}
      accessKeyId: ${S3_ACCESS_KEY_ID}
      s3ForcePathStyle: true
      insecure: false
      http_config:
        idle_conn_timeout: 90s
        response_header_timeout: 0s
        insecure_skip_verify: false

    # Storage Schema
    schemaConfig:
      configs:
      - from: 2024-04-01
        store: tsdb
        index:
          prefix: loki_index_
          period: 24h
        object_store: s3
        schema: v13

# Configuration for the write
write:
  # Number of replicas for the write
  replicas: 3
  persistence:
    # -- Size of persistent disk
    size: 10Gi
    # -- Storage class to be used.
    storageClass: longhorn

  # Enable environment variables in config file
  # https://grafana.com/docs/loki/latest/configuration/#use-environment-variables-in-the-configuration
  extraArgs:
    - '-config.expand-env=true'
  extraEnv:
    - name: S3_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: loki-s3-secret
          key: S3_ACCESS_KEY_ID
    - name: S3_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: loki-s3-secret
          key: S3_SECRET_ACCESS_KEY

# Configuration for the read
read:
  # Number of replicas for the read
  replicas: 3
  persistence:
    # -- Size of persistent disk
    size: 10Gi
    # -- Storage class to be used.
    storageClass: longhorn

  # Enable environment variables in config file
  # https://grafana.com/docs/loki/latest/configuration/#use-environment-variables-in-the-configuration
  extraArgs:
    - '-config.expand-env=true'
  extraEnv:
    - name: S3_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: loki-s3-secret
          key: S3_ACCESS_KEY_ID
    - name: S3_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: loki-s3-secret
          key: S3_SECRET_ACCESS_KEY

# Configuration for the backend
backend:
  # Number of replicas for the backend
  replicas: 3
  persistence:
    # -- Size of persistent disk
    size: 10Gi
    # -- Storage class to be used.
    storageClass: longhorn

  # Enable environment variables in config file
  # https://grafana.com/docs/loki/latest/configuration/#use-environment-variables-in-the-configuration
  extraArgs:
    - '-config.expand-env=true'
  extraEnv:
    - name: S3_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: loki-s3-secret
          key: S3_ACCESS_KEY_ID
    - name: S3_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: loki-s3-secret
          key: S3_SECRET_ACCESS_KEY

# Configuration for the gateway
gateway:
  # -- Specifies whether the gateway should be enabled
  enabled: true
  # -- Number of replicas for the gateway
  replicas: 1

# Disable S3 server subchart
minio:
  enabled: false

# Disable self-monitoring
monitoring:
  selfMonitoring:
    enabled: false
    grafanaAgent:
      installOperator: false
  lokiCanary:
      enabled: false

# Disable helm-test
test:
  enabled: false

```

## Grafana Configuration

Loki need to be added to Grafana as DataSource

This can be done automatically when installing kube-prometheus-stack providing the following additional helm chart configuration:

```yml
grafana:
  # Additional data source
  additionalDataSources:
  - name: Loki
    type: loki
    url: http://loki-read-headless.loki.svc.cluster.local
```

## Observability

### Metrics

Loki exposes its own metrics in Prometheus format on the `http-metrics` port of every component. They
are the only way to see the ingester internals — stream count, WAL replay state — which cAdvisor and
pod logs cannot show.

#### Prometheus Integration

A `ServiceMonitor`, Prometheus Operator's CRD, can be created so kube-prometheus-stack automatically
starts collecting the metrics. In this repository it is environment-specific, so it lives in a
kustomization component that only the prod overlay loads:

```
kubernetes/platform/loki/app/components/monitoring/
├── kustomization.yaml   # kind: Component - ConfigMap merge + HelmRelease patch
├── helm-patch.yaml      # appends monitoring-values.yaml to spec.valuesFrom
└── values.yaml
```

The values it provides:

```yml
monitoring:
  serviceMonitor:
    enabled: true
  dashboards:
    enabled: true
clusterLabelOverride: pi-cluster
```

- `monitoring.serviceMonitor` creates a single `ServiceMonitor` in the `loki` namespace. The chart
  marks the services that must not be scraped — `loki-gateway`, the `*-headless` services and
  `loki-query-scheduler-discovery` — with `prometheus.io/service-monitor: "false"`, so the scrape
  targets are `write`, `read`, `backend`, `canary` and the two caches.
- `monitoring.selfMonitoring` stays disabled: it installs a second kube-prometheus stack from inside
  the chart, which is not wanted here.
- `clusterLabelOverride` keeps the `cluster` label on Loki's metrics equal to the Prometheus external
  label (`pi-cluster`) instead of the chart default `<release>-<chart>`. The bundled dashboards build
  their `cluster` variable from that label.

Without the component nothing scrapes Loki — the namespace has no `ServiceMonitor` and no
`PodMonitor` — which is why the ingester internals were invisible during the 2026-11 logging
incidents. `OBS-004` relies on `loki_ingester_memory_streams`, which only exists once the component
is deployed.

#### Grafana Dashboards

`monitoring.dashboards` creates the `loki-dashboards-1` and `loki-dashboards-2` ConfigMaps, labelled
`grafana_dashboard: "1"`, carrying the upstream dashboards version-matched to the chart:

-   `Loki / Operational`
-   `Loki / Writes`, `Loki / Reads`, `Loki / Writes Resources`, `Loki / Reads Resources`
-   `Loki / Retention`, `Loki / Chunks`, `Loki / Deletion`
-   `Loki / Logs`
-   `Recording Rules`

Labelled ConfigMaps are the same delivery route the fluentd, fluent-bit, Strimzi and CloudNativePG
charts already use in this cluster: the grafana-operator reads them cluster-wide, so no
`GrafanaDashboard` resource is needed. `monitoring.rules` stays disabled because none of these
dashboards query recorded metrics.

See [Grafana Operator - Provisioning Dashboards](/docs/grafana-operator/#provisioning-dashboards) for
the alternative `GrafanaDashboard` onboarding patterns.

