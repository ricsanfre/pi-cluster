---
title: Distributed Tracing (Tempo)
permalink: /docs/tracing/
description: How to deploy a distributed tracing solution based on Grafana Tempo.
last_modified_at: "19-11-2022"
---

## Tempo architecture

Tempo architecture is displayed in the following picture (source: [Grafana documentation](https://grafana.com/docs/tempo/latest/operations/architecture/)):

![Tempo-Architecture](/assets/img/tempo_arch.png)

Tempo architecture is quite similar to Loki's.

- Distributor: responsible for collect traces in different formats (Jaeger, Zipkin, OpenTelemetry)
- Ingester: responsible for batching trace into blocks and storing them in S3 backend
- Query Frontend: responsible for sharding the search space for an incoming query and distributed the sharded query to querier component
- Querier: responsible for finding the requested trace id in either the ingesters or the backend storage
- Compactor: responsible for compacting trace blocks in the backend.

All Tempo components are included within a single binary (docker image) that  supports two different deployments modes (helm installation) where the above components can be started in different PODs:

- Monolithic mode

  In this mode, all Tempo components are running in a single process (container).

- Microservices mode

  In microservices mode, components are deployed in distinct processes. Scaling and HA is specified by microservice.

  - Write nodes: supporting write path. *Distributor* and *Ingestor* components, responsible to store logs and indexes in the back-end storage (Minio S3 storage)
  - Read nodes: supporting read path. *Ruler*, *Querier* and *Frontend Querier* components, responsible to answer to log queries.
  - Gateway node: a load balancer in front of Loki (nginx based), which directs `/loki/api/v1/push` traffic to the write nodes. All other requests go to the read nodes. Traffic should be sent in a round robin fashion.

Further details in Tempo architecture documentation: [Tempo Architecture](https://grafana.com/docs/tempo/latest/operations/architecture/) and [Tempo deployment](https://grafana.com/docs/tempo/latest/operations/deployment/)

Loki will be installed using Simple scalable deployment mode using as S3 Object Storage Server (Minio) as backend.



## Configure S3 Minio Server

Minio Storage server is used as Tempo long-term data storage. 

Grafana Tempo needs to store two different types of data: chunks and indexes. Both of them can be stored in S3 server.

{{site.data.alerts.note}}

As part of the backup infrastructure a bare-metal Minio S3 server has been configured in `node1`. See documentation: [Backup & Restore - Minio S3 Object Store Server](/docs/backup/#minio-s3-object-storage-server). So I will re-use it as Tempo backend.

As alternative a Minio server can be deployed as a another kubernetes service. Tempo distribubted helm chart is able to install this Minio service as a subchart.

{{site.data.alerts.end}}

### Create Minio user and bucket

Use Minio's `mc` command to create Tempo bucket and user

```shell
mc mb <minio_alias>/k3s-tempo 
mc admin user add <minio_alias> tempo <user_password>
```
{{site.data.alerts.note}}

As the [Tempo's documentation states](https://grafana.com/docs/tempo/latest/configuration/s3/#amazon-s3-permissions), when using S3 as object storage, the following permissions are needed:

- s3:ListBucket
- s3:PutObject
- s3:GetObject
- s3:DeleteObject
- s3:GetObjectTagging
- s3:PutObjectTagging

Over the resources: arn:aws:s3:::<bucket_name>, arn:aws:s3:::<bucket_name>/*

{{site.data.alerts.end}}

Apply policy to user `tempo` so it has the proper persmissions on `k3s-tempo` bucket.

```shell
  mc admin policy add <minio_alias> tempo user_policy.json
```

Where `user_policy.json`, contains the following AWS access policies definition:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "TempoPermissions",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:DeleteObject",
                "s3:GetObjectTagging",
                "s3:PutObjectTagging"
            ],
            "Resource": [
                "arn:aws:s3:::k3s-tempo/*",
                "arn:aws:s3:::k3s-tempo"
            ]
        }
    ]
}
``` 

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
  kubectl create namespace tracing
  ```
- Step 4: Create file `tempo-values.yml`

  ```yml
  # Enable trace ingestion
  traces:
    otlp:
      grpc:
        enabled: true
      http:
        enabled: true
    zipkin:
      enabled: true
    jaeger:
      thriftCompact:
        enabled: true
      thriftHttp:
        enabled: true
    opencensus:
      enabled: true

  # Configure S3 backend
  storage:
    trace:
      backend: s3
      s3:
        bucket: <minio_tempo_bucket>
        endpoint: <minio_endpoint>
        region: <minio_site_region>
        access_key: <minio_tempo_user>
        secret_key: <minio_tempo_key>
        insecure: false

  # Configure distributor
  distributor:
    config:
      log_received_spans:
        enabled: true

  # Disable Minio server installation
  minio:
    enabled: false
  ```

  This configuration:

  - Enable S3 as storage backend, providing Minio credentials and bucket.

  - Enalbe traces ingestion of different protocols.

  - Disable minio server installation (`minio.enabled`)

- Step 3: Install Tempo in `tracing` namespace
  ```shell
  helm install tempo grafana/tempo-distributed -f tempo-values.yml --namespace tracing
  ```
- Step 4: Check status of Loki pods
  ```shell
  kubectl get pods -l app.kubernetes.io/name=loki -n logging
  ```
  




## Linkerd traces integration

[Linkerd-jaeger extension](https://linkerd.io/2.12/tasks/distributed-tracing/) is needed for activating the emisson of traces of linkerd-proxys components.

Linkerd jaegger extension, by default, installs Jaeger, as tracing solution backend, [OpenTelemetry collector](https://opentelemetry.io/docs/collector/), to collect and distribute traces to Jaeger backend and Jaegger-injector, responsible for configuring the Linkerd proxies to emit spans.

Tempo will be used, instead of Jaeger, and Tempo distributor component has a embedded OpenTelemetry collector. So non of those components will be installe. Only jaeger-injector needs to be installed.

- Step 1. Prepare linked-jaeger-values.yml

  ```yml
  collector:
    enabled: false
  jaeger:
    enabled: false
  webhook:
    collectorSvcAddr: tempo-distributor.tracing:55678
    collectorSvcAccount: tempo
  ```
  This configuration disables Jaeger and OTel Collector installation and configures jaeger-injector to send traces span to tempo-distributor component using OpenCensus receiver (port 55678)

  `webhook.collectorSvcAddr` is OpenCensus endpoint distributor receiver
  `webhook.collectorSvcAccount` is service account name used by Tempo.

- Step 2. Install jaeger-extensiong helm chart

  ```shell
  helm install linkerd-jaeger -n linkerd-jaeger --create-namespace linkerd/linkerd-jaeger -f linkerd-jaeger-values.yml
  ```

## Traefik traces integration

The ingress is a key component for distributed tracing solution because it is reposible for creating the root span of each trace and for deciding if that trace should be sampled or not.

Distributed tracing systems all rely on propagate the trace context throuhg the chain of involved services. This trace contex is encoding in HTTP request headers. Of the available propagation protocols, B3 is the only one supported by Linkerd, and so this is the one to be used in the whole system.

Traefik uses OpenTracet to export traces to different backends. 

To activate tracing using B3 propagation protocol, the following options need to be provided
  
```
--tracing.zipkin=true
--tracing.zipkin.httpEndpoint=http://tempo-distributor.tracing.svc.cluster.local:9411/api/v2/spans
--tracing.zipkin.sameSpan=true
--tracing.zipkin.id128Bit=true
--tracing.zipkin.sampleRate=1
```

For more details see [Traefik tracing documentation](https://doc.traefik.io/traefik/observability/tracing/overview/)

In order to be able to correlate logs with traces in Grafana, Traefik access log should be configured so, trace ID is also present as a field in the logs. Trace ID comes as a header field (`X-B3-Traceid`), that need to be included in the logs.

By default no header is included in Traefik's access log. Additional parameters need to be added to include the traceID.

```
--accesslog.fields.headers.defaultmode=drop
--accesslog.fields.headers.names.X-B3-Traceid=keep
```

See more details in [Traefik access log documentation](https://doc.traefik.io/traefik/observability/access-logs/#limiting-the-fieldsincluding-headers).

When installing Traefik with Helm the following values.yml file achieve the above configuration

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

In Traefik's access logs, a new field appear `request_X-B3-Traceid` containing trace id that can be used to extrac Tempo traces information.

## Grafana Configuration

Tempo need to be added to Grafana as DataSource

This can be done automatically when installing kube-prometheus-stack providing the following additional helm chart configuration:

```yml
grafana:
  # Additional data source
  additionalDataSources:
  - name: Tempo
    type: tempo
    uid: tempo
    access: proxy
    url: http://tempo-query-frontend.tracing.svc.cluster.local:3100
```

### Loki and Tempo integration

Grafana's Loki data source can be configured to detect traceID automatically and providing a link in grafana to automatically opening the corresponding trace information from Tempo.

See [Loki data source - derived Fields](https://grafana.com/docs/grafana/latest/datasources/loki/#derived-fields).

In order to automatically detect traceID from Traefik logs following configuration need to be provided to kube-prometheus-stack.

This can be done automatically when installing kube-prometheus-stack providing the following helm chart configuration:

```yml
grafana
  additionalDataSources:
  - name: Loki
    type: loki
    uid: loki
    access: proxy
    url: http://loki-gateway.logging.svc.cluster.local
    jsonData:
      derivedFields:
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


## Testing with Emojivoto application

Linkerd's testing application emojivoto can be used to test the tracing solution.

- Step 1: Install emojivoto application using linkerd cli
  ```shell
  linkerd inject https://run.linkerd.io/emojivoto.yml | kubectl apply -f -
  ```

- Step 2: Configure emojivoto applicatio to emit spans to Tempo

  ```shell
  kubectl -n emojivoto set env --all deploy OC_AGENT_HOST=tempo-distributor.tempo:55678
  ```
