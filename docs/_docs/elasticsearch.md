---
title: Elasticsearch and Kibana
permalink: /docs/elasticsearch/
description: How to deploy Elasticsearch and Kibana in our Raspberry Pi Kuberentes cluster.
last_modified_at: "22-07-2022"

---

In June 2020, Elastic [announced](https://www.elastic.co/blog/elasticsearch-on-arm) that starting from 7.8 release they will provide multi-architecture docker images supporting AMD64 and ARM64 architectures.

To facilitate the deployment on a Kubernetes cluster [ECK project](https://github.com/elastic/cloud-on-k8s) was created.
ECK ([Elastic Cloud on Kubernetes](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)) automates the deployment, provisioning, management, and orchestration of ELK Stack (Elasticsearch, Kibana, APM Server, Enterprise Search, Beats, Elastic Agent, and Elastic Maps Server) on Kubernetes based on the operator pattern.

{{site.data.alerts.note}}
Logstash deployment is not supported by ECK operator
{{site.data.alerts.end}}

ECK Operator will be used to deploy Elasticsearh and Kibana.

## Elasticsearch and Kibana installation

### ECK Operator installation

- Step 1: Add the Elastic repository:
  ```shell
  helm repo add elastic https://helm.elastic.co
  ```
- Step2: Fetch the latest charts from the repository:
  ```shell
  helm repo update
  ```
- Step 3: Create namespace
  ```shell
  kubectl create namespace elastic-system
  ```
- Step 3: Install Longhorn in the elastic-system namespace
  ```shell
  helm install elastic-operator elastic/eck-operator --namespace elastic-system
  ```
- Step 4: Monitor operator logs:
  ```shell
  kubectl -n elastic-system logs -f statefulset.apps/elastic-operator
  ```

### Elasticsearch installation

Basic instructions can be found in [ECK Documentation: "Deploy and elasticsearch cluster"](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-deploy-elasticsearch.html)

- Step 1: Create a manifest file containing basic configuration: one node elasticsearch using Longhorn as   storageClass and 5GB of storage in the volume claims.
  
  ```yml
  apiVersion: elasticsearch.k8s.elastic.co/v1
  kind: Elasticsearch
  metadata:
    name: efk
    namespace: k3s-logging
  spec:
    version: 8.1.2
    nodeSets:
    - name: default
      count: 1    # One node elastic search cluster
      config:
        node.store.allow_mmap: false # Disable memory mapping: Note(1)
      volumeClaimTemplates: # Specify Longhorn as storge class and 5GB of storage: Note(2)
      - metadata:
          name: elasticsearch-data
        spec:
          accessModes:
          - ReadWriteOnce
          resources:
            requests:
              storage: 5Gi
          storageClassName: longhorn
    http:
      tls: # Disabling TLS automatic configuration. Note(3)
        selfSignedCertificate:
          disabled: true
  ```
  
  {{site.data.alerts.note}} **(1) About Memory mapping configuration**

  By default, Elasticsearch uses memory mapping (`mmap`) to efficiently access indices. To disable this default mechanism add the following configuration option:
  ```yml
  node.store.allow_nmap: false
  ```
  Usually, default values for virtual address space on Linux distributions are too low for Elasticsearch to work properly, which may result in out-of-memory exceptions. This is why `mmap` is disable.

  For production workloads, it is strongly recommended to increase the kernel setting `vm.max_map_count` to 262144 and leave `node.store.allow_mmap` unset.

  See further details in [ECK Documentation: "Elastisearch Virtual Memory"](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-virtual-memory.html)
  {{site.data.alerts.end}}

  {{site.data.alerts.note}} **(2): About Persistent Storage**

  See how to configure PersistenVolumeTemplates for Elasticsearh using this operator in [ECK Documentation: "Volume claim templates"](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-volume-claim-templates.html)
  {{site.data.alerts.end}}


  {{site.data.alerts.note}} **(3): Disable TLS automatic configuration**

  By default ECK configures secured communications with auto-signed SSL certificates. Access to its service endpoint on port 9200 is only available through https.

  Disabling TLS automatic configuration in Elasticsearch HTTP server enables Linkerd (Cluster Service Mesh) to gather more statistics about connections. Linkerd is parsing plain text traffic (HTTP) instead of encrypted (HTTPS).
  
  Linkerd service mesh will enforce secure communications using TLS between all PODs.
  
  {{site.data.alerts.end}}

- Step 2: Apply manifest
  
  ```shell
  kubectl apply -f manifest.yml
  ```
- Step 3: Check Elasticsearch status
  
  ```shell
  kubectl get elasticsearch -n k3s-logging
  NAME   HEALTH   NODES   VERSION   PHASE   AGE
  efk    yellow   1       8.1.2    Ready   139m
  ```
   
  {{site.data.alerts.note}}

  Elasticsearch status `HEALTH=yellow` indicates that only one node of the Elasticsearch is running (no HA mechanism), `PHASE=Ready` indicates that the server is up and running

  {{site.data.alerts.end}}


#### Elasticsearch authentication

By default ECK configures user authentication to access elasticsearch service. ECK defines a default admin esaticsearch user (`elastic`) and with a password which is stored within a kubernetes Secret.

Both to access elasticsearch from Kibana GUI or to configure Fluentd collector to insert data, elastic user/password need to be provided.

Password is stored in a kubernetes secret (`<efk_cluster_name>-es-elastic-user`). Execute this command for getting the password
```
kubectl get secret -n k3s-logging efk-es-elastic-user -o=jsonpath='{.data.elastic}' | base64 --decode; echo
```

Setting the password to a well known value is not an officially supported feature by ECK but a workaround exists by creating the {clusterName}-es-elastic-user Secret before the Elasticsearch resource (ECK operator).

Generate base64 encoded password 
```shell
echo -n 'supersecret' | base64
```

```yml
apiVersion: v1
kind: Secret
metadata: 
  name: efk-es-elastic-user
  namespace: k3s-logging
type: Opaque
data:
  elastic: <base64 encoded efk_elasticsearch_password>
```

#### Accesing Elasticsearch from outside the cluster

By default Elasticsearh HTTP service is accesible through Kubernetes `ClusterIP` service types (only available within the cluster). To make it available outside the cluster Traefik reverse-proxy can be configured to enable external communication with Elasicsearh server.

This can be useful for example if elasticsearh database have to be used to monitoring logs from servers outside the cluster(i.e: `gateway` node can be configured to send logs to the elasticsearch running in the cluster).

{{site.data.alerts.note}}

If log forwarder/aggregator architecture is deployed, this step can be skipped. In this case, fluentd-aggregator forward service is exposed by the cluster.

{{site.data.alerts.end}}

- Step 1. Create the ingress rule manifest
  
  ```yml
  ---
  # HTTPS Ingress
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: elasticsearch-ingress
    namespace: k3s-logging
    annotations:
      # HTTPS as entry point
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      # Enable TLS
      traefik.ingress.kubernetes.io/router.tls: "true"
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      cert-manager.io/cluster-issuer: ca-issuer
      cert-manager.io/common-name: elasticsearch.picluster.ricsanfre.com
  spec:
    tls:
      - hosts:
          - elasticsearch.picluster.ricsanfre.com
        secretName: elasticsearch-tls
    rules:
      - host: elasticsearch.picluster.ricsanfre.com
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: efk-es-http
                  port:
                    number: 9200
  ---
  # http ingress for http->https redirection
  kind: Ingress
  apiVersion: networking.k8s.io/v1
  metadata:
    name: elasticsearch-redirect
    namespace: k3s-logging
    annotations:
      # Use redirect Midleware configured
      traefik.ingress.kubernetes.io/router.middlewares: traefik-system-redirect@kubernetescrd
      # HTTP as entrypoint
      traefik.ingress.kubernetes.io/router.entrypoints: web
  spec:
    rules:
      - host: elasticsearch.picluster.ricsanfre.com
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: efk-es-http
                  port:
                    number: 9200
  ```
  
  Traefik ingress rule exposes elasticsearch server as `elasticsearch.picluster.ricsanfre.com` virtual host, routing rules are configured for redirecting all incoming HTTP traffic to HTTPS and TLS is enabled using a certificate generated by Cert-manager. 

  See [Traefik configuration document](/docs/traefik/) for furher details.

- Step 2: Apply manifest

  ```shell
  kubectl apply -f manifest.yml
  ```
- Step 3. Access to Elastic HTTP service

  UI can be access through http://elasticsearch.picluster.ricsanfre.com using loging `elastic` and the password stored in `<efk_cluster_name>-es-elastic-user`.

  It should shows the following output (json message)

  ```json
  {
    "name" : "efk-es-default-0",
    "cluster_name" : "efk",
    "cluster_uuid" : "w5BUxIY4SKOtxPUDQfb4lQ",
    "version" : {
      "number" : "8.1.2",
      "build_flavor" : "default",
      "build_type" : "docker",
      "build_hash" : "31df9689e80bad366ac20176aa7f2371ea5eb4c1",
      "build_date" : "2022-03-29T21:18:59.991429448Z",
      "build_snapshot" : false,
      "lucene_version" : "9.0.0",
      "minimum_wire_compatibility_version" : "7.17.0",
      "minimum_index_compatibility_version" : "7.0.0"
    },
    "tagline" : "You Know, for Search"
  }
  ```

### Kibana installation

- Step 1. Create a manifest file
  
  ```yml
  apiVersion: kibana.k8s.elastic.co/v1
  kind: Kibana
  metadata:
    name: kibana
    namespace: k3s-logging
  spec:
    version: 8.1.2
    count: 2 # Elastic Search statefulset deployment with two replicas
    elasticsearchRef:
      name: "elasticsearch"
    http:  # NOTE disabling kibana automatic TLS configuration
      tls:
        selfSignedCertificate:
          disabled: true
  ```
- Step 2: Apply manifest
  ```shell
  kubectl apply -f manifest.yml
  ```
- Step 3: Check kibana status
  ```shell
  kubectl get kibana -n k3s-logging
  NAME   HEALTH   NODES   VERSION   AGE
  efk    green    1       8.1.2    171m
  ```

  {{site.data.alerts.note}}

  Kibana status `HEALTH=green` indicates that Kibana is up and running.

  {{site.data.alerts.end}}
  
#### Ingress rule for Traefik

Make accesible Kibana UI from outside the cluster through Ingress Controller

- Step 1. Create the ingress rule manifest
  
  ```yml
  ---
  # HTTPS Ingress
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: kibana-ingress
    namespace: k3s-logging
    annotations:
      # HTTPS as entry point
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      # Enable TLS
      traefik.ingress.kubernetes.io/router.tls: "true"
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      cert-manager.io/cluster-issuer: ca-issuer
      cert-manager.io/common-name: kibana.picluster.ricsanfre.com
  spec:
    tls:
      - hosts:
          - kibana.picluster.ricsanfre.com
        secretName: kibana-tls
    rules:
      - host: kibana.picluster.ricsanfre.com
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: efk-kb-http
                  port:
                    number: 5601
  ---
  # http ingress for http->https redirection
  kind: Ingress
  apiVersion: networking.k8s.io/v1
  metadata:
    name: kibana-redirect
    namespace: k3s-logging
    annotations:
      # Use redirect Midleware configured
      traefik.ingress.kubernetes.io/router.middlewares: traefik-system-redirect@kubernetescrd
      # HTTP as entrypoint
      traefik.ingress.kubernetes.io/router.entrypoints: web
  spec:
    rules:
      - host: kibana.picluster.ricsanfre.com
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: efk-kb-http
                  port:
                    number: 5601
  ```
  
- Step 2: Apply manifest
  ```shell
  kubectl apply -f manifest.yml
  ```
- Step 3. Access to Kibana UI

  UI can be access through http://kibana.picluster.ricsanfre.com using loging `elastic` and the password stored in `<efk_cluster_name>-es-elastic-user`.


### Prometheus elasticsearh exporter installation

In order to monitor elasticsearch with prometheus, [prometheus-elasticsearch-exporter](https://github.com/prometheus-community/elasticsearch_exporter) need to be installed.

For doing the installation [prometheus-elasticsearch-exporter official helm](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-elasticsearch-exporter) will be used.

- Step 1: Add the prometheus community repository

  ```shell
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  ```
- Step2: Fetch the latest charts from the repository

  ```shell
  helm repo update
  ```

- Step 3: Create values.yml for configuring the helm chart

  ```yml
  ---
  # Elastic search user
  env:
    ES_USERNAME: elastic

  # Elastic search passord from secret
  extraEnvSecrets:
    ES_PASSWORD:
      secret: efk-es-elastic-user
      key: elastic

  # Elastic search URI
  es:
    uri: http://efk-es-http:9200
  ```

- Step 3: Install prometheus-elasticsearh-exporter in the logging namespace with the overriden values

  ```shell
  helm install -f values.yml prometheus-elasticsearch-exporter prometheus-community/prometheus-elasticsearch-exporter --namespace k3s-logging
  ```

When deployed, the exporter generates a Kubernetes Service exposing prometheus-elasticsearch-exporter metrics endpoint (port 9108).

It can be tested with the following command:

```shell
curl prometheus-elasticsearch-exporter.k3s-logging.svc.cluster.local:9108/metrics
# HELP elasticsearch_breakers_estimated_size_bytes Estimated size in bytes of breaker
# TYPE elasticsearch_breakers_estimated_size_bytes gauge
elasticsearch_breakers_estimated_size_bytes{breaker="eql_sequence",cluster="efk",es_client_node="true",es_data_node="true",es_ingest_node="true",es_master_node="true",host="10.42.2.20",name="efk-es-default-0"} 0
elasticsearch_breakers_estimated_size_bytes{breaker="fielddata",cluster="efk",es_client_node="true",es_data_node="true",es_ingest_node="true",es_master_node="true",host="10.42.2.20",name="efk-es-default-0"} 0
elasticsearch_breakers_estimated_size_bytes{breaker="inflight_requests",cluster="efk",es_client_node="true",es_data_node="true",es_ingest_node="true",es_master_node="true",host="10.42.2.20",name="efk-es-default-0"} 0
elasticsearch_breakers_estimated_size_bytes{breaker="model_inference",cluster="efk",es_client_node="true",es_data_node="true",es_ingest_node="true",es_master_node="true",host="10.42.2.20",name="efk-es-default-0"} 0
...
```

## Initial Kibana Setup (DataView configuration)

[Kibana's DataView](https://www.elastic.co/guide/en/kibana/master/data-views.html) must be configured in order to access Elasticsearch data.

- Step 1: Open Kibana UI

  Open a browser and go to Kibana's URL (kibana.picluster.ricsanfre.com)

- Step 2: Open "Management Menu"

  ![Kibana-setup-1](/assets/img/kibana-setup-1.png)

- Step 3: Select "Kibana - Data View" menu option and click on "Create data view"

  ![Kibana-setup-2](/assets/img/kibana-setup-2.png)

- Step 4: Set index pattern to fluentd-* and timestamp field to @timestamp and click on "Create Index" 

  ![Kibana-setup-3](/assets/img/kibana-setup-3.png)
