# Centralized Log Monitoring with EFK stack

ELK Stack (Elaticsearch - Logstash - Kibana) enables centralized log monitoring of IT infrastructure.
As an alternative EFK stack (Elastic - Fluentd - Kibana) can be used, where Fluentd is used instead of Logstash for doing the collection and parsing of logs.


https://medium.com/intelligentmachines/centralised-logging-for-istio-1-5-with-eck-elastic-cloud-on-kubernetes-and-fluent-bit-680db15af1e2

## ARM architecture and Kubernetes deployment support

In June 2020, Elastic announced (https://www.elastic.co/blog/elasticsearch-on-arm) that starting from 7.8 release they will provide multi-architecture docker images supporting AMD64 and ARM64 architectures.

To facilitate the deployment on a Kubernetes cluster [ECK project](https://github.com/elastic/cloud-on-k8s) has been created.
ECK ([Elastic Cloud on Kubernetes](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)) automates the deployment, provisioning, management, and orchestration of ELK Stack (Elasticsearch, Kibana, APM Server, Enterprise Search, Beats, Elastic Agent, and Elastic Maps Server) on Kubernetes based on the operator pattern. 

> NOTE: Logstash deployment is not supported by ECK operator

Fluentd as well support ARM64 docker images for being deployed on Kubernetes clusters with the buil-in configuration needed to automatically collect and parsing containers logs. See [github repository](https://github.com/fluent/fluentd-kubernetes-daemonset).

## Why EFK and not ELK

Fluentd and Logstash offers simillar capabilities (log parsing, routing etc) but I will select Fluentd because:

- **Performance and footprint**: Logstash consumes more memory than Fluentd. Logstash is written in Java and Fluentd is written in Ruby. Fluentd is an efficient log aggregator. For most small to medium-sized deployments, fluentd is fast and consumes relatively minimal resources.
- **Log Parsing**: Fluentd uses standard built-in parsers (JSON, regex, csv etc.) and Logstash uses plugins for this. This makes Fluentd favorable over Logstash, because it does not need extra plugins installed
- **Kubernetes deployment**: Docker has a built-in logging driver for Fluentd, but doesn’t have one for Logstash. With Fluentd, no extra agent is required on the container in order to push logs to Fluentd. Logs are directly shipped to Fluentd service from STDOUT without requiring an extra log file. Logstash requires additional agent (Filebeat) in order to read the application logs from STDOUT before they can be sent to Logstash.

- **Fluentd** is a CNCF project


### References

[1] Kubernetes logging architecture (https://www.magalix.com/blog/kubernetes-logging-101) (https://www.magalix.com/blog/kubernetes-observability-log-aggregation-using-elk-stack)

[2] Fluentd vs Logstash (https://platform9.com/blog/kubernetes-logging-comparing-fluentd-vs-logstash/)

[3] EFK on Kubernetes tutorials (https://www.digitalocean.com/community/tutorials/how-to-set-up-an-elasticsearch-fluentd-and-kibana-efk-logging-stack-on-kubernetes) (https://platform9.com/blog/kubernetes-logging-and-monitoring-the-elasticsearch-fluentd-and-kibana-efk-stack-part-1-fluentd-architecture-and-configuration/)

[4] ELK on Kubernetes tutorials (https://coralogix.com/blog/running-elk-on-kubernetes-with-eck-part-1/) (https://www.deepnetwork.com/blog/2020/01/27/ELK-stack-filebeat-k8s-deployment.html)

[5] Fluentd in Kubernetes (https://docs.fluentd.org/container-deployment/kubernetes)

## EFK Installation


### ELK Operator installation

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

### Elasticsearch installation

Basic instructions [here](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-deploy-elasticsearch.html)

- Step 1: Create a manifest file containing basic configuration: one node elasticsearch using Longhorn as storageClass and 5GB of storage in the volume claims.

```yml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: efk
  namespace: k3s-logging
spec:
  version: 7.15.0
  nodeSets:
  - name: default
    count: 1    # One node elastic search cluster
    config:
      node.store.allow_mmap: false # Disable memory mapping: NOTE1
    volumeClaimTemplates: # Specify Longhorn as storge class and 5GB of storage
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
        storageClassName: longhorn
  http:    # Making elasticsearch service available from outisde the cluster: NOTE 3
    service:
      spec:
        type: LoadBalancer
```

- Step 2: Apply manifest

    kubectl apply -f manifest.yml

- Step 3: Check Services and Pods

```
kubectl get services -n k3s-logging
NAME                            TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
efk-es-transport   ClusterIP      None            <none>        9300/TCP         3h2m
efk-es-default     ClusterIP      None            <none>        9200/TCP         3h2m
efk-es-http        LoadBalancer   10.43.186.20    10.0.0.102    9200:30079/TCP   147m
```

> **NOTE 1: About Memory mapping configuration**<br>
By default, Elasticsearch uses memory mapping (mmap) to efficiently access indices ( `node.store.allow_nmap: false` option disable this default mechanism. <br>
Usually, default values for virtual address space on Linux distributions are too low for Elasticsearch to work properly, which may result in out-of-memory exceptions. This is why mmap is disable. <br>
For production workloads, it is strongly recommended to increase the kernel setting vm.max_map_count to 262144 and leave node.store.allow_mmap unset. See details [here](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-virtual-memory.html)

> **NOTE 2: About Persistent Storage**<br>
See how to configure PersistenVolumeTemplates for Elasticsearh using this operator [here](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-volume-claim-templates.html)

> **NOTE 3: About accesing ELK services from outside the cluster**<br>

By default ELK services (elasticsearch, kibana, etc) are accesible through Kubernetes `ClusterIP` service types (only available within the cluster). To make them available outside the cluster they can be configured as `LoadBalancer` service type.
This can be useful for example if elasticsearh database have to be used to monitoring logs from servers outside the cluster(i.e: `gateway` service can be configured to send logs to the elasticsearch running in the cluster).

More details [here](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-services.html)

### Elasticsearch authentication

By default ECK configures secured communications with auto-signed SSL certificates. Access to its API on port 9200 is only available through https and user authentication is required to allow the connection. ECK defines a `elastic` user and stores its credentials within a kubernetes Secret.

Both to access Kibana UI or to configure Fluetd collector to insert data, secure communications on https must be used and user/password need to be provided 

Password is stored in a kubernetes secret (`<efk_cluster_name>-es-elastic-user`). Execute this command for getting the password
```
kubectl get secret -n k3s-logging efk-es-elastic-user -o=jsonpath='{.data.elastic}' | base64 --decode; echo
```

Setting the password to a well known value is not an officially supported feature by ECK but a workaround exists by creating the {clusterName}-es-elastic-user Secret before creating the Elasticsearch resource with the ECK operator.


```yml
apiVersion: v1
kind: Secret
metadata: 
  name: efk-es-elastic-user
  namespace: k3s-logging
type: Opaque
data:
  elastic: "{{ efk_elasticsearch_passwd | b64encode }}"
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
  version: 7.15.0
  count: 2 # Elastic Search statefulset deployment with two replicas
  elasticsearchRef:
    name: "elasticsearch"
  http:  # NOTE disabling selfSigned certificate
    tls:
      selfSignedCertificate:
        disabled: true
```

- Step 2: Apply manifest

    kubectl apply -f manifest.yml

- Step 3: Check kibana POD and services


```
kubectl get services -n k3s-logging
NAME                     TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
efk-kb-http              LoadBalancer   10.43.242.252   10.0.0.101    5601:31779/TCP   3h2m
```

### Ingress rule for Traefik

Make accesible Kibana UI from outside the cluster through Ingress Controller

- Step 1. Create the ingress rule manifest
```yml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kibana-ingress
  namespace: k3s-logging
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
  - host: kibana.picluster.ricsanfre.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: "elk-kb-http"
            port:
              number: 5601
```
- Step 2: Apply manifest

    kubectl apply -f manifest.yml

- Step 3. Access to Kibana UI

UI can be access through http://kibana.picluster.ricsanfre.com.
Using loging `elastic` and the password stored in `<efk_cluster_name>-es-elastic-user`



### Installation of Fluentd

Fluentd will be deployed on Kubernetes as a DaemonSet, which is a Kubernetes workload type that runs a copy of a given Pod on each Node in the Kubernetes cluster. Using this DaemonSet controller, a Fluentd logging agent Pod will be deployed on every node of the cluster. To learn more about this logging architecture, consult [“Using a node logging agent”](https://kubernetes.io/docs/concepts/cluster-administration/logging/#using-a-node-logging-agent) from the official Kubernetes docs.

In Kubernetes, containerized applications that log to `stdout` and `stderr` have their log streams captured and redirected to JSON files on the nodes. The Fluentd Pod will tail these log files, filter log events, transform the log data, and ship it off to the Elasticsearch logging backend.

In addition to container logs, the Fluentd agent will tail Kubernetes system component logs like kubelet, kube-proxy, and Docker logs. To see a full list of sources tailed by the Fluentd logging agent, consult the [`kubernetes.conf`](https://github.com/fluent/fluentd-kubernetes-daemonset/blob/master/docker-image/v1.14/arm64/debian-elasticsearch7/conf/kubernetes.conf) file used to configure the logging agent.

Fluentd can be deployed on Kubernetes cluster as a daemonset pod  using fluentd community docker images in [`fluent-kubernetes-daemonset` repo](https://github.com/fluent/fluentd-kubernetes-daemonset. 

Further documentation can be found [here](https://docs.fluentd.org/container-deployment/kubernetes) and different backends manifest sample files are provided in `fluentd-kubernetes-daemonset` repo. For using elasticsearh as backend we will use a manifest file based on this [spec](https://github.com/fluent/fluentd-kubernetes-daemonset/blob/master/fluentd-daemonset-elasticsearch-rbac.yaml)


Fluentd need to be tuning for parsing containerd logs (fluentd images are prepared for parsing docker logs). See this [issue](https://github.com/fluent/fluentd-kubernetes-daemonset/issues/412)



### Alternative installation of Filebeats

In order to collect and parse all logs from all containers within the K3S cluster, Filebeats need to be deployed as DaemonSet pod (one pod running on each cluster node)

Basic instructions [here](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-beat-quickstart.html)

- Step 1. Create a manifest file

```yml
apiVersion: beat.k8s.elastic.co/v1beta1
kind: Beat
metadata:
  name: filebeat
spec:
  type: filebeat
  version: 7.14.1
  elasticsearchRef:
    name: elasticsearch
  config:
    filebeat.inputs:
    - type: container
      paths:
      - /var/log/containers/*.log
  daemonSet:
    podTemplate:
      spec:
        dnsPolicy: ClusterFirstWithHostNet
        hostNetwork: true
        securityContext:
          runAsUser: 0
        containers:
        - name: filebeat
          volumeMounts:
          - name: varlogcontainers
            mountPath: /var/log/containers
          - name: varlogpods
            mountPath: /var/log/pods
          - name: varlibdockercontainers
            mountPath: /var/lib/docker/containers
        volumes:
        - name: varlogcontainers
          hostPath:
            path: /var/log/containers
        - name: varlogpods
          hostPath:
            path: /var/log/pods
        - name: varlibdockercontainers
          hostPath:
            path: /var/lib/docker/containers

```

- Step 2: Apply manifest

    kubectl apply -f manifest.yml