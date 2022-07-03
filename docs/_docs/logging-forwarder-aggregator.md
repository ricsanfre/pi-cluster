---
title: Log collection, aggregation and distribution (forwarder/aggregator)
permalink: /docs/logging-forwarder-aggregator/
description: How to deploy logging collection, aggregation and distribution in our Raspberry Pi Kuberentes cluster. Deploy a forwarder/aggregator architecture using Fluentbit and Fluentd. Logs are routed to Elasticsearch, so log analytics can be done using Kibana.

last_modified_at: "03-07-2022"

---

A Forwarder/Aggregator log architecture will be implemented in the Kuberntes cluster with Fluentbit and Fluentd.

Both fluentbit and fluentd can be deployed as forwarder and/or aggregator.

The differences between fluentbit and fluentd can be found in [Fluentbit documentation: "Fluentd & Fluent Bit"](https://docs.fluentbit.io/manual/about/fluentd-and-fluent-bit).

Main differences are:

- Memory footprint: Fluentbit is a lightweight version of fluentd (just 640 KB memory)

- Number of plugins (input, output, filters connectors): Fluentd has more plugins available, but those plugins need to be installed as gem libraries. Fluentbit's plugins do not need to be installed.

In this deployment fluentbit is installed as forwarder (plugins available are enough for collecting and parsing kubernetes logs and host logs) and fluentd as aggregator to leverage the bigger number of plugins available.


## Fluentd Aggregator installation

Fluentd is deploy as log aggregator, collecting all logs forwarded by Fluentbit agent and using ES as backend for routing all logs.

Fluentd will be deployed as Kubernetes Deployment (not a daemonset), enabling multiple PODs service replicas, so it can be accesible by Fluentbit pods.

### Customized fluentd image

Fluentd official images do not contain any of the plugins (elasticsearch, prometheus monitoring, etc.) that are needed. A customized fluentd image need to be built.

{{site.data.alerts.tip}}

You can create your own customized docker image or use mine. You can find it in [ricsanfre/fluentd-aggregator github repository](https://github.com/ricsanfre/fluentd-aggregator).
These images are available in docker hub:

- `ricsanfre/fluentd-aggregator:v1.14-debian-1`: for amd64 architectures

- `ricsanfre/fluentd-aggregator:v1.14-debian-arm64-1`: for arm64 architectures

{{site.data.alerts.end}}

As base image, the [official fluentd docker image](https://github.com/fluent/fluentd-docker-image) can be used. To customize it, follow the instructions in the project repository: ["Customizing the image to intall additional plugins"](https://github.com/fluent/fluentd-docker-image#3-customize-dockerfile-to-install-plugins-optional).

In our case, the list of plugins that need to be added to the default fluentd image are:

- `fluent-plugin-elasticsearch`: ES as backend for routing the logs

- `fluent-plugin-prometheus`: Enabling prometheus monitoring

Additionally default fluentd config can be added to the customized docker image, so fluentd can be configured as log aggregator, collecting logs from forwarders (fluentbit/fluentd) and routing all logs to elasticsearch. 
This fluentd configuration in the docker image can be overwritten when deploying the container in kubernetes, using a [ConfigMap](https://kubernetes.io/es/docs/concepts/configuration/configmap/) mounted as a volume, or when running with `docker run`, using a [bind mount](https://docs.docker.com/storage/bind-mounts/). In both cases the target volume to be mounted is where fluentd expects the configuration files (`/fluentd/etc` in the official images).

{{site.data.alerts.important}}

`fluent-plugin-elasticsearch` plugin configuration requires to set a specific sniffer class for implementing reconnection logic to ES(`sniffer_class_name Fluent::Plugin::ElasticsearchSimpleSniffer`). See plugin documentation [fluent-plugin-elasticsearh: Sniffer Class Name](https://github.com/uken/fluent-plugin-elasticsearch#sniffer-class-name).

The path to the sniffer class need to be passed as parameter to `fluentd` command (-r option), otherwise the fluentd command will give an error

Docker's `entrypoint.sh` in the customized image has to be updated to automatically provide the path to the sniffer class.

```sh
# First step looking for the sniffer ruby class within the plugin
SIMPLE_SNIFFER=$( gem contents fluent-plugin-elasticsearch | grep elasticsearch_simple_sniffer.rb )

# Execute fluentd command with -r option for loading the required ruby class
fluentd -c ${FLUENTD_CONF} ${FLUENTD_OPT} -r ${SIMPLE_SNIFFER}
```

{{site.data.alerts.end}}


Customized image Dockerfile could look like this:

```dockerfile
ARG BASE_IMAGE=fluent/fluentd:v1.14-debian-1

FROM $BASE_IMAGE

## 1- Update base image installing fluent plugins. Executing commands `gem install <plugin_name>`

# Use root account to use apk
USER root

RUN buildDeps="sudo make gcc g++ libc-dev" \
 && apt-get update \
 && apt-get install -y --no-install-recommends $buildDeps \
 && sudo gem install fluent-plugin-elasticsearch \
 && sudo gem install fluent-plugin-prometheus \
 && sudo gem sources --clear-all \
 && SUDO_FORCE_REMOVE=yes \
    apt-get purge -y --auto-remove \
                  -o APT::AutoRemove::RecommendsImportant=false \
                  $buildDeps \
 && rm -rf /var/lib/apt/lists/* \
 && rm -rf /tmp/* /var/tmp/* /usr/lib/ruby/gems/*/cache/*.ge

## 2) (Optional) Copy customized fluentd config files (fluentd as aggregator)
COPY ./conf/* /fluentd/etc/

## 3) Modify entrypoint.sh to configure sniffer class
COPY entrypoint.sh /bin/

## 4) Change to fluent user to run fluentd
USER fluent
ENTRYPOINT ["tini",  "--", "/bin/entrypoint.sh"]
CMD ["fluentd"]
```

{{site.data.alerts.important}}

Fluentd official images are not built with multi-architecture support. Different base images need to be used for different architectures. Docker building argument BASE_IMAGE has to be set to use the proper image:

- `fluent/fluentd:v1.14-debian-1`: for building amd64 docker image

- `fluent/fluentd:v1.14-debian-arm64-1`: for building arm64 docker image

{{site.data.alerts.end}}

### Deploying fluentd in K3S

Fluentd will not be deployed as privileged daemonset, since it does not need to access to kubernetes logs/APIs. It will be deployed using the following Kubernetes resources:

- Certmanager's Certificate resource: so certmanager can generate automatically a Kubernetes TLS Secret resource containing fluentd's TLS certificate so secure communications can be enabled between forwarders and aggregator

- Kubernetes Secret resource to store a shared secret to enable forwarders authentication when connecting to fluentd

- Kubernetes Deployment resource to deploy fluentd as stateless POD. Number of replicas can be set to provide HA to the service

- Kubernetes Service resource, Cluster IP type, exposing fluentd endpoints to other PODs/processes: Fluentbit forwarders, Prometheus, etc.

- Kubernetes ConfigMap resource containing fluentd config files.

**Installation procedure:**

- Step 1. Create fluentd TLS certificate to enable secure communications between forwarders and aggregator.

  To configure fluentd to use TLS, it is needed the path to the files containing the TLS certificate and private key. The TLS Secret containing the certificate and key can be mounted in fluentd POD in a specific location (/fluentd/certs), so fluentd daemon can use them.

  Certmanager's ClusterIssuer `ca-issuer`, created during [certmanager installation](/docs/certmanager/), will be used to generate fluentd's TLS Secret automatically.

  Create the Certificate resource:

  ```yml
  apiVersion: cert-manager.io/v1
  kind: Certificate
  metadata:
    name: fluentd-tls
    namespace: k3s-logging
  spec:
    # Secret names are always required.
    secretName: fluentd-tls
    duration: 2160h # 90d
    renewBefore: 360h # 15d
    commonName: fluentd.picluster.ricsanfre.com
    isCA: false
    privateKey:
      algorithm: ECDSA
      size: 256
    usages:
      - server auth
      - client auth
    dnsNames:
      - fluentd.picluster.ricsanfre.com
    isCA: false
    # ClusterIssuer: ca-issuer.
    issuerRef:
      name: ca-issuer
      kind: ClusterIssuer
      group: cert-manager.io
  ```

  Then, Certmanager automatically creates a Secret like this:

  ```yml
  apiVersion: v1
  kind: Secret
  metadata
    name: fluentd-tls
    namespace: k3s-logging
  type: kubernetes.io/tls
  data:
    ca.crt: <ca cert content base64 encoded>
    tls.crt: <tls cert content base64 encoded>
    tls.key: <private key base64 encoded>
  ```

- Step 2. Create forward protocol shared key

  Generate base64 encoded shared key
  ```shell
  echo -n 'supersecret' | base64
  ```

  Create a Secret `fluentd-shared-key` containing the shared key
  ```yml
  apiVersion: v1
  kind: Secret
  metadata:
    name: fluentd-shared-key
    namespace: k3s-logging
  type: Opaque
  data:
    fluentd-shared-key: <base64 encoded password>
  ```

- Step 3. Create a ConfigMap containing fluentd configuration
  
  ```yml
  # ConfigMap containing fluentd configuration
  # Mounted by the container and mapped to `/etc/fluentd/`
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: fluentd-config
    namespace: k3s-logging
  data:
    fluent.conf: |-
      # Collect logs from forwarders
      <source>
        @type forward
        bind "#{ENV['FLUENTD_FORWARD_BIND'] || '0.0.0.0'}"
        port "#{ENV['FLUENTD_FORWARD_PORT'] || '24224'}"
        # Enabling TLS
        <transport tls>
            cert_path /fluentd/certs/tls.crt
            private_key_path /fluentd/certs/tls.key
        </transport>
        # Enabling access security
        <security>
          self_hostname "#{ENV['FLUENTD_FORWARD_SEC_SELFHOSTNAME'] || 'fluentd-aggregator'}"
          shared_key "#{ENV['FLUENTD_FORWARD_SEC_SHARED_KEY'] || 'sharedkey'}"
        </security>
      </source>
      # Prometheus metric exposed on 0.0.0.0:24231/metrics
      <source>
        @type prometheus
        @id in_prometheus
        bind "#{ENV['FLUENTD_PROMETHEUS_BIND'] || '0.0.0.0'}"
        port "#{ENV['FLUENTD_PROMETHEUS_PORT'] || '24231'}"
        metrics_path "#{ENV['FLUENTD_PROMETHEUS_PATH'] || '/metrics'}"
      </source>
      <source>
        @type prometheus_output_monitor
        @id in_prometheus_output_monitor
      </source>
      # Send received logs to elasticsearch
      <match **>
         @type elasticsearch
         @id out_es
         @log_level info
         include_tag_key true
         host "#{ENV['FLUENT_ELASTICSEARCH_HOST']}"
         port "#{ENV['FLUENT_ELASTICSEARCH_PORT']}"
         path "#{ENV['FLUENT_ELASTICSEARCH_PATH']}"
         scheme "#{ENV['FLUENT_ELASTICSEARCH_SCHEME'] || 'http'}"
         ssl_verify "#{ENV['FLUENT_ELASTICSEARCH_SSL_VERIFY'] || 'true'}"
         ssl_version "#{ENV['FLUENT_ELASTICSEARCH_SSL_VERSION'] || 'TLSv1_2'}"
         user "#{ENV['FLUENT_ELASTICSEARCH_USER'] || use_default}"
         password "#{ENV['FLUENT_ELASTICSEARCH_PASSWORD'] || use_default}"
         reload_connections "#{ENV['FLUENT_ELASTICSEARCH_RELOAD_CONNECTIONS'] || 'false'}"
         reconnect_on_error "#{ENV['FLUENT_ELASTICSEARCH_RECONNECT_ON_ERROR'] || 'true'}"
         reload_on_failure "#{ENV['FLUENT_ELASTICSEARCH_RELOAD_ON_FAILURE'] || 'true'}"
         log_es_400_reason "#{ENV['FLUENT_ELASTICSEARCH_LOG_ES_400_REASON'] || 'false'}"
         logstash_prefix "#{ENV['FLUENT_ELASTICSEARCH_LOGSTASH_PREFIX'] || 'logstash'}"
         logstash_dateformat "#{ENV['FLUENT_ELASTICSEARCH_LOGSTASH_DATEFORMAT'] || '%Y.%m.%d'}"
         logstash_format "#{ENV['FLUENT_ELASTICSEARCH_LOGSTASH_FORMAT'] || 'true'}"
         index_name "#{ENV['FLUENT_ELASTICSEARCH_LOGSTASH_INDEX_NAME'] || 'logstash'}"
         target_index_key "#{ENV['FLUENT_ELASTICSEARCH_TARGET_INDEX_KEY'] || use_nil}"
         type_name "#{ENV['FLUENT_ELASTICSEARCH_LOGSTASH_TYPE_NAME'] || 'fluentd'}"
         include_timestamp "#{ENV['FLUENT_ELASTICSEARCH_INCLUDE_TIMESTAMP'] || 'false'}"
         template_name "#{ENV['FLUENT_ELASTICSEARCH_TEMPLATE_NAME'] || use_nil}"
         template_file "#{ENV['FLUENT_ELASTICSEARCH_TEMPLATE_FILE'] || use_nil}"
         template_overwrite "#{ENV['FLUENT_ELASTICSEARCH_TEMPLATE_OVERWRITE'] || use_default}"
         sniffer_class_name "#{ENV['FLUENT_SNIFFER_CLASS_NAME'] || 'Fluent::Plugin::ElasticsearchSimpleSniffer'}"
         request_timeout "#{ENV['FLUENT_ELASTICSEARCH_REQUEST_TIMEOUT'] || '5s'}"
         application_name "#{ENV['FLUENT_ELASTICSEARCH_APPLICATION_NAME'] || use_default}"
         suppress_type_name "#{ENV['FLUENT_ELASTICSEARCH_SUPPRESS_TYPE_NAME'] || 'true'}"
         enable_ilm "#{ENV['FLUENT_ELASTICSEARCH_ENABLE_ILM'] || 'false'}"
         ilm_policy_id "#{ENV['FLUENT_ELASTICSEARCH_ILM_POLICY_ID'] || use_default}"
         ilm_policy "#{ENV['FLUENT_ELASTICSEARCH_ILM_POLICY'] || use_default}"
         ilm_policy_overwrite "#{ENV['FLUENT_ELASTICSEARCH_ILM_POLICY_OVERWRITE'] || 'false'}"
         <buffer>
           flush_thread_count "#{ENV['FLUENT_ELASTICSEARCH_BUFFER_FLUSH_THREAD_COUNT'] || '8'}"
           flush_interval "#{ENV['FLUENT_ELASTICSEARCH_BUFFER_FLUSH_INTERVAL'] || '5s'}"
           chunk_limit_size "#{ENV['FLUENT_ELASTICSEARCH_BUFFER_CHUNK_LIMIT_SIZE'] || '2M'}"
           queue_limit_length "#{ENV['FLUENT_ELASTICSEARCH_BUFFER_QUEUE_LIMIT_LENGTH'] || '32'}"
           retry_max_interval "#{ENV['FLUENT_ELASTICSEARCH_BUFFER_RETRY_MAX_INTERVAL'] || '30'}"
           retry_forever true
         </buffer>
      </match>
  ```

  Fluentd config file (`fluent.conf`) is loaded into a Kubernetes ConfigMap that will be mounted as `/etc/fluentd` within the fluentd pod.

  It configures fluentd as log aggregator. With this configuration fluentd:

  - collects logs from forwarders (port 24224) configuring [forward input plugin](https://docs.fluentd.org/input/forward)

  - enables Prometheus metrics exposure (port 24231) configuring [prometheus input plugin](https://docs.fluentd.org/monitoring-fluentd/monitoring-prometheus). Complete list of configuration parameters in [fluent-plugin-prometheus repository](https://github.com/fluent/fluent-plugin-prometheus)

  - routes all logs to elastic search configuring [elasticsearch output plugin](https://docs.fluentd.org/output/elasticsearch). Complete list of parameters in [fluent-plugin-elasticsearch reporitory](https://github.com/uken/fluent-plugin-elasticsearch)

  Plugin configuration values have been defined using container environment variables with default values in case of not being specified.

- Step 3. Create a Deployment resource

  ```yml
  # Fluentd Deployment
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    labels:
      app: fluentd
    name: fluentd
    namespace: k3s-logging
  spec:
    replicas: 1
    selector:
      matchLabels:
        app: fluentd
    template:
      metadata:
        labels:
          app: fluentd
      spec:
        containers:
        - image: ricsanfre/fluentd-aggregator:v1.14-debian-arm64-1
          imagePullPolicy: Always
          name: fluentd
          env:
            # Elastic operator creates elastic service name with format cluster_name-es-http
            - name:  FLUENT_ELASTICSEARCH_HOST
              value: efk-es-http
              # Default elasticsearch default port
            - name:  FLUENT_ELASTICSEARCH_PORT
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
            # Setting a index-prefix. By default index is logstash-<date>
            - name:  FLUENT_ELASTICSEARCH_LOGSTASH_PREFIX
              value: fluentd
            - name: FLUENT_ELASTICSEARCH_LOG_ES_400_REASON
              value: "true"
            # Fluentd forward security
            - name: FLUENTD_FORWARD_SEC_SHARED_KEY
              valueFrom:
                secretKeyRef:
                  name: fluentd-shared-key
                  key: fluentd-shared-key
          ports:
          - containerPort: 24224
            name: forward
            protocol: TCP
          - containerPort: 24231
            name: prometheus
            protocol: TCP
          volumeMounts:
          - mountPath: /fluentd/etc
            name: config
            readOnly: true
          - mountPath: /fluentd/certs
            name: fluentd-tls
            readOnly: true
        volumes:
        - name: config
          configMap:
            defaultMode: 420
            name: fluentd-config
        - name: fluentd-tls
          secret:
            secretName: fluentd-tls
  ```
  Fluentd POD is deployed as a Deployment using fluentd custom image.

  Elasticsearch plugin configuration are passed to the fluentd pod as environment variables:

  - connection details (`host` and `port`): elasticsearch kubernetes service (`efk-es-http`) and ES port.

  - access credentials (`user` and `password`): elastic user password obtained from the corresponding Secret.

  - additional plugin parameters: setting index prefix (`logstash_prefix`) and enabling debug messages when receiving errors from Elasticsearch API (`log_es_400_reason`)

  - rest of parameters with default values defined in the ConfigMap.

  Forwarder plugin shared key configuration parameter is also passed to fluentd pod as environment variable, loading the content of the secret generated in step 2: `fluentd-shared-key`.

  ConfigMap containing fluentd config is mounted as `/fluentd/etc` volume.

  TLS Secret containing fluentd's certificate and private key is mounted as `/fluentd/certs` 

- Step 4. Create a Service resource to expose fluentd endpoints internally within the cluster
  
  ```yml
  apiVersion: v1
  kind: Service
  metadata:
    labels:
      app: fluentd
    name: fluentd
    namespace: k3s-logging
  spec:
    ports:
    - name: forward
      port: 24224
      protocol: TCP
      targetPort: forward
    - name: prometheus
      port: 24231
      protocol: TCP
      targetPort: prometheus
    selector:
      app: fluentd
    sessionAffinity: None
    type: ClusterIP  
  ```
  
  Both forward(24224) and prometheus(24231) ports are exposed.
  

- Step 5: create a Service resource to expose fluentd forward endpoint outside the cluster (LoadBalancer service type)

  ```yml
  apiVersion: v1
  kind: Service
  metadata:
    labels:
      app: fluentd
    name: fluentd-ext
    namespace: k3s-logging
  spec:
    ports:
    - name: forward-ext
      port: 24224
      protocol: TCP
      targetPort: forward
    selector:
      app: fluentd
    sessionAffinity: None
    type: LoadBalancer
    loadBalancerIP: {{ k3s_fluentd_external_ip }}  
  ```  

- Step 3: Check fluentd status
  ```shell
  kubectl get pods -n k3s-logging
  ```

## Fluentbit Forwarder installation

It can be installed and configured to collect and parse Kubernetes logs deploying a daemonset pod (same as fluentd). See fluenbit documentation on how to install it on Kuberentes cluster: ["Fluentbit: Kubernetes Production Grade Log Processor"](https://docs.fluentbit.io/manual/installation/kubernetes).

For speed-up the installation there is available a [helm chart](https://github.com/fluent/helm-charts/tree/main/charts/fluent-bit). Fluentbit config file can be build probiding the proper helm chart values.


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
  
  Fluentbit will be configured with the following helm chart `values.yml`:
  
  ```yml
  # fluentbit helm chart values

  #fluentbit-container environment variables:
  env:
    # Fluentd deployment service
    - name: FLUENT_AGGREGATOR_HOST
      value: "fluentd"
    # Default fluentd forward port
    - name: FLUENT_AGGREGATOR_PORT
      value: "24224"
    - name: FLUENT_AGGREGATOR_SHARED_KEY
      valueFrom:
        secretKeyRef:
          name: fluentd-shared-key
          key: fluentd-shared-key
    - name: FLUENT_SELFHOSTNAME
      valueFrom:
        fieldRef:
          fieldPath: spec.nodeName
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

    # fluent-bit.config INPUT:
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

    # fluent-bit.config OUTPUT: **NOTE 4**
    outputs: |

      [OUTPUT]
          Name forward
          match *
          Host ${FLUENT_AGGREGATOR_HOST}
          Port ${FLUENT_AGGREGATOR_PORT}
          Self_Hostname ${FLUENT_SELFHOSTNAME}
          Shared_Key ${FLUENT_AGGREGATOR_SHARED_KEY}
          tls True
          tls.verify False

    # fluent-bit.config PARSERS:
    customParsers: |

      [PARSER]
          Name syslog-rfc3164-nopri
          Format regex
          Regex /^(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\/\.\-]*)(?:\[(?<pid>[0-9]+)\])?(?:[^\:]*\:)? *(?<message>.*)$/
          Time_Key time
          Time_Format %b %d %H:%M:%S
          Time_Keep False

    # fluent-bit.config FILTERS:
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

  # Enable fluentbit instalaltion on master node.
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

### Fluentbit chart configuration details

The Helm chart deploy fluent-bit as a DaemonSet, passing environment values to the pod and mounting as volumes two different ConfigMaps. These ConfigMaps contain the fluent-bit configuration files and the lua scripts that can be used during the parsing.

#### Fluent-bit container environment variables.

Fluent-bit pod environment variables are configured through `env` helm chart value.

```yml
#fluentbit-container environment variables:
env:
  # Fluentd deployment service
  - name: FLUENT_AGGREGATOR_HOST
    value: "fluentd"
  # Default fluentd forward port
  - name: FLUENT_AGGREGATOR_PORT
    value: "24224"
  - name: FLUENT_AGGREGATOR_SHARED_KEY
    valueFrom:
      secretKeyRef:
        name: fluentd-shared-key
        key: fluentd-shared-key
  - name: FLUENT_SELFHOSTNAME
    valueFrom:
      fieldRef:
        fieldPath: spec.nodeName
  # Specify TZ
  - name: TZ
    value: "Europe/Madrid"
```

- Fluentd aggregator connection details (IP: `FLUENT_AGGREGATOR_HOST`, port: `FLUENT_AGGREGATOR_PRORT`) and TLS forward protocol configuration (shared key: `FLUENT_AGGREGATOR_SHARED_KEY` and self-hostname: `FLUENT_SELFHOSTNAME`) are passed as environment variables to the fluentbit pod, so forwarder output plugin can be configured. Shared-key is obtanined from the corresponding Secret and selfhost-name from the node running the POD.

- TimeZone (`TZ`) need to be specified so Fluentbit can properly parse logs which timestamp does not contain timezone information. OS Ubuntu logs like `/var/log/syslog` and `/var/log/auth.log` do not contain timezone information.

#### Fluent-bit configuration files

Fluent-bit helm chart creates a ConfigMap mounted in the POD as `/fluent-bit/etc/` volume containin all fluent-bit configuration files, using helm value `config`

Helm generates a ConfigMap containing:

- fluentbit main configuration file (`fluent-bit.conf`) concatenating content from helm values `config.service`, `config.inputs`, `config.outputs`,  and `config.filters`.
- custom parser file (`custom-parser.conf`) containing content from `config.custom_parsers` helm value.

##### Fluent-bit.conf

The file content has the following sections:

- Fluentbit [SERVICE] configuration

  ```
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
  ```

  This configuration enables built-in HTTP server (`HTTP_Server On`) so Prometheus metrics can be exposed.

  It also loads configuration files containing the log parsers to be used ([PARSER] configuration section) (`Parsers_File`). Fluentbit is using [`parser.conf`](https://github.com/fluent/fluent-bit-docker-image/blob/master/conf/parsers.conf) (file coming from fluentbit official docker image) and `custom_parser.conf` (parser file containing additional parsers defined in the same ConfigMap)

- Fluentbit [INPUT] configuration

  Fluentbit inputs are configured to collect and parse the following:

  - Container logs parsing

    ```
    [INPUT]
        Name tail
        Path /var/log/containers/*.log
        multiline.parser docker, cri
        DB /var/log/fluentbit/flb_kube.db
        Tag kube.*
        Mem_Buf_Limit 5MB
        Skip_Long_Lines True

    ```

    It configures fluentbit to monitor kubernetes containers logs (`/var/log/container/*.logs`), using `tail` input plugin and enabling the parsing of multi-line logs ([`muline.parser`](https://docs.fluentbit.io/manual/pipeline/inputs/tail#multiline-support)) 

    All logs are tagged adding the prefix `kube`.

    [Multiline parser engine](https://docs.fluentbit.io/manual/administration/configuring-fluent-bit/multiline-parsing) provides built-in multiline parsers (supporting docker and cri logs formats) and a way to define custom parsers.
    
    The two options in `multiline.parser` separated by a comma means multi-format: try docker and cri multiline formats.

    For `containerd` logs multiline parser `cri` is needed. Embedded implementation of this parser applies the following regexp to the input lines:
    ```
      "^(?<time>.+) (?<stream>stdout|stderr) (?<_p>F|P) (?<log>.*)$"
    ```
    See implementation in go [code](https://github.com/fluent/fluent-bit/blob/master/src/multiline/flb_ml_parser_cri.c).

    Fourth field ("F/P") indicates whether the log is full (one line) or partial (more lines are expected). See more details in this fluentbit [feature request](https://github.com/fluent/fluent-bit/issues/1316)

  - OS level system logs

    ```
    [INPUT]
      Name tail
      Tag host.*
      DB /var/log/fluentbit/flb_host.db
      Path /var/log/auth.log,/var/log/syslog
      Parser syslog-rfc3164-nopri
    ```

    Fluentbit is configured for extracting OS level logs (`/var/logs/auth` and `/var/log/syslog` files), using custom parser `syslog-rfc3164-nopri` (syslog without priority field) defined in `custom_parser.conf` file.

    {{site.data.alerts.note}}

    By default helm chart tries to configure fluentbit to collect and parse systemd `kubelet.system` service, which is usually the systemd process in K8S distributions. 
    
    ```
    [INPUT]
      Name systemd
      Tag host.*
      Systemd_Filter _SYSTEMD_UNIT=kubelet.service
      Read_From_Tail On
    ``` 

    In K3S only two systemd processes are installed (`k3s` in master node and `k3s-agent` in worker nodes). In both cases, logs are also copied to OS level syslog file (`/var/log/syslog`). So monitoring OS level files is enough to get K3S processes logs.

    {{site.data.alerts.end}}

- Fluentbit [OUTPUT] configuration

  ```
  [OUTPUT]
      Name forward
      match *
      Host ${FLUENT_AGGREGATOR_HOST}
      Port ${FLUENT_AGGREGATOR_PORT}
      Self_Hostname ${FLUENT_SELFHOSTNAME}
      Shared_Key ${FLUENT_AGGREGATOR_SHARED_KEY}
      tls True
      tls.verify False
  ```
  Fluentbit is configured to forward all logs to fluentd aggregator using a secure channel (TLS)
  container environment variables are used to confure fluentd connection details and shared key.

- Fluentbit [FILTERS] configuration

  ```
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
  ```
  Fluent-bit kubernets filter enriches logs with Kubernetes metadata parsing log tag information (obtaining pod_name, container_name, container_id namespace) and querying the Kube API (obtaining pod_id, pod labels and annotations). See [Fluent-bit kuberentes filter documentation](https://docs.fluentbit.io/manual/pipeline/filters/kubernetes).

  Kubernetes annotation and labels are not included in the enrichment process.
  
  This filter is only applied to kubernetes logs(containing kube.* tag).

  All kubernetes metadata is stored within the processed log as a `kubernetes` map.

  Additional filters are configured to reformat this `kubernetes` nested map.

  ```
  [FILTER]
      Name nest
      Match kube.*
      Operation lift
      Nested_under kubernetes
      Add_prefix kubernetes_
  ```
  
  [`nest` filter](https://docs.fluentbit.io/manual/pipeline/filters/nest) remove the nested map `kubernetes` and moving all its records to the root map renaming them with the prefix `kubernetes_`.

  ```
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
  ```
  
  [`modify` filter](https://docs.fluentbit.io/manual/pipeline/filters/modify) removing and renaming some logs fields.

  The following filter need to be applied to host logs (OS level). Logs tagged as `host.*`

  ```
  [FILTER]
    Name lua
    Match host.*
    script /fluent-bit/scripts/adjust_ts.lua
    call local_timestamp_to_UTC
  ```
  This filter executes a local-time-to-utc filter (Lua script). It applies to system level logs (`/var/log/syslog` and `/var/log/auth.log`) . It translates logs timestamps from local time to UTC format.

  This is needed because time field included in these logs does not contain information about TimeZone. Since I am not using UTC time in my cluster (cluser is using `Europe/Madrid` timezone), Fluentbit/Elasticsearch, when parsing them, assumes they are in UTC timezone displaying them in the future.
  See issue [#5](https://github.com/ricsanfre/pi-cluster/issues/5).

##### customParser.conf

customParser.conf file has custom parsers definition ([PARSER] sections).

```
[PARSER]
    Name syslog-rfc3164-nopri
    Format regex
    Regex /^(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\/\.\-]*)(?:\[(?<pid>[0-9]+)\])?(?:[^\:]*\:)? *(?<message>.*)$/
    Time_Key time
    Time_Format %b %d %H:%M:%S
    Time_Keep False
```

Custom parser needed to properly parse Ubuntu level syslog files (`/var/log/auth.log` and `/var/log/syslog`). Fluentbit default syslog parser is not valid, since Ubuntu is using a syslog format without specifying the priority field.


#### Fluent-bit Lua-script files

Fluent-bit helm chart creates a ConfigMap mounted in the POD as `/fluent-bit/scripts/` volume containin all fluent-bit lua script files used during the parsing, using helm value `luaScript`

The lua script configured is the one enabling local-time-to-utc translation:

`adjust_ts.lua` script:

```js
function local_timestamp_to_UTC(tag, timestamp, record)
    local utcdate   = os.date("!*t", ts)
    local localdate = os.date("*t", ts)
    localdate.isdst = false -- this is the trick
    utc_time_diff = os.difftime(os.time(localdate), os.time(utcdate))
    return 1, timestamp - utc_time_diff, record
end
```

#### Enabling fluent-bit deployment in master node


Fluentbit pod tolerations can be configured through helm chart value `tolerations`

```yml
  tolerations:
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule
```

#### Init container for creating fluentbit DB temporary directory

Additional pod init-container for creating `/var/log/fluentbit` directory in each node to store fluentbit Tail plugin database keeping track of monitored files and offsets (`Tail` input `DB` parameter)

```yml
 initContainers:
    - name: init-log-directory
      image: busybox
      command: ['/bin/sh', '-c', 'if [ ! -d /var/log/fluentbit ]; then mkdir -p /var/log/fluentbit; fi']
      volumeMounts:
        - name: varlog
          mountPath: /var/log
```

`initContainer` is based on `busybox` image that creates a directory `/var/logs/fluentbit`


## Gathering logs from servers outside the kubernetes cluster

For gathering the logs from `gateway` server fluentbit will be installed.

There are official installation packages for Ubuntu. Installation instructions can be found in [Fluentbit documentation: "Ubuntu installation"](https://docs.fluentbit.io/manual/installation/linux/ubuntu).

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
    tls: Off
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

Lua script need to be included for translaing local time zone (`Europe\Madrid`) to UTC and the corresponding filter need to be executed. See [issue #5](https://github.com/ricsanfre/pi-cluster/issues/5).
