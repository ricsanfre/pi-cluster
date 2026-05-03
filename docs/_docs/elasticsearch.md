---
title: Log Analytics (Elasticsearch and Kibana)
permalink: /docs/elasticsearch/
description: How to deploy Elasticsearch and Kibana in our Pi Kubernetes cluster.
last_modified_at: "27-03-2026"

---

[Elastic Cloud on Kubernetes (ECK) Operator](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html) is an implementation of Kubernetes Operator design pattern for deploying Elastic stack applications: ElasticSearch, Kibana, Logstash and other applications from Elastic ecosystem.


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
  kubectl create namespace elastic
  ```
- Step 3: Install ECK operator in the `elastic` namespace
  ```shell
  helm install elastic-operator elastic/eck-operator --namespace elastic
  ```
- Step 4: Monitor operator logs:
  ```shell
  kubectl -n elastic logs -f statefulset.apps/elastic-operator
  ```

## Elasticsearch installation

Basic instructions can be found in [ECK Documentation: "Deploy and elasticsearch cluster"](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-deploy-elasticsearch.html)

-   Step 1: Create a manifest file containing basic configuration: one node elasticsearch using Longhorn as storageClass and 5GB of storage in the volume claims.
  
    ```yml
    apiVersion: elasticsearch.k8s.elastic.co/v1
    kind: Elasticsearch
    metadata:
      name: efk
      namespace: elastic
    spec:
      version: 8.15.0
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
              storageClassName: ${STORAGE_CLASS}
      http:
        tls: # Disabling TLS automatic configuration.
          selfSignedCertificate:
            disabled: true

    ```

    {{site.data.alerts.note}}

    Substitute variables (`${var}`) in the above yaml file before deploying mangifest file.
    -   Replace `${STORAGE_CLASS}` by storage class name used (i.e. `longhorn`, `local-path`, etc.)

    {{site.data.alerts.end}}
  
    -   About Virtual Memory configuration (mmap)

        By default, Elasticsearch uses memory mapping (`mmap`) to efficiently access indices. To disable this default mechanism add the following configuration option:

        ```yml
        node.store.allow_nmap: false
        ```
        Usually, default values for virtual address space on Linux distributions are too low for Elasticsearch to work properly, which may result in out-of-memory exceptions. This is why `mmap` is disable.

        For production workloads, it is strongly recommended to increase the kernel setting `vm.max_map_count` to 262144 and leave `node.store.allow_mmap` unset.

        See further details in [ECK Documentation: "Elastisearch Virtual Memory"](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-virtual-memory.html)

    -   About Persistent Storage configuration

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
              storageClassName: ${STORAGE_CLASS}
        ```

        See how to configure PersistenVolumeTemplates for Elasticsearh using this operator in [ECK Documentation: "Volume claim templates"](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-volume-claim-templates.html)


    -   Disable TLS configuration

        ```yml
        http:
          tls:
            selfSignedCertificate:
              disabled: true
        ```

        By default ECK configures secured communications with auto-signed SSL certificates. Access to its service endpoint on port 9200 is only available through https.

        Disabling TLS automatic configuration in Elasticsearch HTTP server enables Cluster Service Mesh to gather more statistics about connections. Service Mesh is parsing plain text traffic (HTTP) instead of encrypted (HTTPS).
        
        Cluster service mesh will enforce secure communications using TLS between all PODs.
  
    -   About limiting resources assigned to ES

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

-   Step 2: Apply manifest
  
    ```shell
    kubectl apply -f manifest.yml
    ```
-   Step 3: Check Elasticsearch status
  
    ```shell
    kubectl get elasticsearch -n elastic
    NAME   HEALTH   NODES   VERSION   PHASE   AGE
    efk    green   1       8.15.0    Ready   139m
    ```
    
    {{site.data.alerts.note}}

    Elasticsearch status `HEALTH=green` indicates that Elasticsearch is running and healthy, `PHASE=Ready` indicates that the server is up and running

    {{site.data.alerts.end}}


### Elasticsearch authentication

By default ECK configures user authentication to access elasticsearch service. ECK defines a default admin esaticsearch user (`elastic`) and with a password which is stored within a kubernetes Secret.

Both to access elasticsearch from Kibana GUI or to configure Fluentd collector to insert data, elastic user/password need to be provided.

Password is stored in a kubernetes secret (`<efk_cluster_name>-es-elastic-user`). Execute this command for getting the password
```
kubectl get secret -n elastic efk-es-elastic-user -o=jsonpath='{.data.elastic}' | base64 --decode; echo
```
#### File-based Authentication

ECK has the capability to define additional custom users and roles. Custom users are added using [ES File-based Authentication](https://www.elastic.co/docs/deploy-manage/users-roles/cluster-or-deployment-auth/file-based). Custom roles can also be added using [ES file-based roles](https://www.elastic.co/docs/deploy-manage/users-roles/cluster-or-deployment-auth/defining-roles#roles-management-file)

{{site.data.alerts.important}}

Users/roles including in  `file` realm cannot be managed using the [user APIs](https://www.elastic.co/docs/api/doc/elasticsearch/group/endpoint-security), or using the Kibana **Management > Security > Users/Roles** pages. File based used/roles are defined at ES node level. All nodes of a cluster should have same users/roles configured. ECK operator guarantees that all nodes of the cluster have the same file-based users/roles.

{{site.data.alerts.end}}

See [Users and roles](https://www.elastic.co/guide/en/cloud-on-k8s/2.16/k8s-users-and-roles.html) from elastic cloud-on-k8s documentation.

To allow fluentd and prometheus exporter to access our elasticsearch cluster, we can define two role that grants the necessary permission for the two users we will be creating (**fluentd, prometheus**).

- Step 1: Create Secrets containing roles definitions

  Fluentd user role:

  ```yml
  kind: Secret
  apiVersion: v1
  metadata:
    name: es-fluentd-roles-secret
    namespace: elastic
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
    namespace: elastic
  stringData:
    roles.yml: |-
      prometheus_role:
        cluster: [
          'monitor',
          'monitor_snapshot'
        ] 
        indices:
        - names: [ '*' ]
          privileges: [ 'monitor', 'view_index_metadata' ]
  ```

- Step 2. Create the Secrets containing user name, password and mapped role

  Fluentd user:

  ```yml
  apiVersion: v1
  kind: Secret
  metadata:
    name: es-fluentd-user-file-realm
    namespace: elastic
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
    namespace: elastic
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
    namespace: elastic
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

By default Elasticsearh HTTP service is accessible through Kubernetes `ClusterIP` service types (only available within the cluster). In Pi Cluster it is exposed externally through Envoy Gateway using a Kubernetes Gateway API `HTTPRoute`.

This exposure will be useful for doing remote configurations on Elasticsearch through its API from `pimaster` node. For example: to configure backup snapshots.

- Step 1. Create the `HTTPRoute` manifest
  
  ```yml
  apiVersion: gateway.networking.k8s.io/v1
  kind: HTTPRoute
  metadata:
    name: elasticsearch
    namespace: elastic
  spec:
    parentRefs:
      - name: public-gateway
        namespace: envoy-gateway-system
    hostnames:
      - elasticsearch.${CLUSTER_DOMAIN}
    rules:
      - backendRefs:
          - name: efk-es-http
            port: 9200
  ```

  {{site.data.alerts.note}}

  Substitute variables (`${var}`) in the above yaml file before deploying manifest.
  -   Replace `${CLUSTER_DOMAIN}` by the domain name used in the cluster. For example: `homelab.ricsanfre.com`.

  Envoy Gateway exposes Elasticsearch as `elasticsearch.${CLUSTER_DOMAIN}` through the shared `public-gateway` `Gateway`. TLS is terminated at the Gateway using the wildcard certificate managed for Envoy Gateway.

  See ["Envoy Gateway - Gateway and TLS termination"](/docs/envoy-gateway/#gateway-and-tls-termination) for details.

  External-DNS can automatically create a DNS entry from the `HTTPRoute` hostname when Gateway API route sources are enabled. See ["DNS (CoreDNS and External-DNS) - Gateway API support"](/docs/kube-dns/#gateway-api-support).

  {{site.data.alerts.end}}
  

- Step 2: Apply manifest

  ```shell
  kubectl apply -f manifest.yml
  ```
- Step 3. Access to Elastic HTTP service

  Elasticsearch HTTP endpoint can be accessed through `https://elasticsearch.${CLUSTER_DOMAIN}` using login `elastic` and the password stored in `<efk_cluster_name>-es-elastic-user`.

  It should shows the following output (json message)

  ```json
  {
    "name" : "efk-es-default-0",
    "cluster_name" : "efk",
    "cluster_uuid" : "WTb_fupJRl27biWOnJY5tQ",
    "version" : {
      "number" : "8.15.0",
      "build_flavor" : "default",
      "build_type" : "docker",
      "build_hash" : "1a77947f34deddb41af25e6f0ddb8e830159c179",
      "build_date" : "2024-08-05T10:05:34.233336849Z",
      "build_snapshot" : false,
      "lucene_version" : "9.11.1",
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
    namespace: elastic
  spec:
    version: 8.15.0
    count: 1
    elasticsearchRef:
      name: "efk"
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
  kubectl get kibana -n elastic
  NAME   HEALTH   NODES   VERSION   AGE
  efk    green    1       8.15.0    171m
  ```

  {{site.data.alerts.note}}

  Kibana status `HEALTH=green` indicates that Kibana is up and running.

  {{site.data.alerts.end}}
  
### Gateway API route for Kibana

Make Kibana UI accessible from outside the cluster through Envoy Gateway.

- Step 1. Create the `HTTPRoute` manifest
  
  ```yml
  apiVersion: gateway.networking.k8s.io/v1
  kind: HTTPRoute
  metadata:
    name: kibana
    namespace: elastic
  spec:
    parentRefs:
      - name: public-gateway
        namespace: envoy-gateway-system
    hostnames:
      - kibana.${CLUSTER_DOMAIN}
    rules:
      - backendRefs:
          - name: efk-kb-http
            port: 5601
  ```

  {{site.data.alerts.note}}

  Substitute variables (`${var}`) in the above yaml file before deploying manifest.
  -   Replace `${CLUSTER_DOMAIN}` by the domain name used in the cluster. For example: `homelab.ricsanfre.com`.

  Envoy Gateway exposes Kibana as `kibana.${CLUSTER_DOMAIN}` through the shared `public-gateway` `Gateway`. TLS is terminated at the Gateway using the wildcard certificate managed for Envoy Gateway.

  See ["Envoy Gateway - Gateway and TLS termination"](/docs/envoy-gateway/#gateway-and-tls-termination) for details.

  External-DNS can automatically create a DNS entry from the `HTTPRoute` hostname when Gateway API route sources are enabled. See ["DNS (CoreDNS and External-DNS) - Gateway API support"](/docs/kube-dns/#gateway-api-support).

  {{site.data.alerts.end}}
  
- Step 2: Apply manifest
  ```shell
  kubectl apply -f manifest.yml
  ```
- Step 3. Access to Kibana UI

  UI can be accessed through `https://kibana.${CLUSTER_DOMAIN}` using login `elastic` and the password stored in `<efk_cluster_name>-es-elastic-user`.

  Execute the following command to get `elastic` user password

  ```shell
  kubectl get secret efk-es-elastic-user -o jsonpath='{.data.elastic}' -n elastic | base64 -d;echo
  ```

### Initial Kibana Setup (DataView configuration)

[Kibana's DataView](https://www.elastic.co/guide/en/kibana/master/data-views.html) must be configured in order to access Elasticsearch data.

{{site.data.alerts.note}}

This configuration must be done once data from fluentd has been inserted in ES: A index (`fluentd-*`) containing  data has been created.

{{site.data.alerts.end}}

-   Step 1: Open Kibana UI

    Open a browser and go to Kibana's URL (kibana.picluster.ricsanfre.com)

-   Step 2: Open "Management Menu"

    ![Kibana-setup-1](/assets/img/kibana-setup-1.png)

-   Step 3: Select "Kibana - Data View" menu option and click on "Create data view"

    ![Kibana-setup-2](/assets/img/kibana-setup-2.png)

-   Step 4: Set index pattern to fluentd-* and timestamp field to @timestamp and click on "Create Index" 

    ![Kibana-setup-3](/assets/img/kibana-setup-3.png)

#### Automation using API

Kibana's dataview can be automatically creatred using [Kibana's API DataView endpoint](https://www.elastic.co/guide/en/kibana/current/data-views-api-create.html).

A Kubernetes Job can be created to automatically invoke API to create the required API.

The following configMap contains two scripts to be executed by the Job:

-  `wait-for-kibana.sh`: it test the connection to Kibana, and wait till Kibana is available
-  `create-data-view.sh`: Create a Dataview using Kibana API.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kibana-config-data
data:
  wait-for-kibana.sh: |
    #!/bin/sh
    # Wait for Kibana to be available & healthy
    echo "Testing connection to Kibana"
    until $(curl -k -X GET http://$KIBANA_URL:$KIBANA_PORT/_cluster/health); do sleep 5; done
    until [ "$(curl -k -X GET http://$KIBANA_URL:$KIBANA_PORT/_cluster/health | wc -l)" == "0" ]
    do sleep 5
    done

  create-data-view.sh: |
    #!/bin/sh
    #Import data view
    echo "Importing data_view..."
    curl -u elastic:$ELASTICSEARCH_PASSWORD \
    -X POST http://$KIBANA_URL:$KIBANA_PORT/api/data_views/data_view \
    -H 'Content-Type: application/json; Elastic-Api-Version=2023-10-31' \
    -H 'kbn-xsrf: string' \
    -d '
    {
      "data_view": {
        "name": "fluentd",
        "title": "fluentd-*",
        "timeFieldName": "@timestamp"
      }
    }
    '
```

The Job is the following:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: kibana-config-job
spec:
  parallelism: 1
  completions: 1
  template:
    spec:
      restartPolicy: Never
      initContainers:
        - name: wait-for-kibana
          image: alpine/curl:latest
          imagePullPolicy: IfNotPresent
          env:
          - name: KIBANA_URL
            value: efk-kb-http
          - name: KIBANA_PORT
            value: "5601"
          command: ["/bin/sh","/kibana/wait-for-kibana.sh"]
          volumeMounts:
          - name: kibana-config-data
            mountPath: /kibana/
      containers:
        - name: kibana-config-job
          image: alpine/curl:latest
          env:
            - name: ELASTICSEARCH_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: efk-es-elastic-user
                  key: elastic
            - name: KIBANA_URL
              value: efk-kb-http
            - name: KIBANA_PORT
              value: "5601"
          command: ["/bin/sh","/kibana/create-data-view.sh"]
          volumeMounts:
          - name: kibana-config-data
            mountPath: /kibana/
      volumes:
      - name: kibana-config-data
        configMap:
          name: kibana-config-data
          defaultMode: 0777
```

## Configuring ElasticStack

### Automating configuration with Terraform and Flux Tofu Controller

As an alternative to manual API calls, ElasticStack configuration can be managed with OpenTofu/Terraform.

This repository already includes an Elastic Terraform module to configure Elasticsearch and Kibana resources (roles, users, ILM policies, templates, and dataviews) in a declarative way. The module can be executed manually or automatically with Flux Tofu Controller.

Module: [`terraform/elastic/`]({{ site.github.repository_url }}/tree/master/terraform/elastic)

Providers used in the module:

- ElasticStack provider: [elastic/elasticstack (OpenTofu Registry)](https://search.opentofu.org/provider/elastic/elasticstack/latest)
- Vault provider: [hashicorp/vault (OpenTofu Registry)](https://search.opentofu.org/provider/hashicorp/vault/latest)
- Kubernetes provider: [hashicorp/kubernetes (OpenTofu Registry)](https://search.opentofu.org/provider/hashicorp/kubernetes/latest)

The Terraform module manages ElasticStack resources from JSON files in `terraform/elastic/resources/`.

JSON schema and examples are documented in [`terraform/elastic/JSON_FORMAT_GUIDE.md`]({{ site.github.repository_url }}/blob/master/terraform/elastic/JSON_FORMAT_GUIDE.md).

- `roles/*.json`
- `users/*.json`
- `policies/*.json`
- `template_components/*.json`
- `templates/*.json`
- `dataviews/*.json`

#### Vault Provider

The module authenticates to Vault using the [hashicorp/vault provider (OpenTofu Registry)](https://search.opentofu.org/provider/hashicorp/vault/latest) and supports two execution modes:

1. Direct/local execution (`tofu_controller_execution=false`):
   - Uses `vault_token`.
2. In-cluster Tofu Controller execution (`tofu_controller_execution=true`):
   - Uses Kubernetes auth login (`vault_kubernetes_auth_login_path`, default `auth/kubernetes/login`).
   - Uses Vault role `vault_kubernetes_auth_role` (in this repo, `tf-runner`).
   - Uses service account token from `kubernetes_token_file` (default `/var/run/secrets/kubernetes.io/serviceaccount/token`).

The module reads users credentials from Vault KV v2 (`vault_kv2_path`, default `secret`) using `vault_secret_key` in each file under `resources/users/*.json`.

#### Automating with Tofu Controller

The Terraform module can be automatically reconciled by Flux Tofu Controller, which executes the Terraform code and applies the configuration to Elasticsearch and Kibana.

For general controller installation and operational concepts, see [Flux Tofu Controller Usage](/docs/fluxcd/#flux-tofu-controller-usage).

Tofu Controller resource used in this repository:

- Flux Terraform CR: `kubernetes/platform/elastic-stack/config/base/terraform.yaml`

##### How it works

1. Flux source-controller publishes the Git artifact.
2. Tofu Controller reconciles the `Terraform` custom resource.
3. The module authenticates to Vault using Kubernetes auth role `tf-runner`.
4. The module reads user passwords from Vault and applies Elasticsearch/Kibana configuration declaratively.

Example `Terraform` custom resource (already present in this repo):

```yaml
apiVersion: infra.contrib.fluxcd.io/v1alpha2
kind: Terraform
metadata:
  name: config-elastic
spec:
  interval: 30m
  approvePlan: auto
  destroyResourcesOnDeletion: true
  path: ./terraform/elastic
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  vars:
    - name: tofu_controller_execution
      value: "true"
    - name: vault_address
      value: "https://vault.${CLUSTER_DOMAIN}:8200"
    - name: vault_kubernetes_auth_login_path
      value: "auth/kubernetes/login"
    - name: vault_kubernetes_auth_role
      value: "tf-runner"
    - name: elasticsearch_endpoint
      value: "http://efk-es-http.elastic.svc:9200"
    - name: kibana_endpoint
      value: "http://efk-kb-http.elastic.svc:5601"
```

#### Operational workflow

1. Edit JSON files under `terraform/elastic/resources/`.
2. Commit and push changes to the Git branch watched by Flux.
3. Reconcile and verify:

```shell
flux reconcile terraform config-elastic -n flux-system
kubectl -n flux-system get terraform config-elastic
kubectl -n flux-system describe terraform config-elastic
```

{{site.data.alerts.note}}
Prerequisite: Vault Kubernetes auth must include the `tf-runner` role bound to the Tofu runner service account in `flux-system`, and policies must allow reading all secrets required by the Elastic Terraform module.

For the actual `tf-runner` Vault role/policy configuration and CLI snippets, see [Flux Tofu Controller: Vault access from tf-runner (Kubernetes auth)](/docs/fluxcd/#vault-access-from-tf-runner-kubernetes-auth).
{{site.data.alerts.end}}

## Observability

### Metrics

#### Prometheus Integration via Elasticsearh exporter

In order to monitor elasticsearch with prometheus, [prometheus-elasticsearch-exporter](https://github.com/prometheus-community/elasticsearch_exporter) need to be installed.

For doing the installation [prometheus-elasticsearch-exporter official helm](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-elasticsearch-exporter) will be used.

-   Step 1: Add the prometheus community repository

    ```shell
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    ```
-   Step 2: Fetch the latest charts from the repository

    ```shell
    helm repo update
    ```

-   Step 3: Create values.yml for configuring the helm chart

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
    
    # Enable Service Monitor
    serviceMonitor:
      ## If true, a ServiceMonitor CRD is created for a prometheus operator
      ## https://github.com/coreos/prometheus-operator
      ##
      enabled: true
    
    ```
  
  This config passes ElasticSearch API endpoint (`uri`) and the needed credentials through environement variables(`ES_USERNAME` and `ES_PASSWORD`). The `es-prometheus-user-file-realm` secret was created in section [Elasticsearch authentication](#elasticsearch-authentication).

-   Step 3: Install prometheus-elasticsearh-exporter in the `elastic` namespace with the overriden values

    ```shell
    helm install -f values.yml prometheus-elasticsearch-exporter prometheus-community/prometheus-elasticsearch-exporter --namespace elastic
    ```

When deployed, the exporter generates a Kubernetes Service exposing prometheus-elasticsearch-exporter metrics endpoint (/metrics on port 9108) 

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

#### Integration with Kube-prom-stack

Providing `serviceMonitor.enabled: true` to the helm chart `values.yaml` file, corresponding Prometheus Operator's resource, `ServiceMonitor`, so Kube-Prometheus-Stack can automatically start scraping metrics form this endpoint

#### Grafana Dashboards

See [Grafana Operator - Provisioning Dashboards](/docs/grafana-operator/#provisioning-dashboards) for the general `GrafanaDashboard` onboarding patterns.

Elasticsearh exporter dashboard sample can be donwloaded from [prometheus-elasticsearh-exporter repo](https://github.com/prometheus-community/elasticsearch_exporter/blob/master/examples/grafana/dashboard.json).

The dashboard can be onboarded with a `GrafanaDashboard` resource:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: elasticsearch
spec:
  allowCrossNamespaceImport: true
  folder: Infrastructure
  instanceSelector:
    matchLabels:
      dashboards: grafana
  url: https://raw.githubusercontent.com/prometheus-community/elasticsearch_exporter/master/elasticsearch-mixin/compiled/dashboards/cluster.json
```