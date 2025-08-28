---
title: Kafka
permalink: /docs/kafka/
description: How to deploy Kafka to our Kubernetes cluster. Using Strimzi Kafka Operator to streamline the deployment
last_modified_at: "28-08-2025"

---

## Kafka Cluster installation

For the installation [Strimzi](https://strimzi.io/) kafka operator will be used to deploy a Kafka cluster.

### Strimzi Operator installation procedure using Helm

Installation using `Helm` (Release 3):

- Step 1: Add the Strimzi Helm repository:

  ```shell
  helm repo add strimzi https://strimzi.io/charts/
  ```
- Step2: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```
- Step 3: Create namespace

  ```shell
  kubectl create namespace kafka
  ```
- Step 3: Install Strimzi kafka operator

  ```shell
  helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator --namespace kafka
  ```
- Step 4: Confirm that the deployment succeeded, run:

  ```shell
  kubectl -n kafka get pod
  ```

### Deploy Kafka cluster

Using Strimzi operator, Kafka cluster in KRaft mode can be deployed.

-   Step 1: Create a Kafka cluster of 3 nodes with dual roles (Kraft controller/ Kafka broker),configure its storage (5gb) and create a Kafka cluster from that pool broker using a specific Kafka release.
  
    ```yaml
    ---
    apiVersion: kafka.strimzi.io/v1beta2
    kind: KafkaNodePool
    metadata:
      name: dual-role
      labels:
        strimzi.io/cluster: my-cluster
    spec:
      replicas: 3
      roles:
        - controller
        - broker
      storage:
        type: jbod
        volumes:
          - id: 0
            type: persistent-claim
            size: 5Gi
            class: longhorn
            deleteClaim: false
            kraftMetadata: shared
    ---
    apiVersion: kafka.strimzi.io/v1beta2
    kind: Kafka
    metadata:
      name: my-cluster
      annotations:
        strimzi.io/node-pools: enabled
        strimzi.io/kraft: enabled
    spec:
      kafka:
        version: 4.0.0
        metadataVersion: 4.0-IV3
        listeners:
          - name: plain
            port: 9092
            type: internal
            tls: false
          - name: tls
            port: 9093
            type: internal
            tls: true
        config:
          offsets.topic.replication.factor: 3
          transaction.state.log.replication.factor: 3
          transaction.state.log.min.isr: 2
          default.replication.factor: 3
          min.insync.replicas: 2
      entityOperator:
        topicOperator: {}
        userOperator: {}
    ```


-   Step 2: Apply manifest
  
    ```shell
    kubectl apply -f manifest.yml
    ```
-   Step 3: Check Kafka status
  
    ```shell
    kubectl get kafka -n kafka
    NAME         DESIRED KAFKA REPLICAS   DESIRED ZK REPLICAS   READY   WARNINGS
    my-cluster   3                        3                     True
    ```

{{site.data.alerts.note}}

By default, intra-broker communication is encrypted with TLS.

{{site.data.alerts.end}}


### Create Topic

- Step 1: Create a manifest file `topic.yaml`

  ```yml
  apiVersion: kafka.strimzi.io/v1beta2
  kind: KafkaTopic
  metadata:
    name: my-topic
    labels:
      strimzi.io/cluster: my-cluster
  spec:
    partitions: 1
    replicas: 3
    config:
      retention.ms: 7200000
      segment.bytes: 1073741824
  ``` 

- Step 2: Apply manifest
  
  ```shell
  kubectl apply -f topic.yml
  ```
- Step 3: Check Kafka topic status

  ```shell
  kubectl get kafkatopic my-topic -n kafka
  NAME       CLUSTER      PARTITIONS   REPLICATION FACTOR   READY
  my-topic   my-cluster   1            1                    True
  ```
  
### Testing Kafka cluster

Once the cluster is running, you can run a simple producer to send messages to a Kafka topic (the topic will be automatically created).

- Step 1: launch producer
  ```shell
  kubectl -n kafka run kafka-producer -ti --image=quay.io/strimzi/kafka:0.29.0-kafka-3.2.0 --rm=true --restart=Never -- bin/kafka-console-producer.sh --bootstrap-server my-cluster-kafka-bootstrap:9092 --topic my-topic
  ```

- Step 3: in a different terminal launch consumer
  ```shell
  kubectl -n kafka run kafka-consumer -ti --image=quay.io/strimzi/kafka:0.29.0-kafka-3.2.0 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server my-cluster-kafka-bootstrap:9092 --topic my-topic --from-beginning
  ```

- Step 5: In producer terminal wait for the prompt and start typing messages. (Input Control-C to finish)

  Messages will be outputed in consumer terminal.

### Observability

#### Metrics

Kafka can be configured to generate Prometheus metrics using an external exporters (Prometheus JMX Exporter and Kafka Exporter).

##### Prometheus JMX Exporter
[Prometheus JMX Exporter](https://github.com/prometheus/jmx_exporter) is a collector of JMX metrics and exposes them via HTTP for Prometheus consumption.

Kafka generates JMX metrics that can be collected by Prometheus JMX Exporter. The JMX Exporter runs as a Java agent within the Kafka broker process, exposing JMX metrics on an HTTP endpoint.

##### Prometheus Kafka Exporter

Kafka exposed metrics via JMX are not sufficient to monitor Kafka brokers and clients.

[Kafka Exporter](https://github.com/danielqsj/kafka_exporter) is an open source project to enhance monitoring of Apache Kafka brokers and clients. It collects and exposes additional metrics related to Kafka consumer groups, consumer lags, topics, partitions, and offsets.


##### Strimzi Operator

Strimzi provides built-in support for JMX Exporter and Kafka Exporter.

When creating Kafka Cluster using Strimzi Operator, JMX Exporter and Kafka Exporter can be enabled by adding the following configuration to the Kafka manifest file:


```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: cluster
spec:
  kafka:
    # ...
    # Configure JMX Exporter
    metricsConfig:
      type: jmxPrometheusExporter
      valueFrom:
        configMapKeyRef:
          name: kafka-metrics
          key: kafka-metrics-config.yml
  # Enable Kafka Exporter
  kafkaExporter:
    topicRegex: ".*"
    groupRegex: ".*"

```

Prometheus JMX Exporter configuration file must be provided in a ConfigMap named `kafka-metrics` in the same namespace as the Kafka cluster.
This files contains rules for mapping JMX metrics to Prometheus metrics. The following is a sample confguration provided by Strimzi that can be used as a starting point:

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: kafka-metrics
  labels:
    app: strimzi
data:
  kafka-metrics-config.yml: |
    # See https://github.com/prometheus/jmx_exporter for more info about JMX Prometheus Exporter metrics
    lowercaseOutputName: true
    rules:
    # Special cases and very specific rules
    - pattern: kafka.server<type=(.+), name=(.+), clientId=(.+), topic=(.+), partition=(.*)><>Value
      name: kafka_server_$1_$2
      type: GAUGE
      labels:
        clientId: "$3"
        topic: "$4"
        partition: "$5"
    - pattern: kafka.server<type=(.+), name=(.+), clientId=(.+), brokerHost=(.+), brokerPort=(.+)><>Value
      name: kafka_server_$1_$2
      type: GAUGE
      labels:
        clientId: "$3"
        broker: "$4:$5"
    - pattern: kafka.server<type=(.+), cipher=(.+), protocol=(.+), listener=(.+), networkProcessor=(.+)><>connections
      name: kafka_server_$1_connections_tls_info
      type: GAUGE
      labels:
        cipher: "$2"
        protocol: "$3"
        listener: "$4"
        networkProcessor: "$5"
    - pattern: kafka.server<type=(.+), clientSoftwareName=(.+), clientSoftwareVersion=(.+), listener=(.+), networkProcessor=(.+)><>connections
      name: kafka_server_$1_connections_software
      type: GAUGE
      labels:
        clientSoftwareName: "$2"
        clientSoftwareVersion: "$3"
        listener: "$4"
        networkProcessor: "$5"
    - pattern: "kafka.server<type=(.+), listener=(.+), networkProcessor=(.+)><>(.+-total):"
      name: kafka_server_$1_$4
      type: COUNTER
      labels:
        listener: "$2"
        networkProcessor: "$3"
    - pattern: "kafka.server<type=(.+), listener=(.+), networkProcessor=(.+)><>(.+):"
      name: kafka_server_$1_$4
      type: GAUGE
      labels:
        listener: "$2"
        networkProcessor: "$3"
    - pattern: kafka.server<type=(.+), listener=(.+), networkProcessor=(.+)><>(.+-total)
      name: kafka_server_$1_$4
      type: COUNTER
      labels:
        listener: "$2"
        networkProcessor: "$3"
    - pattern: kafka.server<type=(.+), listener=(.+), networkProcessor=(.+)><>(.+)
      name: kafka_server_$1_$4
      type: GAUGE
      labels:
        listener: "$2"
        networkProcessor: "$3"
    # Some percent metrics use MeanRate attribute
    # Ex) kafka.server<type=(KafkaRequestHandlerPool), name=(RequestHandlerAvgIdlePercent)><>MeanRate
    - pattern: kafka.(\w+)<type=(.+), name=(.+)Percent\w*><>MeanRate
      name: kafka_$1_$2_$3_percent
      type: GAUGE
    # Generic gauges for percents
    - pattern: kafka.(\w+)<type=(.+), name=(.+)Percent\w*><>Value
      name: kafka_$1_$2_$3_percent
      type: GAUGE
    - pattern: kafka.(\w+)<type=(.+), name=(.+)Percent\w*, (.+)=(.+)><>Value
      name: kafka_$1_$2_$3_percent
      type: GAUGE
      labels:
        "$4": "$5"
    # Generic per-second counters with 0-2 key/value pairs
    - pattern: kafka.(\w+)<type=(.+), name=(.+)PerSec\w*, (.+)=(.+), (.+)=(.+)><>Count
      name: kafka_$1_$2_$3_total
      type: COUNTER
      labels:
        "$4": "$5"
        "$6": "$7"
    - pattern: kafka.(\w+)<type=(.+), name=(.+)PerSec\w*, (.+)=(.+)><>Count
      name: kafka_$1_$2_$3_total
      type: COUNTER
      labels:
        "$4": "$5"
    - pattern: kafka.(\w+)<type=(.+), name=(.+)PerSec\w*><>Count
      name: kafka_$1_$2_$3_total
      type: COUNTER
    # Generic gauges with 0-2 key/value pairs
    - pattern: kafka.(\w+)<type=(.+), name=(.+), (.+)=(.+), (.+)=(.+)><>Value
      name: kafka_$1_$2_$3
      type: GAUGE
      labels:
        "$4": "$5"
        "$6": "$7"
    - pattern: kafka.(\w+)<type=(.+), name=(.+), (.+)=(.+)><>Value
      name: kafka_$1_$2_$3
      type: GAUGE
      labels:
        "$4": "$5"
    - pattern: kafka.(\w+)<type=(.+), name=(.+)><>Value
      name: kafka_$1_$2_$3
      type: GAUGE
    # Emulate Prometheus 'Summary' metrics for the exported 'Histogram's.
    # Note that these are missing the '_sum' metric!
    - pattern: kafka.(\w+)<type=(.+), name=(.+), (.+)=(.+), (.+)=(.+)><>Count
      name: kafka_$1_$2_$3_count
      type: COUNTER
      labels:
        "$4": "$5"
        "$6": "$7"
    - pattern: kafka.(\w+)<type=(.+), name=(.+), (.+)=(.*), (.+)=(.+)><>(\d+)thPercentile
      name: kafka_$1_$2_$3
      type: GAUGE
      labels:
        "$4": "$5"
        "$6": "$7"
        quantile: "0.$8"
    - pattern: kafka.(\w+)<type=(.+), name=(.+), (.+)=(.+)><>Count
      name: kafka_$1_$2_$3_count
      type: COUNTER
      labels:
        "$4": "$5"
    - pattern: kafka.(\w+)<type=(.+), name=(.+), (.+)=(.*)><>(\d+)thPercentile
      name: kafka_$1_$2_$3
      type: GAUGE
      labels:
        "$4": "$5"
        quantile: "0.$6"
    - pattern: kafka.(\w+)<type=(.+), name=(.+)><>Count
      name: kafka_$1_$2_$3_count
      type: COUNTER
    - pattern: kafka.(\w+)<type=(.+), name=(.+)><>(\d+)thPercentile
      name: kafka_$1_$2_$3
      type: GAUGE
      labels:
        quantile: "0.$4"
    # KRaft overall related metrics
    # distinguish between always increasing COUNTER (total and max) and variable GAUGE (all others) metrics
    - pattern: "kafka.server<type=raft-metrics><>(.+-total|.+-max):"
      name: kafka_server_raftmetrics_$1
      type: COUNTER
    - pattern: "kafka.server<type=raft-metrics><>(current-state): (.+)"
      name: kafka_server_raftmetrics_$1
      value: 1
      type: UNTYPED
      labels:
        $1: "$2"
    - pattern: "kafka.server<type=raft-metrics><>(.+):"
      name: kafka_server_raftmetrics_$1
      type: GAUGE
    # KRaft "low level" channels related metrics
    # distinguish between always increasing COUNTER (total and max) and variable GAUGE (all others) metrics
    - pattern: "kafka.server<type=raft-channel-metrics><>(.+-total|.+-max):"
      name: kafka_server_raftchannelmetrics_$1
      type: COUNTER
    - pattern: "kafka.server<type=raft-channel-metrics><>(.+):"
      name: kafka_server_raftchannelmetrics_$1
      type: GAUGE
    # Broker metrics related to fetching metadata topic records in KRaft mode
    - pattern: "kafka.server<type=broker-metadata-metrics><>(.+):"
      name: kafka_server_brokermetadatametrics_$1
      type: GAUGE
```



Once the Kafka cluster is deployed with JMX Exporter and Kafka Exporter enabled, Prometheus can be configured to scrape metrics from the exporters.

If Kube-Prometheus-Stack is installed in the cluster, Prometheus can be configured to scrape metrics from Kafka brokers and exporters by creating a `PodMonitor` resources.

The following resources can be created for scraping metrics from all PODs that are created by Strimzi (Kafka, KafkaConnect, KafkaMirrorMaker) are created in the Kafka namespace:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: cluster-operator-metrics
  labels:
    app: strimzi
spec:
  selector:
    matchLabels:
      strimzi.io/kind: cluster-operator
  namespaceSelector:
    matchNames:
      - kafka
  podMetricsEndpoints:
  - path: /metrics
    port: http
---
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: entity-operator-metrics
  labels:
    app: strimzi
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: entity-operator
  namespaceSelector:
    matchNames:
      - kafka
  podMetricsEndpoints:
  - path: /metrics
    port: healthcheck
---
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: bridge-metrics
  labels:
    app: strimzi
spec:
  selector:
    matchLabels:
      strimzi.io/kind: KafkaBridge
  namespaceSelector:
    matchNames:
      - kafka
  podMetricsEndpoints:
  - path: /metrics
    port: rest-api
---
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: kafka-resources-metrics
  labels:
    app: strimzi
spec:
  selector:
    matchExpressions:
      - key: "strimzi.io/kind"
        operator: In
        values: ["Kafka", "KafkaConnect", "KafkaMirrorMaker2"]
  namespaceSelector:
    matchNames:
      - kafka
  podMetricsEndpoints:
  - path: /metrics
    port: tcp-prometheus
    relabelings:
    - separator: ;
      regex: __meta_kubernetes_pod_label_(strimzi_io_.+)
      replacement: $1
      action: labelmap
    - sourceLabels: [__meta_kubernetes_namespace]
      separator: ;
      regex: (.*)
      targetLabel: namespace
      replacement: $1
      action: replace
    - sourceLabels: [__meta_kubernetes_pod_name]
      separator: ;
      regex: (.*)
      targetLabel: kubernetes_pod_name
      replacement: $1
      action: replace
    - sourceLabels: [__meta_kubernetes_pod_node_name]
      separator: ;
      regex: (.*)
      targetLabel: node_name
      replacement: $1
      action: replace
    - sourceLabels: [__meta_kubernetes_pod_host_ip]
      separator: ;
      regex: (.*)
      targetLabel: node_ip
      replacement: $1
      action: replace

```

{{site.data.alerts.note}}

Further details can be found in [Strimzi documentation - Monitoring Kafka](https://strimzi.io/docs/operators/latest/deploying#assembly-metrics-str)
See samples file configuration in [Strimzi operatro Github repo - Examples: Metrics](https://github.com/strimzi/strimzi-kafka-operator/tree/0.47.0/examples/metrics)

{{site.data.alerts.end}}

##### Grafana Dashboards

If [Grafana's dynamic provisioning of dashboard](/docs/grafana/#dynamic_provisioning_of_dashboards) is configured, Kafka grafana dashboard is automatically deployed by Strimzi Operator Helm chart when providing the following values:


```yaml
dashboards:
  enabled: true
  label: grafana_dashboard # this is the default value from the grafana chart
  labelValue: "1" # this is the default value from the grafana chart
  # Annotations to specify the Grafana folder
  annotations:
    grafana_folder: Strimzi
  extraLabels: {}
```

Helm chart will deploy a dahsboard in a kubernetes ConfigMap that Grafana can dynamically load and add into "Strimzi" folder.

## Schema Registry

A schema defines the structure of message data. It defines allowed data types, their format, and relationships. A schema acts as a blueprint for data, describing the structure of data records, the data types of individual fields, the relationships between fields, and any constraints or rules that apply to the data.

Kafka Schema Registry is a component in the Apache Kafka ecosystem that provides a centralized schema management service for Kafka producers and consumers. It allows producers to register schemas for the data they produce, and consumers to retrieve and use these schemas for data validation and deserialization. The Schema Registry helps ensure that data exchanged through Kafka is compliant with a predefined schema, enabling data consistency, compatibility, and evolution across different systems and applications.

![Schema-Registry](/assets/img/schema-registry-ecosystem.jpg)

<img src="/assets/img/schema-registry-and-kafka.png" alt="Schema-Registry-and-Kafka" style="background-color:white">

When using Avro or other schema format, it is critical to manage schemas and evolve them thoughtfully. Schema compatibility checking is enabled in Kafka Schema Registry by versioning every single schema and comparing new schemas to previous versions. The type of compatibility required (backward, forward, full, none, etc) determines how Kafka Schema Registry evaluates each new schema. New schemas that fail compatibility checks are removed from service.

Some key benefits of using Kafka Schema Registry include:

- Schema Evolution: As data formats and requirements evolve over time, it is common for producers and consumers to undergo changes to their data schemas. Kafka Schema Registry provides support for schema evolution, allowing producers to register new versions of schemas while maintaining compatibility with existing consumers. Consumers can retrieve the appropriate schema version for deserialization, ensuring that data is processed correctly even when schema changes occur.

- Data Validation: Kafka Schema Registry enables data validation by allowing producers to register schemas with predefined data types, field names, and other constraints. Consumers can then retrieve and use these schemas to validate incoming data, ensuring that data conforms to the expected structure and format. This helps prevent data processing errors and improves data quality.
Schema Management: Kafka Schema Registry provides a centralized repository for managing schemas, making it easier to track, version, and manage changes. Producers and consumers can register, retrieve and manage schemas through a simple API, allowing for centralized schema governance and management.

- Interoperability: Kafka Schema Registry promotes interoperability between different producers and consumers by providing a standardized way to define and manage data schemas. Producers and consumers written in different programming languages or using different serialization frameworks can use a common schema registry to ensure data consistency and compatibility across the ecosystem.

- Backward and Forward Compatibility: Kafka Schema Registry allows producers to register backward and forward compatible schemas, enabling smooth upgrades and changes to data schemas without disrupting existing producers and consumers. Backward compatibility ensures that older consumers can still process data produced with a newer schema, while forward compatibility allows newer consumers to process data produced with an older schema.

### Deploying Schema Registry

Official confluent docker images for Schema Registry can be installed using [helm chart maintained by the community](https://github.com/confluentinc/cp-helm-charts/tree/master/charts/cp-schema-registry). [Confluent official docker images support multiarchitecture (x86/ARM)](https://hub.docker.com/r/confluentinc/cp-schema-registry/tags). However, this helm chart is quite old and it seems not to be maintaned any more (last update: 2 years ago).

### Install Bitnami packaged Schema registry

[Confluent Schema Registry packaged by Bitnami](https://github.com/bitnami/charts/tree/main/bitnami/schema-registry) is keept up to date and it supports [multi-architecture docker images](https://hub.docker.com/r/bitnami/schema-registry/tags).


- Step 1: Prepare schema-registry-values.yaml:

  ```yml
  kafka:
    enabled: false
  auth:
    protocol: {}
  service:
    ports:
      client: {}
  externalKafka:
    brokers:
      - PLAINTEXT://my-cluster-kafka-bootstrap:9092
  ```
- Step 2: Install bitnami schema registry:

  ```shell
  helm install schema-registry oci://registry-1.docker.io/bitnamicharts/schema-registry -f schema-registry-values.yml --namespace kafka
  ```
- Step 3: Check schema registry started

  ```shell
  kubectl logs kafka-schema-registry-0 schema-registry -n kafka

  [2023-08-19 09:06:38,783] INFO HV000001: Hibernate Validator 6.1.7.Final (org.hibernate.validator.internal.util.Version:21)
  [2023-08-19 09:06:39,019] INFO Started o.e.j.s.ServletContextHandler@7e94d093{/,null,AVAILABLE} (org.eclipse.jetty.server.handler.ContextHandler:921)
  [2023-08-19 09:06:39,029] INFO Started o.e.j.s.ServletContextHandler@270b6b5e{/ws,null,AVAILABLE} (org.eclipse.jetty.server.handler.ContextHandler:921)
  [2023-08-19 09:06:39,040] INFO Started NetworkTrafficServerConnector@660acfb{HTTP/1.1, (http/1.1, h2c)}{0.0.0.0:8081} (org.eclipse.jetty.server.AbstractConnector:333)
  [2023-08-19 09:06:39,041] INFO Started @6514ms (org.eclipse.jetty.server.Server:415)
  [2023-08-19 09:06:39,041] INFO Schema Registry version: 7.4.1 commitId: 8969f9f38b043ca55d4e97536b6bcb5ccc54f42f (io.confluent.kafka.schemaregistry.rest.SchemaRegistryMain:47)
  [2023-08-19 09:06:39,042] INFO Server started, listening for requests... (io.confluent.kafka.schemaregistry.rest.SchemaRegistryMain:49)
  ```

### Testing Schema Registy

Once the cluster is running, you can run a producer and a consumer using Avro messages stored in Schema Registry.

{{site.data.alerts.note}}

Kafka consumer and producers docker images used for testing ca be found in [kafka-python-client repository](https://github.com/ricsanfre/kafka-python-client). This docker image contain source code of one of the examples in [confluent-kafka-python repository]https://github.com/confluentinc/confluent-kafka-python/.


{{site.data.alerts.end}}

- Step 1: launch producer
  ```shell
  kubectl -n kafka run kafka-producer -ti --image=ricsanfre/kafka-python-client:latest --rm=true --restart=Never -- python avro_producer.py -b my-cluster-kafka-bootstrap:9092 -s http://kafka-schema-registry:8081 -t my-avro-topic
  ```
  Enter required fields for building the message


- Step 3: in a different terminal launch consumer
  ```shell
  kubectl -n kafka run kafka-consumer -ti --image=ricsanfre/kafka-python-client:latest --rm=true --restart=Never -- python avro_consumer.py -b my-cluster-kafka-bootstrap:9092 -s http://kafka-schema-registry:8081 -t my-avro-topic
  ```

## Kafka UI (Kafdrop)

[Kafdrop](https://github.com/obsidiandynamics/kafdrop) is a web UI for viewing Kafka topics and browsing consumer groups. The tool displays information such as brokers, topics, partitions, consumers, and lets you view messages.

{{site.data.alerts.note}}

Even when helm chart source code is available in the repository, this helm chart is not hosted in any official helm repository. I have decided to selfhost this helm chart within my own repository [ricsanfre/helm-charts/kafdrop](https://github.com/ricsanfre/helm-charts/tree/master/charts/kafdrop) that is available in my own helm repository `https://ricsanfre.github.io/helm-charts/`

{{site.data.alerts.end}}

- Step 1: Add the Helm repository:

  ```shell
  helm repo add ricsanfre https://ricsanfre.github.io/helm-charts/
  ```
- Step 2: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```
- Step 3: Prepare kafdrop-values.yml

  ```yml
  # Kafka broker connection
  kafka:
    brokerConnect: my-cluster-kafka-bootstrap:9092ç
  # JVM options
  jvm:
    opts: "-Xms32M -Xmx64M"

  # Adding connection to schema registry
  cmdArgs: "--schemaregistry.connect=http://kafka-schema-registry:8081"

  # Ingress resource
  ingress:
    enabled: true
    ## Add ingressClassName to the Ingress
    ingressClassName: nginx
    # ingress host
    hosts:
      - kafdrop.${CLUSTER_DOMAIN}
    ## TLS Secret Name
    tls:
      - secretName: kafdrop-tls
        hosts:
          - kafdrop.${CLUSTER_DOMAIN}
    ## Default ingress path
    path: /
    ## Ingress annotations
    annotations:
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      # Possible Cluster-Issuer values:
      #   * 'letsencrypt-issuer' (valid TLS certificate using IONOS API)
      #   * 'ca-issuer' (CA-signed certificate, not valid)
      cert-manager.io/cluster-issuer: letsencrypt-issuer
      cert-manager.io/common-name: kafdrop.${CLUSTER_DOMAIN}

  # Kafdrop docker images are not multi-arch. Only amd64 image is available
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/arch
            operator: In
            values:
            - amd64
  ```


  {{site.data.alerts.note}}

  Substitute variables (`${var}`) in the above yaml file before deploying manifest.
  -   Replace `${CLUSTER_DOMAIN}` by the domain name used in the cluster. For example: `homelab.ricsanfre.com`.

  Ingress Controller NGINX exposes kafdrop server as `kafdrop.${CLUSTER_DOMAIN}` virtual host, routing rules are configured for redirecting all incoming HTTP traffic to HTTPS and TLS is enabled using a certificate generated by Cert-manager.

  See ["Ingress NGINX Controller - Ingress Resources Configuration"](/docs/nginx/#ingress-resources-configuration) for furher details.

  ExternalDNS will automatically create a DNS entry mapped to Load Balancer IP assigned to Ingress Controller, making kafdrop service available at `kafdrop.{$CLUSTER_DOMAIN}. Further details in ["External DNS - Use External DNS"](/docs/kube-dns/#use-external-dns)

  {{site.data.alerts.end}}


  Kafdrop is configured to use Schema Registry, so messages can be decoded when Schema Registry is used. See helm chart value `cmdArgs`:
  -  `--schemaregistry.connect=http://kafka-schema-registry:8081`


- Step 4: Install Kafdrop helm chart

  ```shell
  helm upgrade -i kafdrop ricsanfre/kafdrop -f kafdrop-values.yml --namespace kafka
  ```
- Step 4: Confirm that the deployment succeeded, opening UI:

  https://kafdrop.picluster.ricsanfre.com/
  

## References

- [Strimzi documentation](https://strimzi.io/docs/operators/latest/overview)
- [Strimzi-Kafka-Operator Github repository](https://github.com/strimzi/strimzi-kafka-operator/)
- [Kafdrop-Kafka Web UI](https://github.com/obsidiandynamics/kafdrop)
- [Confluent Schema Registry doc](https://docs.confluent.io/platform/current/schema-registry/index.html)
- [Bitnami Schema Registry helm chart](https://github.com/bitnami/charts/tree/main/bitnami/schema-registry)