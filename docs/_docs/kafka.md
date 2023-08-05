---
title: Kafka
permalink: /docs/kafka/
description: How to deploy Kafka to our Kubernetes cluster. Using Strimzi Kafka Operator to streamline the deployment
last_modified_at: "05-08-2023"

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

Using Strimzi operator build Kafka cluster CRD.

- Step 1: Create a manifest file containing basic configuration of Kafka cluster with 3 Zookeeper replicas and 3 Kafka broker replicas. Persistence will be configure to use Longhorn as storageClass and 5GB of storage in the volume claims.
  
  ```yml
	apiVersion: kafka.strimzi.io/v1beta2
	kind: Kafka
	metadata:
	  name: my-cluster
	  namespace: kafka
	spec:
	  kafka:
	    version: 3.5.1
	    replicas: 3
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
	      inter.broker.protocol.version: "3.2"
	    storage:
	      type: jbod
	      class: longhorn
	      volumes:
	      - id: 0
	        type: persistent-claim
	        size: 5Gi
	        deleteClaim: false

	  zookeeper:
	    replicas: 3
	    storage:
	      type: persistent-claim
	      size: 5Gi
	      deleteClaim: false5Gi
	      class: longhorn
	  entityOperator:
	    topicOperator: {}
	    userOperator: {}  
  ```

- Step 2: Apply manifest
  
  ```shell
  kubectl apply -f manifest.yml
  ```
- Step 3: Check Kafka status
  
  ```shell
  kubectl get kafka -n kafka
  NAME            DESIRED KAFKA REPLICAS   DESIRED ZK REPLICAS   READY   WARNINGS
  kafka-cluster   3                        3                     True    True
  ```

### Testing Kafka cluster

Once the cluster is running, you can run a simple producer to send messages to a Kafka topic (the topic will be automatically created).

- Step 1: launch producer
  ```shell
  kubectl -n kafka run kafka-producer -ti --annotations="linkerd.io/inject=disabled" --image=quay.io/strimzi/kafka:0.29.0-kafka-3.2.0 --rm=true --restart=Never -- bin/kafka-console-producer.sh --bootstrap-server my-cluster-kafka-bootstrap:9092 --topic my-topic
  ```

- Step 3: in a different terminal launch consumer
  ```shell
  kubectl -n kafka run kafka-consumer -ti --annotations="linkerd.io/inject=disabled" --image=quay.io/strimzi/kafka:0.29.0-kafka-3.2.0 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server my-cluster-kafka-bootstrap:9092 --topic my-topic --from-beginning
  ```

- Step 5: In producer terminal wait for the prompt and start typing messages. (Input Control-C to finish)

  Messages will be outputed in consumer terminal.


### Deploy Kafka UI (Kafdrop)

[Kafdrop](https://github.com/obsidiandynamics/kafdrop) is a web UI for viewing Kafka topics and browsing consumer groups. The tool displays information such as brokers, topics, partitions, consumers, and lets you view messages.

{{site.data.alerts.note}}

Even when helm chart source code is available in the repository, this helm chart is not hosted in any official helm repository. I have decided to selfhost this helm chart within my own repository `https://ricsanfre.github.io/helm-charts/`

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
  # Ingress resource
  ingress:
    enabled: true
    ## Add ingressClassName to the Ingress
    ingressClassName: nginx
    # ingress host
    hosts:
      - kafdrop.picluster.ricsanfre.com
    ## TLS Secret Name
    tls:
      - secretName: kafdrop-tls
        hosts:
          - kafdrop.picluster.ricsanfre.com
    ## Default ingress path
    path: /
    ## Ingress annotations
    annotations:
      # Linkerd configuration. Configure Service as Upstream
      nginx.ingress.kubernetes.io/service-upstream: "true"
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      # Possible Cluster-Issuer values:
      #   * 'letsencrypt-issuer' (valid TLS certificate using IONOS API)
      #   * 'ca-issuer' (CA-signed certificate, not valid)
      cert-manager.io/cluster-issuer: letsencrypt-issuer
      cert-manager.io/common-name: kafdrop.picluster.ricsanfre.com

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