---
title: Log Analytics (Elasticsearch and Kibana)
permalink: /docs/elasticsearch/
description: How to deploy Elasticsearch and Kibana in our Pi Kuberentes cluster.
last_modified_at: "27-07-2023"

---

In June 2020, Elastic [announced](https://www.elastic.co/blog/elasticsearch-on-arm) that starting from 7.8 release they will provide multi-architecture docker images supporting AMD64 and ARM64 architectures.

To facilitate the deployment on a Kubernetes cluster [ECK project](https://github.com/elastic/cloud-on-k8s) was created.
ECK ([Elastic Cloud on Kubernetes](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)) automates the deployment, provisioning, management, and orchestration of ELK Stack (Elasticsearch, Kibana, APM Server, Enterprise Search, Beats, Elastic Agent, and Elastic Maps Server) on Kubernetes based on the operator pattern.

{{site.data.alerts.note}}
Logstash deployment is not supported by ECK operator
{{site.data.alerts.end}}

ECK Operator will be used to deploy Elasticsearh and Kibana.

## ECK Operator installation

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
  kubectl create namespace logging
  ```
- Step 3: Install ECK operator in the `logging` namespace
  ```shell
  helm install elastic-operator elastic/eck-operator --namespace logging
  ```
- Step 4: Monitor operator logs:
  ```shell
  kubectl -n logging logs -f statefulset.apps/elastic-operator
  ```

## Elasticsearch installation

Basic instructions can be found in [ECK Documentation: "Deploy and elasticsearch cluster"](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-deploy-elasticsearch.html)

- Step 1: Create a manifest file containing basic configuration: one node elasticsearch using Longhorn as storageClass and 5GB of storage in the volume claims.
  
  ```yml
  apiVersion: elasticsearch.k8s.elastic.co/v1
  kind: Elasticsearch
  metadata:
    name: efk
    namespace: logging
  spec:
    version: 8.1.2
    nodeSets:
    - name: default
      count: 1    # One node elastic search cluster
      config:
        node.store.allow_mmap: false # Disable memory mapping
      volumeClaimTemplates: 
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
  
  - About Virtual Memory configuration (mmap)

    By default, Elasticsearch uses memory mapping (`mmap`) to efficiently access indices. To disable this default mechanism add the following configuration option:

    ```yml
    node.store.allow_nmap: false
    ```
    Usually, default values for virtual address space on Linux distributions are too low for Elasticsearch to work properly, which may result in out-of-memory exceptions. This is why `mmap` is disable.

    For production workloads, it is strongly recommended to increase the kernel setting `vm.max_map_count` to 262144 and leave `node.store.allow_mmap` unset.

    See further details in [ECK Documentation: "Elastisearch Virtual Memory"](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-virtual-memory.html)

  - About Persistent Storage configuration

    Longhorn is configured for Elastisearch POD's persistent volumes

    ```yml
    volumeClaimTemplates:
      - metadata:
          name: elasticsearch-data
        spec:
          accessModes:
          - ReadWriteOnce
          resources:
            requests:
              storage: 5Gi
          storageClassName: longhorn
    ```

    See how to configure PersistenVolumeTemplates for Elasticsearh using this operator in [ECK Documentation: "Volume claim templates"](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-volume-claim-templates.html)


  - Disable TLS configuration


    ```yml
    http:
      tls:
        selfSignedCertificate:
          disabled: true

    ```

    By default ECK configures secured communications with auto-signed SSL certificates. Access to its service endpoint on port 9200 is only available through https.

    Disabling TLS automatic configuration in Elasticsearch HTTP server enables Linkerd (Cluster Service Mesh) to gather more statistics about connections. Linkerd is parsing plain text traffic (HTTP) instead of encrypted (HTTPS).
    
    Linkerd service mesh will enforce secure communications using TLS between all PODs.
  
  - About limiting resources assigned to ES

    In Kubernetes, limits in the consumption of resources (CPU and memory) can be assigned to PODs. See ["Kubernetes Doc - Resource Management for Pods and Containers"](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/).

    `resource requests` defines the minimum amount of resources that must be available for a Pod to be scheduled; `resource limits` defines the maximum amount of resources that a Pod is allowed to consume. 

    When you specify the `resource request` for containers in a Pod, the kube-scheduler uses this information to decide which node to place the Pod on. When you specify a `resource limit` for a container, the kubelet enforces those limits so that the running container is not allowed to use more of that resource than the limit you set. The kubelet also reserves at least the request amount of that system resource specifically for that container to use.

    In case of using ECK Operator is it recommended to specify those resource limits and resource request to each of the Objects created by the Operator.
    See details on how to setup those limits in [ECK Documentation - Manage compute resources](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-managing-compute-resources.html).

    For example memory heap assigned to JVM is calculated based on that resource limits, "The heap size of the JVM is automatically calculated based on the node roles and the available memory. The available memory is defined by the value of `resources.limits.memory` set on the elasticsearch container in the Pod template, or the available memory on the Kubernetes node is no limit is set".

    By default, ECK does not specify any limit to CPU resource and it defines `resources.limits.memory` for ElasticSearch POD set to 2GB.

    In production environment this default limit should be increased. In lab environments where memory resources are limited it can be decreased to reduce ES memory footprint.

    In both scenarios, the limit can be changed in in `Elasticsearch` object (`podTemplate` section).

    ```yml
      podTemplate:
        # Limiting Resources consumption
        spec:
          containers:
          - name: elasticsearch
            resources:
              requests:
                memory: 1Gi
              limits:
                memory: 1Gi

    ```

- Step 2: Apply manifest
  
  ```shell
  kubectl apply -f manifest.yml
  ```
- Step 3: Check Elasticsearch status
  
  ```shell
  kubectl get elasticsearch -n logging
  NAME   HEALTH   NODES   VERSION   PHASE   AGE
  efk    yellow   1       8.1.2    Ready   139m
  ```
   
  {{site.data.alerts.note}}

  Elasticsearch status `HEALTH=yellow` indicates that only one node of the Elasticsearch is running (no HA mechanism), `PHASE=Ready` indicates that the server is up and running

  {{site.data.alerts.end}}


### Elasticsearch authentication

By default ECK configures user authentication to access elasticsearch service. ECK defines a default admin esaticsearch user (`elastic`) and with a password which is stored within a kubernetes Secret.

Both to access elasticsearch from Kibana GUI or to configure Fluentd collector to insert data, elastic user/password need to be provided.

Password is stored in a kubernetes secret (`<efk_cluster_name>-es-elastic-user`). Execute this command for getting the password
```
kubectl get secret -n logging efk-es-elastic-user -o=jsonpath='{.data.elastic}' | base64 --decode; echo
```

Recently ECK has added support to define additional custom users and roles. Custom users are added [ES File-based Authentication](https://www.elastic.co/guide/en/elasticsearch/reference/current/file-realm.html).

See [Users and roles](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-users-and-roles.html) from elastic cloud-on-k8s documentation.

To allow fluentd and prometheus exporter to access our elasticsearch cluster, we can define two role that grants the necessary permission for the two users we will be creating (**fluentd, prometheus**).

- Step 1: Create Secrets containing roles definitions

  Fluentd user role:

  ```yml
  kind: Secret
  apiVersion: v1
  metadata:
    name: es-fluentd-roles-secret
    namespace: logging
  stringData:
    roles.yml: |-
      fluentd_role:
        cluster: ['manage_index_templates', 'monitor', 'manage_ilm']
        indices:
        - names: [ '*' ]
          privileges: [
            'indices:admin/create',
            'write',
            'create',
            'delete',
            'create_index',
            'manage',
            'manage_ilm'
          ]
  ```

  Prometheus Exporter user role:

  ```yml
  kind: Secret
  apiVersion: v1
  metadata:
    name: es-prometheus-roles-secret
    namespace: logging
  stringData:
    roles.yml: |-
      prometheus_role:
        cluster: [
          'cluster:monitor/health',
          'cluster:monitor/nodes/stats',
          'cluster:monitor/state',
          'cluster:monitor/nodes/info',
          'cluster:monitor/prometheus/metrics'
        ] 
        indices:
        - names: [ '*' ]
          privileges: [ 'indices:admin/aliases/get', 'indices:admin/mappings/get', 'indices:monitor/stats', 'indices:data/read/search' ]
  ```

- Step 2. Create the Secrets containing user name, password and mapped role

  Fluentd user:

  ```yml
  apiVersion: v1
  kind: Secret
  metadata:
    name: es-fluentd-user-file-realm
    namespace: logging
  type: kubernetes.io/basic-auth
  data:
    username: <`echo -n 'fluentd' | base64`>
    password: <`echo -n 'supersecret' | base64`>
    roles: <`echo -n 'fluentd_role' | base64`>
  ```

  Prometheus exporter user:

  ```yml
  apiVersion: v1
  kind: Secret
  metadata:
    name: es-prometheus-user-file-realm
    namespace: logging
  type: kubernetes.io/basic-auth
  data:
    username: <`echo -n 'prometheus' | base64`>
    password: <`echo -n 'supersecret' | base64`>
    roles: <`echo -n 'prometheus_role' | base64`>
  ```


- Step 3: Modify Elasticsearch yaml file created in step 1 of ES installation.

  Add the following lines to ElasticSearch manifest file:

  ```yml
  apiVersion: elasticsearch.k8s.elastic.co/v1
  kind: Elasticsearch
  metadata:
    name: efk
    namespace: logging
  spec:
    auth:
      roles:
      - secretName: es-fluentd-roles-secret
      - secretName: es-prometheus-roles-secret
      fileRealm:
      - secretName: es-fluentd-user-file-realm
      - secretName: es-prometheus-user-file-realm
  ...
  ```

In addition to the `elastic` user we can also create an super user account for us to login, we can create the account just like how we created the `fluentd` or `prometheus` user, but instead with the role set to `superuser`.

### Accesing Elasticsearch from outside the cluster

By default Elasticsearh HTTP service is accesible through Kubernetes `ClusterIP` service types (only available within the cluster). To make it available outside the cluster Ingress NGINX can be configured to enable external communication with Elasicsearh server.

This exposure will be useful for doing remote configurations on Elasticsearch through its API from `pimaster` node. For example: to configure backup snapshots.

- Step 1. Create the ingress rule manifest
  
  ```yml
  ---
  # HTTPS Ingress
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: elasticsearch-ingress
    namespace: logging
    annotations:
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      cert-manager.io/cluster-issuer: ca-issuer
      cert-manager.io/common-name: elasticsearch.picluster.ricsanfre.com
  spec:
    ingressClassName: nginx
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
  ```
  
  ingress NGINX exposes elasticsearch server as `elasticsearch.picluster.ricsanfre.com` virtual host, routing rules are configured for redirecting all incoming HTTP traffic to HTTPS and TLS is enabled using a certificate generated by Cert-manager. 

  See [Ingress NGINX configuration document](/docs/nginx/) for furher details.

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

## Kibana installation

- Step 1. Create a manifest file
  
  ```yml
  apiVersion: kibana.k8s.elastic.co/v1
  kind: Kibana
  metadata:
    name: kibana
    namespace: logging
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
  kubectl get kibana -n logging
  NAME   HEALTH   NODES   VERSION   AGE
  efk    green    1       8.1.2    171m
  ```

  {{site.data.alerts.note}}

  Kibana status `HEALTH=green` indicates that Kibana is up and running.

  {{site.data.alerts.end}}
  
### Ingress rule for Kibana

Make accesible Kibana UI from outside the cluster through Ingress Controller

- Step 1. Create the ingress rule manifest
  
  ```yml
  ---
  # HTTPS Ingress
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: kibana-ingress
    namespace: logging
    annotations:
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      cert-manager.io/cluster-issuer: ca-issuer
      cert-manager.io/common-name: kibana.picluster.ricsanfre.com
  spec:
    ingressClassName: nginx
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
  ```
  
- Step 2: Apply manifest
  ```shell
  kubectl apply -f manifest.yml
  ```
- Step 3. Access to Kibana UI

  UI can be access through http://kibana.picluster.ricsanfre.com using loging `elastic` and the password stored in `<efk_cluster_name>-es-elastic-user`.

### Initial Kibana Setup (DataView configuration)

[Kibana's DataView](https://www.elastic.co/guide/en/kibana/master/data-views.html) must be configured in order to access Elasticsearch data.

{{site.data.alerts.note}}
This configuration must be done once data from fluentd has been inserted in ES: A index (`fluentd-<date>`) containing  data has been created.
{{site.data.alerts.end}}

- Step 1: Open Kibana UI

  Open a browser and go to Kibana's URL (kibana.picluster.ricsanfre.com)

- Step 2: Open "Management Menu"

  ![Kibana-setup-1](/assets/img/kibana-setup-1.png)

- Step 3: Select "Kibana - Data View" menu option and click on "Create data view"

  ![Kibana-setup-2](/assets/img/kibana-setup-2.png)

- Step 4: Set index pattern to fluentd-* and timestamp field to @timestamp and click on "Create Index" 

  ![Kibana-setup-3](/assets/img/kibana-setup-3.png)

## Prometheus elasticsearh exporter installation

In order to monitor elasticsearch with prometheus, [prometheus-elasticsearch-exporter](https://github.com/prometheus-community/elasticsearch_exporter) need to be installed.

For doing the installation [prometheus-elasticsearch-exporter official helm](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-elasticsearch-exporter) will be used.

- Step 1: Add the prometheus community repository

  ```shell
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  ```
- Step 2: Fetch the latest charts from the repository

  ```shell
  helm repo update
  ```

- Step 3: Create values.yml for configuring the helm chart

  ```yml
  ---
  # Elastic search password from secret
  extraEnvSecrets:
    ES_USERNAME:
      secret: es-prometheus-user-file-realm
      key: username
    ES_PASSWORD:
      secret: es-prometheus-user-file-realm
      key: password


  # Elastic search URI
  es:
    uri: http://efk-es-http:9200
  ```
  
  This config passes ElasticSearch API endpoint (`uri`) and the needed credentials through environement variables(`ES_USERNAME` and `ES_PASSWORD`). The `es-prometheus-user-file-realm` secret was created above when in [Elasticsearch authentication](#elasticsearch-authentication)

- Step 3: Install prometheus-elasticsearh-exporter in the logging namespace with the overriden values

  ```shell
  helm install -f values.yml prometheus-elasticsearch-exporter prometheus-community/prometheus-elasticsearch-exporter --namespace logging
  ```

When deployed, the exporter generates a Kubernetes Service exposing prometheus-elasticsearch-exporter metrics endpoint (/metrics on port 9108).

It can be tested with the following command:

```shell
curl prometheus-elasticsearch-exporter.logging.svc.cluster.local:9108/metrics
# HELP elasticsearch_breakers_estimated_size_bytes Estimated size in bytes of breaker
# TYPE elasticsearch_breakers_estimated_size_bytes gauge
elasticsearch_breakers_estimated_size_bytes{breaker="eql_sequence",cluster="efk",es_client_node="true",es_data_node="true",es_ingest_node="true",es_master_node="true",host="10.42.2.20",name="efk-es-default-0"} 0
elasticsearch_breakers_estimated_size_bytes{breaker="fielddata",cluster="efk",es_client_node="true",es_data_node="true",es_ingest_node="true",es_master_node="true",host="10.42.2.20",name="efk-es-default-0"} 0
elasticsearch_breakers_estimated_size_bytes{breaker="inflight_requests",cluster="efk",es_client_node="true",es_data_node="true",es_ingest_node="true",es_master_node="true",host="10.42.2.20",name="efk-es-default-0"} 0
elasticsearch_breakers_estimated_size_bytes{breaker="model_inference",cluster="efk",es_client_node="true",es_data_node="true",es_ingest_node="true",es_master_node="true",host="10.42.2.20",name="efk-es-default-0"} 0
...
```
