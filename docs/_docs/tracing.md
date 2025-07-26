---
title: Distributed Tracing (Tempo)
permalink: /docs/tracing/
description: How to deploy a distributed tracing solution based on Grafana Tempo.
last_modified_at: "24-04-2024"
---


Distributed tracing solution for Kuberentes cluster is based on [Grafana Tempo](https://grafana.com/oss/tempo/).

![tracing-architecture](/assets/img/tracing-architecture.png)


Grafana Tempo is used as traces backend and Grafana as front-end. Tempo, integrates a [Open Telemetry collector](https://opentelemetry.io/docs/collector/) enabling the ingestion of traces generated with common open source tracing protocols like Jaeger, Zipkin, and OpenTelemetry.

Tempo requires only object storage backend to operate, and is integrated with Grafana, Prometheus, and Loki. Minio S3 Object Store will be used as Tempo backend.


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


Further details in Tempo architecture documentation: [Tempo Architecture](https://grafana.com/docs/tempo/latest/operations/architecture/) and [Tempo deployment](https://grafana.com/docs/tempo/latest/setup/deployment/)

Tempo will be installed using microservices mode configuring S3 Object Storage Server (Minio) as backend.

## Configure S3 Minio Server

Minio Storage server is used as Tempo long-term data storage. 

Grafana Tempo needs to store two different types of data: chunks and indexes. Both of them can be stored in S3 server.

{{site.data.alerts.note}}

Tempo helm chart is able to install this Minio service as a subchart, but its installation will be disabled and Minio Storage Service already deployed in the cluster will be used as Tempo's backend. 

As part of Minio Storage Service installation, Tempo's S3 bucket, policy and user is already configured.
See documentation: [Minio S3 Object Storage Service](/docs/minio/).

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

## Tempo Installation

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
  kubectl create namespace tempo
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

- Step 3: Install Tempo in `tempo` namespace
  ```shell
  helm install tempo grafana/tempo-distributed -f tempo-values.yml --namespace tempo
  ```
- Step 4: Check status of Loki pods
  ```shell
  kubectl get pods -l app.kubernetes.io/name=tempo -n tempo
  ```

### GitOps installation

As an alternative, for GitOps deployments, instead of hardcoding minio credentials within Helm chart values, a external secret can be configured leveraging [Tempo's capability of using environment variables in config file](https://grafana.com/docs/tempo/latest/configuration/#use-environment-variables-in-the-configuration)

The following secret need to be created:
```yml
apiVersion: v1
kind: Secret
metadata:
  name: tempo-minio-secret
  namespace: tempo
type: Opaque
data:
  MINIO_ACCESS_KEY_ID: < minio_tempo_user | b64encode >
  MINIO_SECRET_ACCESS_KEY: < minio_tempo_key | b64encode >
```

And the following Helm values has to be provided:

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
      bucket: k3s-tempo
      endpoint: minio.minio:9091
      region: eu-west-1
      access_key: ${MINIO_ACCESS_KEY_ID}
      secret_key: ${MINIO_SECRET_ACCESS_KEY}
      insecure: true

# Configure distributor
distributor:
  config:
    log_received_spans:
      enabled: true
  # Enable environment variables in config file
  # https://grafana.com/docs/tempo/latest/configuration/#use-environment-variables-in-the-configuration
  extraArgs:
    - '-config.expand-env=true'
  extraEnv:
    - name: MINIO_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: tempo-minio-secret
          key: MINIO_ACCESS_KEY_ID
    - name: MINIO_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: tempo-minio-secret
          key: MINIO_SECRET_ACCESS_KEY
# Configure ingester
ingester:
  # Enable environment variables in config file
  # https://grafana.com/docs/tempo/latest/configuration/#use-environment-variables-in-the-configuration
  extraArgs:
    - '-config.expand-env=true'
  extraEnv:
    - name: MINIO_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: tempo-minio-secret
          key: MINIO_ACCESS_KEY_ID
    - name: MINIO_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: tempo-minio-secret
          key: MINIO_SECRET_ACCESS_KEY
# Configure compactor
compactor:
  # Enable environment variables in config file
  # https://grafana.com/docs/tempo/latest/configuration/#use-environment-variables-in-the-configuration
  extraArgs:
    - '-config.expand-env=true'
  extraEnv:
    - name: MINIO_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: tempo-minio-secret
          key: MINIO_ACCESS_KEY_ID
    - name: MINIO_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: tempo-minio-secret
          key: MINIO_SECRET_ACCESS_KEY
# Configure querier
querier:
  # Enable environment variables in config file
  # https://grafana.com/docs/tempo/latest/configuration/#use-environment-variables-in-the-configuration
  extraArgs:
    - '-config.expand-env=true'
  extraEnv:
    - name: MINIO_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: tempo-minio-secret
          key: MINIO_ACCESS_KEY_ID
    - name: MINIO_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: tempo-minio-secret
          key: MINIO_SECRET_ACCESS_KEY
# Configure query-frontend
queryFrontend:
  # Enable environment variables in config file
  # https://grafana.com/docs/tempo/latest/configuration/#use-environment-variables-in-the-configuration
  extraArgs:
    - '-config.expand-env=true'
  extraEnv:
    - name: MINIO_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: tempo-minio-secret
          key: MINIO_ACCESS_KEY_ID
    - name: MINIO_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: tempo-minio-secret
          key: MINIO_SECRET_ACCESS_KEY
# Disable Minio server installation
minio:
  enabled: false
```

## Tempo Configuration


### Grafana Configuration

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
    url: http://tempo-query-frontend-discovery.tempo.svc.cluster.local:3200
```

### Loki and Tempo integration

Grafana's Loki data source can be configured to detect traceID automatically and providing a link in grafana to automatically opening the corresponding trace information from Tempo.

See [Loki data source - derived Fields](https://grafana.com/docs/grafana/latest/datasources/loki/#derived-fields).

This can be done automatically when installing kube-prometheus-stack providing the following helm chart configuration:

```yml
grafana
  additionalDataSources:
  - name: Loki
    type: loki
    uid: loki
    access: proxy
    url: http://loki-read-headless.loki.svc.cluster.local
    jsonData:
      derivedFields:
        # Traefik traces integration
        # - datasourceUid: tempo
        #   matcherRegex: '"request_X-B3-Traceid":"(\w+)"'
        #   name: TraceID
        #   url: $${__value.raw}
          # NGINX traces integration
        - datasourceUid: tempo
          matcherRegex: '"trace_id": "(\w+)"'
          name: TraceID
          url: $${__value.raw}
  - name: Tempo
    uid: tempo
    type: tempo
    access: proxy
    url: http://tempo-query-frontend-discovery.tempo.svc.cluster.local:3200
```

A derived field `TraceID` is added to logs whose message contains field `request_X-B3-Traceid` (Traefik access logs) or containing `trace_id` (NGINX access logs)

## Testing with Emojivoto application


{{site.data.alerts.warning}}

Because of the deprecation of OpenTracing in Ingress NGINX release 1.10. E2E tracing propagation using Linkerd's emojivoto application is not working anymore.

Emojivoto is using OpenTracing B3 context propagation while Nginx is using W3C. So tracing context is not being propagated from NGINX to emojivoto microservices.

See [issue #329](https://github.com/ricsanfre/pi-cluster/issues/329).

A different testing application, using OpenTelemetry instead of Opentracing, is needed.

{{site.data.alerts.end}}

Linkerd's testing application emojivoto can be used to test the tracing solution.

- Step 1: Install emojivoto application using linkerd cli
  ```shell
  linkerd inject https://run.linkerd.io/emojivoto.yml | kubectl apply -f -
  ```

- Step 2: Configure emojivoto application to emit spans to Tempo

  ```shell
  kubectl -n emojivoto set env --all deploy OC_AGENT_HOST=tempo-distributor.tempo:55678
  ```

- Step 3: Create Ingress

  ```yml
  kind: Ingress
  apiVersion: networking.k8s.io/v1
  metadata:
    name: emojivoto
    namespace: emojivoto
    annotations:
      # Linkerd configuration. Configure Service as Upstream
      nginx.ingress.kubernetes.io/service-upstream: "true"
      nginx.ingress.kubernetes.io/enable-opentracing: "true"
  spec:
    ingressClassName: nginx
    rules:
      - host: emojivoto.picluster.ricsanfre.com
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: web-svc
                  port:
                    number: 80
  ```

- Step 4: Connect to emojivoto.picluster.ricsanfre.com and vote!!

  ![emoji-vote](/assets/img/emojivoto.png)

- Step 5: Connect to Grafana, select Explorer and Loki data source

  Filter logs usin LQL: 
  {% raw %}
  ```
  {app="ingress-nginx", container="stream-accesslog"} | json | line_format "{{.message}}" | json | request_host="emojivoto.picluster.ricsanfre.com" | uri =~ "/api/vote.+"
  ```
  {% endraw %}

  Logs containing the votes made in step 5 are displayed.

  ![emojivote-logs](/assets/img/emojivoto-logs.png)

- Open details of one of the logs and click on Tempo link, traces to that specific transaction are showed

  ![emojivote-logs](/assets/img/emojivoto-loki-tempo.png)

  