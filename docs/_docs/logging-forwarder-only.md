---
title: Log collection, aggregation and distribution (Forwarders-only architecture)
permalink: /docs/logging-forwarder-only/
description: How to deploy fluentbit or fluentd to collect all kubernetes logs and load them to ES. Forwarder-only deployment pattern as alternative to forwarder/aggregator pattern.
last_modified_at: "20-07-2022"
---

Both fluentbit and fluentd can be deployed as forwarder-only to collect all kubernetes logs and load them to the backend (ES) directly without aggregation layer. Also they can be deployed as daemonset on kubernetes nodes using the official helm charts.

## Fluentbit-based Agent

Fluentbit can be installed and configured to collect and parse Kubernetes logs deploying it as a daemonset pod. See fluenbit documentation on how to install it on Kuberentes cluster: ["Fluentbit: Kubernetes Production Grade Log Processor"](https://docs.fluentbit.io/manual/installation/kubernetes).

For speed-up the installation there is available a [helm chart](https://github.com/fluent/helm-charts/tree/main/charts/fluent-bit). fluentbit config file can be 


- Step 1. Add fluentbit helm repo
  ```shell
  helm repo add fluent https://fluent.github.io/helm-charts
  ```
- Step 2. Update helm repo
  ```shell
  helm repo update
  ```
- Step 3. Create `values.yml` for tuning helm chart deployment.
  
  fluentbit configuration can be provided to the helm. See [`values.yml`](https://github.com/fluent/helm-charts/blob/main/charts/fluent-bit/values.yaml)
  
  The final `values.yml` is:
  
  ```yml
  ---
  # fluentbit helm chart values

  # fluentbit-container environment variables.
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
    # Helm chart combines service, inputs, outputs, custom_parsers and filters section
    # fluent-bit.config SERVICE
    service: |

      [SERVICE]
          Daemon Off
          Flush 1
          Log_Level info
          Parsers_File parsers.conf
          Parsers_File custom_parsers.conf
          HTTP_Server On
          HTTP_Listen 0.0.0.0
          HTTP_Port 2020
          Health_Check On

    # fluent-bit.config INPUT. **NOTE 3**
    inputs: |

      [INPUT]
          Name tail
          Path /var/log/containers/*.log
          multiline.parser docker, cri
          DB /var/log/fluentbit/flb_kube.db
          Tag kube.*
          Mem_Buf_Limit 5MB
          Skip_Long_Lines True

      [INPUT]
          Name tail
          Tag host.*
          DB /var/log/fluentbit/flb_host.db
          Path /var/log/auth.log,/var/log/syslog
          Parser syslog-rfc3164-nopri

    outputs: |

      [OUTPUT]
          Name es
          match *
          Host ${FLUENT_ELASTICSEARCH_HOST}
          Port ${FLUENT_ELASTICSEARCH_PORT}
          Logstash_Format True
          Logstash_Prefix logstash
          Suppress_Type_Name True
          Include_Tag_Key True
          Tag_Key tag
          HTTP_User ${FLUENT_ELASTICSEARCH_USER}
          HTTP_Passwd ${FLUENT_ELASTICSEARCH_PASSWORD}
          tls False
          tls.verify False
          Retry_Limit False

    # fluent-bit.config PARSERS
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
          Kube_Tag_Prefix kube.var.log.containers.
          Merge_Log True
          Merge_Log_Trim True
          Keep_Log False
          K8S-Logging.Parser True
          K8S-Logging.Exclude False
          Annotations False
          Labels False

      [FILTER]
          Name nest
          Match kube.*
          Operation lift
          Nested_under kubernetes
          Add_prefix kubernetes_

      [FILTER]
          Name modify
          Match kube.*
          Rename kubernetes_pod_name k8s.pod.name
          Rename kubernetes_namespace_name k8s.namespace.name
          Rename kubernetes_container_name k8s.container.name
          Remove kubernetes_container_image
          Remove kubernetes_docker_id
          Remove kubernetes_pod_id
          Remove kubernetes_host
          Remove kubernetes_container_hash
          Remove stream
          Remove _p
          Rename log message
          Add k8s.cluster.name picluster

      [FILTER]
          Name lua
          Match host.*
          script /fluent-bit/scripts/adjust_ts.lua
          call local_timestamp_to_UTC

  # Fluentbit config Lua Scripts.
  luaScripts:
    adjust_ts.lua: |
      function local_timestamp_to_UTC(tag, timestamp, record)
          local utcdate   = os.date("!*t", ts)
          local localdate = os.date("*t", ts)
          localdate.isdst = false -- this is the trick
          utc_time_diff = os.difftime(os.time(localdate), os.time(utcdate))
          return 1, timestamp - utc_time_diff, record
      end

  # Enable fluentbit installation on master node.
  tolerations:
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule

  # Init container. Create directory for fluentbit db
  initContainers:
    - name: init-log-directory
      image: busybox
      command: ['/bin/sh', '-c', 'if [ ! -d /var/log/fluentbit ]; then mkdir -p /var/log/fluentbit; fi']
      volumeMounts:
        - name: varlog
          mountPath: /var/log
  ```

- Step 4. Install chart
  ```shell
  helm install fluent-bit fluent/fluent-bit -f values.yml --namespace k3s-logging
  ```

  {{site.data.alerts.note}} **Chart configuration details**

  [Configuration chart is almost the same as the one described in forwader/aggregator architecture](/docs/logging-forwarder-aggregator/#fluentbit-chart-configuration-details).
   
  Changes:

  - Environment variables

    Elasticsearch connection details (IP: `FLUENT_ELASTICSEARCH_HOST` and port: `FLUENT_ELASTICSEARCH_PORT` ) and access credentials (`FLUENT_ELASTICSEARCH_USER` and `FLUENT_ELASTICSEARCH_PASSWD`) are passed as environment variables to the fluentbit pod (`elastic` user password obtaining from the corresponding Secret).

  - Output configuration

    [OUTPUT] configuration routes the logs to elasticsearch.

    ```
    [OUTPUT]
        Name es
        match *
        Host ${FLUENT_ELASTICSEARCH_HOST}
        Port ${FLUENT_ELASTICSEARCH_PORT}
        Logstash_Format True
        Logstash_Prefix logstash
        Suppress_Type_Name True
        Include_Tag_Key True
        Tag_Key tag
        HTTP_User ${FLUENT_ELASTICSEARCH_USER}
        HTTP_Passwd ${FLUENT_ELASTICSEARCH_PASSWORD}
        tls False
        tls.verify False
        Retry_Limit False
    ```
    
    `tls` option is disabled (set to False/Off). TLS communications are enabled by linkerd service mesh.

    `Suppress_Type_Name` option must be enabled (set to On/True). When enabled, mapping types is removed and Type option is ignored. Types are deprecated in APIs in v7.0. This option need to be disabled to avoid errors when injecting logs into elasticsearch:

    ```json
    {"error":{"root_cause":[{"type":"illegal_argument_exception","reason":"Action/metadata line [1] contains an unknown parameter [_type]"}],"type":"illegal_argument_exception","reason":"Action/metadata line [1] contains an unknown parameter [_type]"},"status":400}
    ``` 
    In release v7.x the log is just a warning but in v8 the error causes fluentbit to fail injecting logs into Elasticsearch.

  {{site.data.alerts.end}}
  

## Fluentd-based Agent

Fluentd also can be installed and configured to collect and parse Kubernetes logs deploying it as a daemonset pod. See fluenbit documentation on how to install it on Kuberentes cluster: ["Fluentd: Container Deployment - Kubernetes"](https://docs.fluentd.org/container-deployment/kubernetes).


Fluentd can be deployed on Kubernetes cluster as a daemonset pod  using fluentd community docker images in [`fluent-kubernetes-daemonset` repo](https://github.com/fluent/fluentd-kubernetes-daemonset). Different docker images are provided pre-configured for collecting and parsing kuberentes logs and to inject them into different stinations, one of them is elasticsearch.

This docker images by default fluentd agent parse container logs, and Kubernetes system component logs like kubelet, kube-proxy, and Docker logs. To see a full list of sources tailed by the Fluentd logging agent, consult the [`kubernetes.conf`](https://github.com/fluent/fluentd-kubernetes-daemonset/blob/master/docker-image/v1.14/arm64/debian-elasticsearch7/conf/kubernetes.conf) file used to configure the logging agent.

Further details can be found in [Fluentd documentation: "Kubernetes deployment"](https://docs.fluentd.org/container-deployment/kubernetes) and different backends manifest sample files are provided in `fluentd-kubernetes-daemonset` Github repo. For using elasticsearh as backend we will use a manifest file based on this [spec](https://github.com/fluent/fluentd-kubernetes-daemonset/blob/master/fluentd-daemonset-elasticsearch-rbac.yaml)

Fluentd default image and manifest files need to be adapted for parsing containerd logs. `fluentd -kubernets-daemonset` images by default are configured for parsing docker logs. See this [issue](https://github.com/fluent/fluentd-kubernetes-daemonset/issues/412)

{{site.data.alerts.note}}

In this case instead of installing fluentd daemonset chart. Manual instalation instructions are provided:

{{site.data.alerts.end}}

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
