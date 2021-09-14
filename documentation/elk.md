# Centralized Log Monitoring with ELK stack

ELK Stack (Elaticsearch - Logstash - Kibana) enables centralized log monitoring of IT infrastructure.
ELK will be used to monitoring the logs of the K3S cluster.


### ARM architecture support

In June 2020, Elastic announced (https://www.elastic.co/blog/elasticsearch-on-arm) that starting from 7.8 release they will provide multi-architecture docker images supporting AMD64 and ARM64 architectures.

To facilitate the deployment on a Kubernetes cluster [ECK project](https://github.com/elastic/cloud-on-k8s) has been created.

### ELK on Kubernetes

ECK ([Elastic Cloud on Kubernetes](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)) automates the deployment, provisioning, management, and orchestration of ELK Stack (Elasticsearch, Kibana, APM Server, Enterprise Search, Beats, Elastic Agent, and Elastic Maps Server) on Kubernetes based on the operator pattern.

### Installation of ELK Operator

- Step 1: Add the Elastic repository:
    ```
    helm repo add elastic https://helm.elastic.co
    ```
- Step2: Fetch the latest charts from the repository:
    ```
    helm repo update
    ```
- Step 3: Create namespace
    ```
    kubectl create namespace elastic-system
    ```
- Step 3: Install Longhorn in the elastic-system namespace
    ```
    helm install elastic-operator elastic/eck-operator --namespace elastic-system
    ```
- Step 4: Monitor operator logs:
    ```
    kubectl -n elastic-system logs -f statefulset.apps/elastic-operator
    ```

### Installatio of Elasticsearh

https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-deploy-elasticsearch.html

- Step 1: Create a manifest file containing basic configuration: one node elasticsearch using Longhorn as storageClass and PVC of 5GB

```yml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: elasticsearch
spec:
  version: 7.14.1
  nodeSets:
  - name: default
    count: 1
    config:
      node.store.allow_mmap: false
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