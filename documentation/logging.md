# Centralized Log Monitoring with EFK stack

ELK Stack (Elaticsearch - Logstash - Kibana) enables centralized log monitoring of IT infrastructure.
As an alternative EFK stack (Elastic - Fluentd - Kibana) can be used, where Fluentd is used instead of Logstash for doing the collection and parsing of logs.

EFK stack will be deployed as centralized logging solution for the K3S cluster.

![K3S-EFK-Architecture](images/efk_logging_architecture.png)

S
## ARM architecture and Kubernetes deployment support

In June 2020, Elastic announced (https://www.elastic.co/blog/elasticsearch-on-arm) that starting from 7.8 release they will provide multi-architecture docker images supporting AMD64 and ARM64 architectures.

To facilitate the deployment on a Kubernetes cluster [ECK project](https://github.com/elastic/cloud-on-k8s) has been created.
ECK ([Elastic Cloud on Kubernetes](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)) automates the deployment, provisioning, management, and orchestration of ELK Stack (Elasticsearch, Kibana, APM Server, Enterprise Search, Beats, Elastic Agent, and Elastic Maps Server) on Kubernetes based on the operator pattern. 

> NOTE: Logstash deployment is not supported by ECK operator

Fluentd/Fluentbit as well support ARM64 docker images for being deployed on Kubernetes clusters with the buil-in configuration needed to automatically collect and parsing containers logs. See [github repository](https://github.com/fluent/fluentd-kubernetes-daemonset).

## Why EFK and not ELK

Fluentd/Fluentbit and Logstash offers simillar capabilities (log parsing, routing etc) but I will select Fluentd because:

- **Performance and footprint**: Logstash consumes more memory than Fluentd. Logstash is written in Java and Fluentd is written in Ruby. Fluentd is an efficient log aggregator. For most small to medium-sized deployments, fluentd is fast and consumes relatively minimal resources.
- **Log Parsing**: Fluentd uses standard built-in parsers (JSON, regex, csv etc.) and Logstash uses plugins for this. This makes Fluentd favorable over Logstash, because it does not need extra plugins installed
- **Kubernetes deployment**: Docker has a built-in logging driver for Fluentd, but doesn’t have one for Logstash. With Fluentd, no extra agent is required on the container in order to push logs to Fluentd. Logs are directly shipped to Fluentd service from STDOUT without requiring an extra log file. Logstash requires additional agent (Filebeat) in order to read the application logs from STDOUT before they can be sent to Logstash.

- **Fluentd** is a CNCF project


# EFK Installation

## ELK Operator installation

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

## Elasticsearch installation

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
        loadBalancerIP: 10.0.0.101
    tls: # Configuring self-signed certificate with DNS and static IP address: NOTE 4
      selfSignedCertificate:
        subjectAltNames:
        - ip: 10.0.0.101
        - dns: elasticsearch.picluster.ricsanfre.com
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

By default ELK services (elasticsearch, kibana, etc) are accesible through Kubernetes `ClusterIP` service types (only available within the cluster). To make them available outside the cluster they can be configured as `LoadBalancer` service type and specifying a static IP address (`loadBalancerIP`) for the service from the Metal LB pool.
This can be useful for example if elasticsearh database have to be used to monitoring logs from servers outside the cluster(i.e: `gateway` service can be configured to send logs to the elasticsearch running in the cluster).

More details [here](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-services.html)

> **NOTE 4: TLS self-signed certificate**<br>

Self-signed certificate will be created for elasticsearch, SANS (Service Alternative Names) can be added to the TLS certificate. More details [here](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-transport-settings.html)

## Elasticsearch authentication

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


## Kibana installation

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
            name: "efk-kb-http"
            port:
              number: 5601
```
- Step 2: Apply manifest

    kubectl apply -f manifest.yml

- Step 3. Access to Kibana UI

UI can be access through http://kibana.picluster.ricsanfre.com.
Using loging `elastic` and the password stored in `<efk_cluster_name>-es-elastic-user`

## Collecting Kuberentes logs with Fluentbit/Fluentd

In Kubernetes, containerized applications that log to `stdout` and `stderr` have their log streams captured and redirected to log files on the nodes. To tail these log files, filter log events, transform the log data, and ship it off to the Elasticsearch logging backend, a process like, fluentd/fluentbit can be used.

Log format used by Kubernetes is different depending on the container runtime used. `docker` container run-time generates logs file in JSON format. `containerd` run-time, used by K3S, uses CRI log format.

    <time_stamp> <stream_type> <P/F> <log>

where:
  - <time_stamp> has the format `%Y-%m-%dT%H:%M:%S.%L%z` Date and time including UTC offset
  - <stream_type> is `stdout` or `stderr`
  - <P/F> indicates whether the log line is partial (P), in case of multine logs, or full log line (F)
  - <log>: message log

Fluentd or, its lightweight alternative, Fluentbit are deployed on Kubernetes as a DaemonSet, which is a Kubernetes workload type that runs a copy of a given Pod on each Node in the Kubernetes cluster.
Using this DaemonSet controller, a Fluentd/Fluentbit logging agent Pod is deployed on every node of the cluster.

To learn more about this logging architecture, consult [“Using a node logging agent”](https://kubernetes.io/docs/concepts/cluster-administration/logging/#using-a-node-logging-agent) from the official Kubernetes docs.

In addition to container logs, the Fluentd/Fluentbit agent can collect and parse Kubernetes system component logs like kubelet, kube-proxy, systemd-based services and OS filesystem level logs (syslog, kern.log, etc).

> NOTE: Ubuntu system logs stored in `/var/logs` (auth.log, systlog, kern.log), have a syslog format without priority field, and the timestamp is using local time.

    <time_stamp> <host> <process>[<PID>] <message>
Where:
  - <time_stamp> has the format `%b %d %H:%M:%S`: local date and time not including timezone UTC offset
  - <host>: hostanme
  - <process> and <PID> identifies the process generating the log


### Fluent-bit installation

Fluentbit is a lightweight version of fluentd ( just 640 KB not requiring any gem library to be installed). See comparison [here](https://docs.fluentbit.io/manual/about/fluentd-and-fluent-bit).

It can be installed and configured to collect and parse Kubernetes logs deploying a daemonset pod (same as fluentd). See fluenbit documentation on how to install it on Kuberentes cluster (https://docs.fluentbit.io/manual/installation/kubernetes).

For speed-up the installation there is available a [helm chart](https://github.com/fluent/helm-charts/tree/main/charts/fluent-bit). fluentbit config file can be 


- Step 1. Add fluentbit helm repo

      helm repo add fluent https://fluent.github.io/helm-charts

- Step 2. Update helm repo

      helm repo update

- Step 3. Create `values.yml` for tuning helm chart deployment.

  fluentbit configuration can be provided to the helm. See [`values.yml`](https://github.com/fluent/helm-charts/blob/main/charts/fluent-bit/values.yaml)
  
  The final `values.yml` is:
  ```yml
  ---
  # fluentbit helm chart values

  # fluentbit-container environment variables. **NOTE 1**
  env:
    # Elastic operator creates elastic service name with format cluster_name-es-http
    - name: FLUENT_ELASTICSEARCH_HOST
      value: "efk-es-http"
    # Default elasticsearch default port
    - name: FLUENT_ELASTICSEARCH_PORT
      value: "9200"
    # Elasticsearch user
    - name: FLUENT_ELASTICSEARCH_USER
      value: "elastic"
    # Elastic operator stores elastic user password in a secret
    - name: FLUENT_ELASTICSEARCH_PASSWORD
      valueFrom:
        secretKeyRef:
          name: "efk-es-elastic-user"
          key: elastic
    # Specify TZ
    - name: TZ
      value: "Europe/Madrid"

  # Fluentbit config
  config:
    # fluent-bit.config SERVICE. **NOTE 2**
    # Helm chart defaults are Ok
    # service: |
    #   [SERVICE]
    #     Daemon Off
    #     Flush 1
    #     Log_Level info
    #     Parsers_File parsers.conf
    #     Parsers_File custom_parsers.conf
    #     HTTP_Server On
    #     HTTP_Listen 0.0.0.0
    #     HTTP_Port 2020
    #     Health_Check On

    # fluent-bit.config INPUT. **NOTE 3**
    inputs: |

      [INPUT]
          Name tail
          Path /var/log/containers/*.log
          multiline.parser cri
          Tag kube.*
          DB /var/log/flb_kube.db
          Mem_Buf_Limit 5MB
          Skip_Long_Lines True

      [INPUT]
          Name tail
          Tag node.var.log.auth
          Path /var/log/auth.log
          DB /var/log/flb_auth.db
          Parser syslog-rfc3164-nopri

      [INPUT]
          Name tail
          Tag node.var.log.syslog
          Path /var/log/syslog
          DB /var/log/flb_syslog.db
          Parser syslog-rfc3164-nopri
    # fluent-bit.config OUTPUT **NOTE 4**
    outputs: |

      [OUTPUT]
          Name es
          match *
          Host ${FLUENT_ELASTICSEARCH_HOST}
          Port ${FLUENT_ELASTICSEARCH_PORT}
          Logstash_Format True
          Logstash_Prefix logstash
          Include_Tag_Key True
          Tag_Key tag
          HTTP_User ${FLUENT_ELASTICSEARCH_USER}
          HTTP_Passwd ${FLUENT_ELASTICSEARCH_PASSWORD}
          tls True
          tls.verify False
          Retry_Limit False
    # fluent-bit.config PARSERS **NOTE 5**
    customParsers: |

      [PARSER]
          Name syslog-rfc3164-nopri
          Format regex
          Regex /^(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\/\.\-]*)(?:\[(?<pid>[0-9]+)\])?(?:[^\:]*\:)? *(?<message>.*)$/
          Time_Key time
          Time_Format %b %d %H:%M:%S
          Time_Keep False

    # fluent-bit.config FILTERS **NOTE 6**
    filters: |

      [FILTER]
          Name kubernetes
          Match kube.*
          Merge_Log True
          Keep_Log False
          K8S-Logging.Parser True
          K8S-Logging.Exclude True

      [FILTER]
          name lua
          match node.*
          script /fluent-bit/scripts/adjust_ts.lua
          call local_timestamp_to_UTC

  # Fluentbit config Lua Scripts. **NOTE 7**
  luaScripts:
    adjust_ts.lua: |
      function local_timestamp_to_UTC(tag, timestamp, record)
          local utcdate   = os.date("!*t", ts)
          local localdate = os.date("*t", ts)
          localdate.isdst = false -- this is the trick
          utc_time_diff = os.difftime(os.time(localdate), os.time(utcdate))
          return 1, timestamp - utc_time_diff, record
      end

  # Enable fluentbit instalaltion on master node. **NOTE 8**
  tolerations:
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule

  # Init container. Create directory for fluentbit db **NOTE 9**
  initContainers:
    - name: init-log-directory
      image: busybox
      command: ['/bin/sh', '-c', 'if [ ! -d /var/log/fluentbit ]; then mkdir -p /var/log/fluentbit; fi']
      volumeMounts:
        - name: varlog
          mountPath: /var/log
  ```
  **NOTE 1: Daemonset pod environment variables**

  Elasticsearch connection details (IP and port) and access credentials are passed as environment variables to the fluentbit pod (`elastic` user password obtaining from the corresponding Secret).

  TimeZone (`TZ`) need to be specified so Fluentbit can properly parse logs which timestamp do not contain timezone information (i.e: OS Ubuntu logs like `/var/log/syslog` and `/var/log/auth.log`). 

  **NOTE 2: Fluentbit SERVICE configuration**
  
  [SERVER] configuration provided by default by the helm chart, enables the HTTP server for being able to scrape Prometheus metric.
  
  **NOTE 3: Fluentbit INPUT configuration**

  [INPUT] default configurationonly parse kuberentes logs, supporting the parsing of multiline logs in multipleformats (docker and cri-o). cri is the format we are interested in.
    ```
    [INPUT]
          Name tail
          Path /var/log/containers/*.log
          multiline.parser docker, cri
          Tag kube.*
          Mem_Buf_Limit 5MB
          Skip_Long_Lines On
    ```
  This is a new multiline core 1.8 functionality (https://docs.fluentbit.io/manual/pipeline/inputs/tail#multiline-core-v1.8). 
  The two options in `multiline.parser` separated by a comma means multi-format: try docker and cri multiline formats.

  For contained logs multiline parser cri is needed. Embedded implementation of this parser applies the following regexp to the input lines:

    "^(?<time>.+) (?<stream>stdout|stderr) (?<_p>F|P) (?<log>.*)$"

  > NOTE: See implementation in go [code](https://github.com/fluent/fluent-bit/blob/master/src/multiline/flb_ml_parser_cri.c)

  Fourth field ("F/P") indicates whether the log is full (one line) or partial (more lines are expected)
    See more details in this fluentbit [feature request](https://github.com/fluent/fluent-bit/issues/1316)

  It also configured the log parsing of a systemd `kubelet.system` service, that it is not available in K3S
  
    ```
        [INPUT]
          Name systemd
          Tag host.*
          Systemd_Filter _SYSTEMD_UNIT=kubelet.service
          Read_From_Tail On
    ``` 
  Default configuration need to be changed since K3S does not use default docker output (it uses cri with specific Time format and it does not install a systemd `kubelet.service`.

  Additional inputs need to be configured for extracting logs from host (`/var/logs/auth` and `/var/log/syslog`)

  **NOTE 4: Fluentbit OUTPUT configuration**

  [OUTPUT] configuration by default uses elasticsearch, but it needs to be modified for specifying the access credentials and https protocol specific parameters (use tls and skip SSL certification validation)

  **NOTE 5: Fluentbit PARSER configuration**

  [PARSER] default configuration need to be changed to include specific parser for the syslog formats without priority used by Ubuntu in its authentication and syslog files (`/var/log/auth.log` and `/var/log/syslog`).
  
  **NOTE 6: Fluentbit FILTERS configuration**

  [FILTERS] default helm chart configuration includes a filter for enriching logs with Kubernetes metadata. See [documentation](https://docs.fluentbit.io/manual/pipeline/filters/kubernetes).

  Default configuration need to be modified to include local-time-to-utc filter (Lua script), which translates all logs timestamps to UTC for all node local logs (`/var/log/syslog` and `/var/log/auth.log`). Time field included in these logs does not contain information about TimeZone and when parsing them Fluentbit/Elasticsearch assume they are in UTC timezone displaying them in the future, which in my case it is wrong (`Europe/Madrid` timezone).
  
  See issue [#5](https://github.com/ricsanfre/pi-cluster/issues/5)
  
  **NOTE 7: Lua scripts**
  Helm chart supports the specification of Lua scripts to be used by FILTERS. Helm chart creates a specific ConfigMap with the content of the Lua scripts that are mounted by the pod.

  **NOTE 8: Enable daemonset deployment of master node**
  `tolerantions` section need to be provided.

  **NOTE 9: Init container for creating fluentbit DB temporary directory**
  Configure a `initContainer` based on `busybox` image that creates a directory `/var/logs/fluentbit` to store fluentbit Tail database keeping track of monitored files and offsets (`Tail` input `DB` parameter).
  
- Step 4. Install chart

      helm install fluent-bit fluent/fluent-bit -f values.yml --namespace k3s-logging
 
### Alternative to Fluentbit (Fluentd)

Fluentd will be deployed on Kubernetes as a DaemonSet, which is a Kubernetes workload type that runs a copy of a given Pod on each Node in the Kubernetes cluster. Using this DaemonSet controller, a Fluentd logging agent Pod will be deployed on every node of the cluster. To learn more about this logging architecture, consult [“Using a node logging agent”](https://kubernetes.io/docs/concepts/cluster-administration/logging/#using-a-node-logging-agent) from the official Kubernetes docs.

In addition to container logs, the Fluentd agent will tail Kubernetes system component logs like kubelet, kube-proxy, and Docker logs. To see a full list of sources tailed by the Fluentd logging agent, consult the [`kubernetes.conf`](https://github.com/fluent/fluentd-kubernetes-daemonset/blob/master/docker-image/v1.14/arm64/debian-elasticsearch7/conf/kubernetes.conf) file used to configure the logging agent.

Fluentd can be deployed on Kubernetes cluster as a daemonset pod  using fluentd community docker images in [`fluent-kubernetes-daemonset` repo](https://github.com/fluent/fluentd-kubernetes-daemonset). Different docker images are provided pre-configured for collecting and parsing kuberentes logs and to inject them into different destinations, one of them is elasticsearch.

Further documentation can be found [here](https://docs.fluentd.org/container-deployment/kubernetes) and different backends manifest sample files are provided in `fluentd-kubernetes-daemonset` repo. For using elasticsearh as backend we will use a manifest file based on this [spec](https://github.com/fluent/fluentd-kubernetes-daemonset/blob/master/fluentd-daemonset-elasticsearch-rbac.yaml)

Fluentd default image and manifest files need to be adapted for parsing containerd logs. `fluentd -kubernets-daemonsset` images by default are configured for parsing docker logs. See this [issue](https://github.com/fluent/fluentd-kubernetes-daemonset/issues/412)

- Step 1. Create and apply a manifest file for fluentd role and password

  Fluentd need to access to kubernetes API for querying resources

  ```yml
  ---
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: fluentd
    namespace: k3s-logging
  ---
  apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRole
  metadata:
    name: fluentd
  rules:
  - apiGroups:
    - ""
    resources:
    - pods
    - namespaces
    verbs:
    - get
    - list
    - watch
  ---
  kind: ClusterRoleBinding
  apiVersion: rbac.authorization.k8s.io/v1
  metadata:
    name: fluentd
  roleRef:
    kind: ClusterRole
    name: fluentd
    apiGroup: rbac.authorization.k8s.io
  subjects:
  - kind: ServiceAccount
    name: fluentd
    namespace: "{{ k3s_logging_namespace }}"
  ```

- Step 2. Create and apply manifest file for fluend additional configuration

  By default `fluentd-kubernetes-daemonset` image configuration add the basic configuration for collecting and parsing kubernetes pods and processes logs and injecting into elasticsearch database.

  No configuration is included for collecting and parsing other logs from the nodes, like /var/log/auth.log (containing all authentication logs) or /var/log/syslog (containing all important node level logs).

  Fluentd images load the configuration from [`/fluentd/etc/fluent.conf`](https://github.com/fluent/fluentd-kubernetes-daemonset/blob/master/docker-image/v1.14/debian-elasticsearch7/conf/fluent.conf). This file contains the configuration for injecting all data into elasticsearh and to include `kubernets.conf` file which contains all kubernetes logs parsing configuration. As well a include statement load all configuration stored in `/fluentd/etc/conf.d` 

  ```
  # AUTOMATICALLY GENERATED
  # DO NOT EDIT THIS FILE DIRECTLY, USE /templates/conf/fluent.conf.erb

  @include "#{ENV['FLUENTD_SYSTEMD_CONF'] || 'systemd'}.conf"
  @include "#{ENV['FLUENTD_PROMETHEUS_CONF'] || 'prometheus'}.conf"
  @include kubernetes.conf
  @include conf.d/*.conf

  <match **>
    @type elasticsearch
    @id out_es
    @log_level info
    include_tag_key true
    host "#{ENV['FLUENT_ELASTICSEARCH_HOST']}"
    port "#{ENV['FLUENT_ELASTICSEARCH_PORT']}"

  ...

  ```

  Additional configuration files for parsing auth.log and syslog.log need to be created and passing them to the pod within /fluent/etc/conf.d directory. For doing that a ConfigMap will be created and mounted on fluentd container as /fluentd/etc/conf.d volume.

  ```yml
  apiVersion: v1
  data:
    # Additional configuration for parsing auth.log file
    auth.conf: |-
      <source>
        @type tail
        path /var/log/auth.log
        pos_file /var/log/auth.pos
        tag authlog
        <parse>
          @type syslog
          message_format rfc3164
          with_priority false
        </parse>
      </source>
    # Additional configuraion for pasing syslog.file
    syslog.conf: |-
      <source>
        @type tail
        path /var/log/syslog.log
        pos_file /var/log/syslog.pos
        tag syslog
        <parse>
          @type syslog
          message_format rfc3164
          with_priority false
        </parse>
      </source>

  kind: ConfigMap
  metadata:
    labels:
      stack: efk
    name: fluentd-config
    namespace: k3s-logging

  ```

  - Step 3. Create and apply manifest file for daemonset fluentd pod

  ```yml
  apiVersion: apps/v1
  kind: DaemonSet
  metadata:
    name: fluentd
    namespace: k3s-logging
    labels:
      k8s-app: fluentd-logging
      version: v1
  spec:
    selector:
      matchLabels:
        k8s-app: fluentd-logging
        version: v1
    template:
      metadata:
        labels:
          k8s-app: fluentd-logging
          version: v1
      spec:
        serviceAccount: fluentd
        serviceAccountName: fluentd
        tolerations:
        # Schedule this pod on master node
        - key: node-role.kubernetes.io/master
          operator: Exists
          effect: NoSchedule
        containers:
        - name: fluentd
          image: fluent/fluentd-kubernetes-daemonset:v1.14-debian-elasticsearch7-1
          env:
            # Elastic operator creates elastic service name with format cluster_name-es-http
            - name:  FLUENT_ELASTICSEARCH_HOST
              value: efk-es-http
            # Default elasticsearch default port
            - name:  FLUENT_ELASTICSEARCH_PORT
              value: "9200"
            # Elastic operator enables only HTTPS channels to elaticsearch
            - name: FLUENT_ELASTICSEARCH_SCHEME
              value: "https"
            # Elastic operator creates auto-signed certificates, verification must be disabled
            - name: FLUENT_ELASTICSEARCH_SSL_VERIFY
              value: "false"
            # Elasticsearch user
            - name: FLUENT_ELASTICSEARCH_USER
              value: "elastic"
            # Elastic operator stores elastic user password in a secret
            - name: FLUENT_ELASTICSEARCH_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "efk-es-elastic-user"
                  key: elastic
            # Setting a index-prefix for fluentd. By default index is logstash
            - name:  FLUENT_ELASTICSEARCH_INDEX_NAME
              value: fluentd
            # Use cri parser for contarinerd based pods
            - name: FLUENT_CONTAINER_TAIL_PARSER_TYPE
              value: "cri"
            # Use proper time format parsing for containerd logs
            - name: FLUENT_CONTAINER_TAIL_PARSER_TIME_FORMAT
              value: "%Y-%m-%dT%H:%M:%S.%N%:z"
          resources:
            limits:
              memory: 200Mi
            requests:
              cpu: 100m
              memory: 200Mi
          volumeMounts:
          # Fluentd need access to node logs /var/log
          - name: varlog
            mountPath: /var/log
          # Fluentd need access to pod logs /var/log/pods
          - name: dockercontainerlogdirectory
            mountPath: /var/log/pods
            readOnly: true
          # Mounting additional fluentd configuration files
          - name: fluentd-additional-config-vol
            mountPath: /fluentd/etc/conf.d
        terminationGracePeriodSeconds: 30
        volumes:
        - name: varlog
          hostPath:
            path: /var/log
        - name: dockercontainerlogdirectory
          hostPath:
            path: /var/log/pods
        - name: fluentd-additional-config-vol
          configMap:
            # holds the different fluentd configuration files
            name: fluentd-config
  ```


## Gathering logs from servers outside the kubernetes cluster

For gathering the logs from `gateway` server fluentbit can be installed. Fluentbit is a lightweight version of fluentd ( just 640 KB not requiring any gem library to be installed) See comparison [here](https://docs.fluentbit.io/manual/about/fluentd-and-fluent-bit)
There official packages for Ubuntu. Installation instructions can be found [here](https://docs.fluentbit.io/manual/installation/linux/ubuntu).

For automating configuration tasks, ansible role [**ricsanfre.fluentbit**](https://galaxy.ansible.com/ricsanfre/fluentbit) has been developed.

Fluentbit role input and parsing rules are defined through variables for `control` inventory (group_vars/control.yml), to which gateway belongs to.

```yml
fluentbit_inputs:
  - Name: tail
    Tag: auth
    Path: /var/log/auth.log
    Path_key: log_file
    DB: /run/fluent-bit-auth.state
    Parser: syslog-rfc3164-nopri
  - Name: tail
    Tag: syslog
    Path: /var/log/syslog
    Path_key: log_file
    DB: /run/fluent-bit-syslog.state
    Parser: syslog-rfc3164-nopri
# Fluentbit Elasticsearch output
fluentbit_outputs:
  - Name: es
    match: "*"
    Host: 10.0.0.101
    Port: 9200
    Logstash_Format: On
    Logstash_Prefix: logstash
    Include_Tag_Key: On
    Tag_Key: tag
    HTTP_User: elastic
    HTTP_Passwd: s1cret0
    tls: On
    tls.verify: Off
    Retry_Limit: False
# Fluentbit custom parsers
fluentbit_custom_parsers:
  - Name: syslog-rfc3164-nopri
    Format: regex
    Regex: /^(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\/\.\-]*)(?:\[(?<pid>[0-9]+)\])?(?:[^\:]*\:)? *(?<message>.*)$/
    Time_Key: time
    Time_Format: "%b %d %H:%M:%S"
    Time_Keep: false

# Fluentbit_filters
fluentbit_filters:
  - name: lua
    match: "*"
    script: /etc/td-agent-bit/adjust_ts.lua
    call: local_timestamp_to_UTC

```
With this rules Fluentbit will monitoring log entries in `/var/log/auth.log` and `/var/log/syslog` files, parsing them using a custom parser `syslog-rfc3165-nopri` (syslog default parser removing priority field) and forward them to elasticsearch server running on K3S cluster.

Lua script need to be included for translaing local time zone (`Europe\Madrid`) to UTC and the corresponding filter need to be executed. See issue [#5](https://github.com/ricsanfre/pi-cluster/issues/5).

# References

[1] Kubernetes logging architecture (https://www.magalix.com/blog/kubernetes-logging-101) (https://www.magalix.com/blog/kubernetes-observability-log-aggregation-using-elk-stack)

[2] Fluentd vs Logstash (https://platform9.com/blog/kubernetes-logging-comparing-fluentd-vs-logstash/)

[3] EFK on Kubernetes tutorials (https://www.digitalocean.com/community/tutorials/how-to-set-up-an-elasticsearch-fluentd-and-kibana-efk-logging-stack-on-kubernetes) (https://platform9.com/blog/kubernetes-logging-and-monitoring-the-elasticsearch-fluentd-and-kibana-efk-stack-part-1-fluentd-architecture-and-configuration/)

[4] ELK on Kubernetes tutorials (https://coralogix.com/blog/running-elk-on-kubernetes-with-eck-part-1/) (https://www.deepnetwork.com/blog/2020/01/27/ELK-stack-filebeat-k8s-deployment.html)

[5] Fluentd in Kubernetes (https://docs.fluentd.org/container-deployment/kubernetes)
