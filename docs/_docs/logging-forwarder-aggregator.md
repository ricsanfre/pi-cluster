---
title: Fluentbit/Fluentd (Forwarder/Aggregator)
permalink: /docs/logging-forwarder-aggregator/
description: How to deploy logging collection, aggregation and distribution in our Raspberry Pi Kuberentes cluster. Deploy a forwarder/aggregator architecture using Fluentbit and Fluentd. Logs are routed to Elasticsearch, so log analysis can be done using Kibana.

last_modified_at: "27-07-2022"

---

A Forwarder/Aggregator log architecture will be implemented in the Kubernetes cluster with Fluentbit and Fluentd.

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

[Fluentd official images](https://github.com/fluent/fluentd-docker-image) do not contain any of the plugins (elasticsearch, prometheus monitoring, etc.) that are needed.

There are also available [fluentd images for kubernetes](https://github.com/fluent/fluentd-kubernetes-daemonset), but they are customized to parse kubernetes logs (deploy fluentd as forwarder and not as aggregator) and there is one image per output plugin (one for elasticsearch, one for kafka, etc.)

Since in the future I might configure the aggregator to dispath logs to another source (i.e Kafka for building a analytics Data Pipeline), I have decided to build a customized fluentd image with just the plugins I need, and containing default configuration to deploy fluentd as aggregator.

{{site.data.alerts.tip}}

[fluentd-kubernetes-daemonset images](https://github.com/fluent/fluentd-kubernetes-daemonset) should work for deploying fluentd as Deployment. For outputing to the ES you just need to select the adequate [fluentd-kubernetes-daemonset image tag](https://hub.docker.com/r/fluent/fluentd-kubernetes-daemonset/tags).

As alternative, you can create your own customized docker image or use mine. You can find it in [ricsanfre/fluentd-aggregator github repository](https://github.com/ricsanfre/fluentd-aggregator).
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
COPY entrypoint.sh /fluentd/

## 4) Change to fluent user to run fluentd
USER fluent
ENTRYPOINT ["tini",  "--", "/fluentd/entrypoint.sh"]
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

- Kubernetes ConfigMap resources containing fluentd config files.

{{site.data.alerts.note}}

[fluentd official helm chart](https://github.com/fluent/helm-charts/tree/main/charts/fluentd) also supports the deployment of fluentd as deployment or statefulset instead of daemonset. In case of deployment, [Kubernetes HPA (Horizontal POD Autoscaler)](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) is also supported.

Fluentd aggregator should be deployed in HA, Kubernetes deployment with several replicas. Additionally, [Kubernetes HPA (Horizontal POD Autoscaler)](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) should be configured to automatically scale the number of replicas.

The above Kubernetes resources, except TLS certificate and shared secret, are created automatically by the helm chart. I will use the helm chart deployment to ease the installation and maintenace.

{{site.data.alerts.end}}

#### Installation procedure

- Step 1. Create fluentd TLS certificate to enable secure communications between forwarders and aggregator.

  To configure fluentd to use TLS, it is needed the path to the files containing the TLS certificate and private key. The TLS Secret containing the certificate and key can be mounted in fluentd POD in a specific location (/etc/fluent/certs), so fluentd proccess can use them.

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

- Step 3. Add fluentbit helm repo
  ```shell
  helm repo add fluent https://fluent.github.io/helm-charts
  ```
- Step 4. Update helm repo
  ```shell
  helm repo update
  ```
- Step 5. Create `values.yml` for tuning helm chart deployment.
  
  fluentd configuration can be provided to the helm. See [`values.yml`](https://github.com/fluent/helm-charts/blob/main/charts/fluentd/values.yaml)
  
  Fluentd will be configured with the following helm chart `values.yml`:
  
  ```yml
  ---

  # Fluentd image
  image:
    repository: "ricsanfre/fluentd-aggregator"
    pullPolicy: "IfNotPresent"
    tag: "v1.14-debian-arm64-1"

  # Deploy fluentd as deployment
  kind: "Deployment"
  # Number of replicas
  replicaCount: 1
  # Enabling HPA
  autoscaling:
    enabled: true
    minReplicas: 1
    maxReplicas: 100
    targetCPUUtilizationPercentage: 80

  # Do not create serviceAccount and RBAC. Fluentd does not need to get access to kubernetes API.
  serviceAccount:
    create: false
  rbac:
    create: false

  ## Additional environment variables to set for fluentd pods
  env:
    # Path to fluentd conf file
    - name: "FLUENTD_CONF"
      value: "../../../etc/fluent/fluent.conf"
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
    # Setting a index-prefix for fluentd. By default index is logstash
    - name: FLUENT_ELASTICSEARCH_LOGSTASH_PREFIX
      value: fluentd
    - name: FLUENT_ELASTICSEARCH_LOG_ES_400_REASON
      value: "true"
    # Fluentd forward security
    - name: FLUENTD_FORWARD_SEC_SHARED_KEY
      valueFrom:
        secretKeyRef:
          name: fluentd-shared-key
          key: fluentd-shared-key

  # Volumes and VolumeMounts (only configuration files and certificates)
  volumes:
    - name: etcfluentd-main
      configMap:
        name: fluentd-main
        defaultMode: 0777
    - name: etcfluentd-config
      configMap:
        name: fluentd-config
        defaultMode: 0777
    - name: fluentd-tls
      secret:
        secretName: fluentd-tls

  volumeMounts:
    - name: etcfluentd-main
      mountPath: /etc/fluent
    - name: etcfluentd-config
      mountPath: /etc/fluent/config.d/
    - mountPath: /etc/fluent/certs
      name: fluentd-tls
      readOnly: true

  # Service. Exporting forwarder port (Metric already exposed by chart)
  service:
    type: "ClusterIP"
    annotations: {}
    ports:
    - name: forwarder
      protocol: TCP
      containerPort: 24224

  ## Fluentd list of plugins to install
  ##
  plugins: []
  # - fluent-plugin-out-http

  ## Do not create additional config maps
  ##
  configMapConfigs: []

  ## Fluentd configurations:
  ##
  fileConfigs:
    01_sources.conf: |-
      ## logs from fluentbit forwarders
      <source>
        @type forward
        @label @FORWARD
        bind "#{ENV['FLUENTD_FORWARD_BIND'] || '0.0.0.0'}"
        port "#{ENV['FLUENTD_FORWARD_PORT'] || '24224'}"
        # Enabling TLS
        <transport tls>
            cert_path /etc/fluent/certs/tls.crt
            private_key_path /etc/fluent/certs/tls.key
        </transport>
        # Enabling access security
        <security>
          self_hostname "#{ENV['FLUENTD_FORWARD_SEC_SELFHOSTNAME'] || 'fluentd-aggregator'}"
          shared_key "#{ENV['FLUENTD_FORWARD_SEC_SHARED_KEY'] || 'sharedkey'}"
        </security>
      </source>
      ## Enable Prometheus end point
      <source>
        @type prometheus
        @id in_prometheus
        bind "0.0.0.0"
        port 24231
        metrics_path "/metrics"
      </source>
      <source>
        @type prometheus_monitor
        @id in_prometheus_monitor
      </source>
      <source>
        @type prometheus_output_monitor
        @id in_prometheus_output_monitor
      </source>
    02_filters.conf: |-
      <label @FORWARD>
        # Re-route fluentd logs
        <match kube.var.log.containers.fluentd**>
          @type relabel
          @label @FLUENT_LOG
        </match>
        <filter kube.**>
          @type record_transformer
          enable_ruby true
          remove_keys log_processed
          <record>
            json_message.${record["k8s.container.name"]} ${(record.has_key?('log_processed'))? record['log_processed'] : nil}
          </record>
        </filter>
        <match **>
          @type relabel
          @label @DISPATCH
        </match>
      </label>
    03_dispatch.conf: |-
      <label @DISPATCH>
        <filter **>
          @type prometheus
          <metric>
            name fluentd_input_status_num_records_total
            type counter
            desc The total number of incoming records
            <labels>
              tag ${tag}
              hostname ${hostname}
            </labels>
          </metric>
        </filter>
        <match **>
          @type relabel
          @label @OUTPUT
        </match>
      </label>
    04_outputs.conf: |-
      <label @OUTPUT>
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
      </label>
  ```

- Step 6: create a Service resource to expose only fluentd forward endpoint outside the cluster (LoadBalancer service type)

  {{site.data.alerts.note}}

  Helm chart creates a Service resource (ClusterIP) exposing all ports (forward and metrics ports). Outide the cluster only forward port should be available.

  {{site.data.alerts.end}}

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
      targetPort: 24224
    selector:
      app.kubernetes.io/instance: fluentd
      app.kubernetes.io/name: fluentd
    sessionAffinity: None
    type: LoadBalancer
    loadBalancerIP: 10.0.0.101
  ```
  Fluentd forward service will be available in port 24224 and IP 10.0.0.101 (IP belonging to MetalLB addresses pool). This IP address should be mapped to a DNS record, `fluentd.picluster.ricsanfre.com`, in `gateway` dnsmasq configuration.

- Step 3: Check fluentd status
  ```shell
  kubectl get all -l app.kubernetes.io/name=fluentd -n k3s-logging
  ```

### Fluentd chart configuration details

The Helm chart deploy fluentd as a Deployment, passing environment values to the pod and mounting as volumes different ConfigMaps. These ConfigMaps contain the fluentd configuration files and TLS secret used in forward protocol (communication with the fluentbit forwarders).

#### Fluentd deployed as Deployment

```yml
# Fluentd image
image:
  repository: "ricsanfre/fluentd-aggregator"
  pullPolicy: "IfNotPresent"
  tag: "v1.14-debian-arm64-1"

# Deploy fluentd as deployment
kind: "Deployment"

# Number of replicas
replicaCount: 1

# Enabling HPA
autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 100
  targetCPUUtilizationPercentage: 80

# Do not create serviceAccount and RBAC. Fluentd does not need to get access to kubernetes API.
serviceAccount:
  create: false
rbac:
  create: false
```

Fluentd is deployed as Deployment (`kind: "Deployment"`) with 1 replica (`replicaCount: 1`, using custom fluentd image (`image.repository: "ricsanfre/fluentd-aggregator` and `image.tag`).

Service account (`serviceAccount.create: false`) and corresponding RoleBinding (`rbac.create: false`) are not created since fluentd aggregator does not need to access to Kubernetes API.

HPA autoscaling is also configured (`autoscaling.enabling: true`).

#### Fluentd container environment variables.


```yml
## Additional environment variables to set for fluentd pods
env:
  # Path to fluentd conf file
  - name: "FLUENTD_CONF"
    value: "../../../etc/fluent/fluent.conf"
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
  # Setting a index-prefix for fluentd. By default index is logstash
  - name: FLUENT_ELASTICSEARCH_LOGSTASH_PREFIX
    value: fluentd
  - name: FLUENT_ELASTICSEARCH_LOG_ES_400_REASON
    value: "true"
  # Fluentd forward security
  - name: FLUENTD_FORWARD_SEC_SHARED_KEY
    valueFrom:
      secretKeyRef:
        name: fluentd-shared-key
        key: fluentd-shared-key
```

fluentd docker image and configuration files use the following environment variables:

- Path to main fluentd config file (`FLUENTD_CONF`) pointing at `/etc/fluent/fluent.conf` file. 

  {{site.data.alerts.note}}

  `FLUENTD_CONF` environment variable is used by docker image to load main config file from `/fluentd/conf/${FLUEND_CONF}`. A relative path from `/fluentd/conf/` directory need to be provided to match environment variable definition in the docker image.

  {{site.data.alerts.end}}

- Elasticsearch output plugin configuration:

  - ES connection details (`FLUENT_ELASTICSEARCH_HOST` and `FLUENT_ELASTICSEARCH_PORT`): elasticsearch kubernetes service (`efk-es-http`) and ES port.

  - ES access credentials (`FLUENT_ELASTICSEARCH_USER` and `FLUENT_ELASTICSEARCH_PASSWORD`): elastic user password obtained from the corresponding Secret (`efk-es-elastic-user` created during ES installation)

  - additional plugin parameters: setting index prefix (`FLUENT_ELASTICSEARCH_LOGSTASH_PREFIX`) and enabling debug messages when receiving errors from Elasticsearch API (`FLUENT_ELASTICSEARCH_LOG_ES_400_REASON`)

  - rest of parameters of the plugin with default values defined in the configuration.

- Forwarder input plugin configuration:

  - Shared key used for authentication(`FLUENTD_FORWARD_SEC_SHARED_KEY`), loading the content of the secret generated in step 2 of installation procedure: `fluentd-shared-key`.


#### Fluentd POD volumes and volume mounts

```yml
# Volumes and VolumeMounts (only configuration files and certificates)
volumes:
  - name: etcfluentd-main
    configMap:
      name: fluentd-main
      defaultMode: 0777
  - name: etcfluentd-config
    configMap:
      name: fluentd-config
      defaultMode: 0777
  - name: fluentd-tls
    secret:
      secretName: fluentd-tls

volumeMounts:
  - name: etcfluentd-main
    mountPath: /etc/fluent
  - name: etcfluentd-config
    mountPath: /etc/fluent/config.d/
  - mountPath: /etc/fluent/certs
    name: fluentd-tls
    readOnly: true
```

ConfigMaps created by the helm chart are mounted in the fluentd container:

- ConfigMap `fluentd-main`, containing fluentd main config file (`fluent.conf`), is mounted as `/etc/fluent` volume.

- ConfigMap `fluentd-config`, containing fluentd config files included by main config file is mounted as `/etc/fluent/config.d`

Additional Secret, contining fluentd TLS certificate and key is also mounted:

- Secret `fluentd-tls`, generated in step 1 of the installation procedure, containing fluentd certificate and key
  TLS Secret containing fluentd's certificate and private key, is mounted as `/etc/fluent/certs`.

#### Fluentd Service and other configurations

```yml
# Service. Exporting forwarder port (Metric already exposed by chart)
service:
  type: "ClusterIP"
  annotations: {}
  ports:
  - name: forwarder
    protocol: TCP
    containerPort: 24224

## Fluentd list of plugins to install
##
plugins: []
# - fluent-plugin-out-http

## Do not create additional config maps
##
configMapConfigs: []
```

Fluetd service is configured as ClusterIP, exposing `forwarder` port (By default Helm chart also exposes prometheus `/metrics` endpoint in port 24231 ).

The helm chart can be also configured to install fluentd plugins on start-up (`plugins`) and to load aditional fluentd config directories `configMapConfigs`.

{{site.data.alerts.note}}
  
Set configMapConfigs to null to avoid loading default configMaps created by the Helm chart containing systemd input plugin configuration and prometheus default config.

{{site.data.alerts.end}}

#### Fluentd configuration files

Fluentd main config file (`fluent.conf`) is loaded into a Kubernetes ConfigMap(`fluentd-main`) that will be mounted as `/etc/fluent.conf` within the fluentd pod.

The content created by default by the helm chart is the following:

`/etc/fluent.conf`:
```
# do not collect fluentd logs to avoid infinite loops.
<label @FLUENT_LOG>
  <match **>
    @type null
    @id ignore_fluent_logs
  </match>
</label>

@include config.d/*.conf
```

Default configuration only contains a rule for discarding fluentd own logs (labeled as @FLUENT_LOG) and includes the configuration of all files located in `/etc/fluent/config.d` directory. All files contained in that directory are stored in another ConfigMap (`fluentd-config`).

{{site.data.alerts.note}}

It is not needed to change the default content of the `fluent.conf` created by Helm Chart.

{{site.data.alerts.end}}

`fluentd-config` ConfigMap is configured with the content loaded in `fileConfigs` helm Chart value.

- Sources (input plugins) configuration:

  `/etc/fluent/conf.d/01_sources.conf`

  ```xml
  ## logs from fluentbit forwarders
  <source>
    @type forward
    @label @FORWARD
    bind "#{ENV['FLUENTD_FORWARD_BIND'] || '0.0.0.0'}"
    port "#{ENV['FLUENTD_FORWARD_PORT'] || '24224'}"
    # Enabling TLS
    <transport tls>
        cert_path /etc/fluent/certs/tls.crt
        private_key_path /etc/fluent/certs/tls.key
    </transport>
    # Enabling access security
    <security>
      self_hostname "#{ENV['FLUENTD_FORWARD_SEC_SELFHOSTNAME'] || 'fluentd-aggregator'}"
      shared_key "#{ENV['FLUENTD_FORWARD_SEC_SHARED_KEY'] || 'sharedkey'}"
    </security>
  </source>
  ## Enable Prometheus end point
  <source>
    @type prometheus
    @id in_prometheus
    bind "0.0.0.0"
    port 24231
    metrics_path "/metrics"
  </source>
  <source>
    @type prometheus_monitor
    @id in_prometheus_monitor
  </source>
  <source>
    @type prometheus_output_monitor
    @id in_prometheus_output_monitor
  </source>
  ```
  With this configuration, fluentd:

  - collects logs from forwarders (port 24224) configuring [forward input plugin](https://docs.fluentd.org/input/forward). TLS and authentication is configured.

  - enables Prometheus metrics exposure (port 24231) configuring [prometheus input plugin](https://docs.fluentd.org/monitoring-fluentd/monitoring-prometheus). Complete list of configuration parameters in [fluent-plugin-prometheus repository](https://github.com/fluent/fluent-plugin-prometheus)

  - labels (`@FORWARD`) all coming records from fluent-bit forwarders to perform further processing and routing.

- Filters configuration:

  `/etc/fluent/conf.d/02_filters.conf`

  ```xml
  <label @FORWARD>
    # Re-route fluentd logs
    <match kube.var.log.containers.fluentd**>
      @type relabel
      @label @FLUENT_LOG
    </match>
    <filter kube.**>
      @type record_transformer
      enable_ruby true
      remove_keys log_processed
      <record>
        json_message.${record["k8s.container.name"]} ${(record.has_key?('log_processed'))? record['log_processed'] : nil}
      </record>
    </filter>
    <match **>
      @type relabel
      @label @DISPATCH
    </match>
  </label>
  ```

  With this configuration, fluentd:
  
  - relabels (`@FLUENT_LOG`) logs coming from fluentd itself to reroute them (discard them).

  - removes `log_processed` field, and creates a new field `json_message.<container-name>` containing original `log_processed` field but copied to a unique map using container name `k8s.container.name`. This way we assure that all log fields are unique avoiding errors during the ingestion into ES.

  - relabels (`@DISPATCH`)the rest of logs to be dispatched to the outputs

- Dispatch configuration

  `/etc/fluent/conf.d/03_dispatch.conf`

  ```xml
  <label @DISPATCH>
    <filter **>
      @type prometheus
      <metric>
        name fluentd_input_status_num_records_total
        type counter
        desc The total number of incoming records
        <labels>
          tag ${tag}
          hostname ${hostname}
        </labels>
      </metric>
    </filter>
    <match **>
      @type relabel
      @label @OUTPUT
    </match>
  </label>
  ```

  With this configuration, fluentd:

  - counts per tag and hostname, incoming records to provide the corresponding prometheus metric `fluentd_input_status_num_records_total`

- Ouptut plugin configuration

  `/etc/fluent/conf.d/04_outputs.conf`

  ```xml
  <label @OUTPUT>
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
  </label>
  ```
  
  With this configuration fluentd:

  - routes all logs to elastic search configuring [elasticsearch output plugin](https://docs.fluentd.org/output/elasticsearch). Complete list of parameters in [fluent-plugin-elasticsearch reporitory](https://github.com/uken/fluent-plugin-elasticsearch).

## Fluentbit Forwarder installation

Fluentbit can be installed and configured to collect and parse Kubernetes logs deploying it as a daemonset pod. See fluenbit documentation on how to install it on Kuberentes cluster: ["Fluentbit: Kubernetes Production Grade Log Processor"](https://docs.fluentbit.io/manual/installation/kubernetes).

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
          storage.path /var/log/fluentbit/storage
          storage.sync normal
          storage.checksum off
          storage.backlog.mem_limit 5M
          storage.metrics on

    # fluent-bit.config INPUT:
    inputs: |

      [INPUT]
          Name tail
          Alias input.kube
          Path /var/log/containers/*.log
          multiline.parser docker, cri
          DB /var/log/fluentbit/flb_kube.db
          Tag kube.*
          Mem_Buf_Limit 5MB
          storage.type filesystem
          Skip_Long_Lines On

      [INPUT]
          Name tail
          Alias input.host
          Tag host.*
          DB /var/log/fluentbit/flb_host.db
          Path /var/log/auth.log,/var/log/syslog
          Mem_Buf_Limit 5MB
          storage.type filesystem
          Parser syslog-rfc3164-nopri

    # fluent-bit.config OUTPUT
    outputs: |

      [OUTPUT]
          Name forward
          Alias output.aggregator
          match *
          Host ${FLUENT_AGGREGATOR_HOST}
          Port ${FLUENT_AGGREGATOR_PORT}
          Self_Hostname ${FLUENT_SELFHOSTNAME}
          Shared_Key ${FLUENT_AGGREGATOR_SHARED_KEY}
          tls On
          tls.verify Off

    # fluent-bit.config PARSERS:
    customParsers: |

      [PARSER]
          Name syslog-rfc3164-nopri
          Format regex
          Regex /^(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\/\.\-]*)(?:\[(?<pid>[0-9]+)\])?(?:[^\:]*\:)? *(?<message>.*)$/
          Time_Key time
          Time_Format %b %d %H:%M:%S
          Time_Keep Off

    # fluent-bit.config FILTERS:
    filters: |

      [FILTER]
          Name kubernetes
          Match kube.*
          Buffer_Size 512k
          Kube_Tag_Prefix kube.var.log.containers.
          Merge_Log On
          Merge_Log_Trim Off
          Merge_Log_Key log_processed
          Keep_Log Off
          K8S-Logging.Parser On
          K8S-Logging.Exclude On
          Annotations Off
          Labels Off

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
    # json-exporter config
    extraFiles:
      json-exporter-config.yml: |
        modules:
          default:
            metrics:
              - name: fluenbit_storage_layer
                type: object
                path: '{.storage_layer}'
                help: The total number of chunks in the fs storage
                values:
                  fs_chunks_up: '{.chunks.fs_chunks_up}'
                  fs_chunks_down: '{.chunks.fs_chunks_down}'
  
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

  # Init container. Create directory for fluentbit
  initContainers:
    - name: init-fluentbit-directory
      image: busybox
      command: ['/bin/sh', '-c', 'if [ ! -d /var/log/fluentbit ]; then mkdir -p /var/log/fluentbit; fi ; if [ ! -d /var/log/fluentbit/tail-db ]; then mkdir -p /var/log/fluentbit/tail-db; fi ; if [ ! -d /var/log/fluentbit/storage ]; then mkdir -p /var/log/fluentbit/storage; fi']
      volumeMounts:
        - name: varlog
          mountPath: /var/log
  # Sidecar container to export storage metrics
  extraContainers:
    - name: json-exporter
      image: quay.io/prometheuscommunity/json-exporter
      command: ['/bin/json_exporter']
      args: ['--config.file=/json-exporter-config.yml']
      ports:
        - containerPort: 7979
          name: http
          protocol: TCP
      volumeMounts:
        - mountPath: /json-exporter-config.yml
          name: config
          subPath: json-exporter-config.yml        
  ```

- Step 4. Install chart
  ```shell
  helm install fluent-bit fluent/fluent-bit -f values.yml --namespace k3s-logging
  ```

- Step 5: Check fluent-bit status
  ```shell
  kubectl get all -l app.kubernetes.io/name=fluent-bit -n k3s-logging
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
      storage.path /var/log/fluentbit/storage
      storage.sync normal
      storage.checksum off
      storage.backlog.mem_limit 5M
      storage.metrics on
  ```

  This configuration enables built-in HTTP server (`HTTP_Server`, `HTTP_Listen` and `HTTP_Port`) to endpoints enabling [remote monitoring of fluentbit](https://docs.fluentbit.io/manual/administration/monitoring). One of the endpoints, `/api/v1/metrics/prometheus`, exposed metrics in Prometheus format.

  It also loads configuration files containing the log parsers to be used ([PARSER] configuration section) (`Parsers_File`). Fluentbit is using [`parser.conf`](https://github.com/fluent/fluent-bit-docker-image/blob/master/conf/parsers.conf) (file coming from fluentbit official docker image) and `custom_parser.conf` (parser file containing additional parsers defined in the same ConfigMap).

  To increase realibility, [fluentbit filesystem buffering mechanism](https://docs.fluentbit.io/manual/administration/buffering-and-storage) is enabled (`storage.path` and `storage.*`) and storage metrics endpoint (`storage.metrics`).

- Fluentbit [INPUT] configuration

  Fluentbit inputs are configured to collect and parse the following:

  - Container logs parsing

    ```
    [INPUT]
        Name tail
        Alias input.kube
        Path /var/log/containers/*.log
        multiline.parser docker, cri
        DB /var/log/fluentbit/flb_kube.db
        Tag kube.*
        Skip_Long_Lines On
        Mem_Buf_Limit 50MB
        storage.type filesystem

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

    To increase realibility, [fluentbit memory/filesystem buffering mechanism](https://docs.fluentbit.io/manual/administration/buffering-and-storage) is enabled: (`Mem_Buf_Limit` set to 50MB and `storage.type` set to filesystem).

    `Alias` is configured to provide more readable metrics. See [fluentbit monitoring documentation](https://docs.fluentbit.io/manual/administration/monitoring#configuring-aliases).

    Tail `DB` parameter configured to keeping track of the monitoring files. See [Fluentbit tail input: keeping state"](https://docs.fluentbit.io/manual/pipeline/inputs/tail#keep_state)

  - OS level system logs

    ```
    [INPUT]
      Name tail
      Alias input.os
      Tag host.*
      DB /var/log/fluentbit/flb_host.db
      Path /var/log/auth.log,/var/log/syslog
      Parser syslog-rfc3164-nopri
      Mem_Buf_Limit 50MB
      storage.type filesystem
    ```

    Fluentbit is configured for extracting OS level logs (`/var/logs/auth` and `/var/log/syslog` files), using custom parser `syslog-rfc3164-nopri` (syslog without priority field) defined in `custom_parser.conf` file.

    To increase realibility, [fluentbit memory/filesystem buffering mechanism](https://docs.fluentbit.io/manual/administration/buffering-and-storage) is enabled: (`Mem_Buf_Limit` set to 50MB and `storage.type` set to filesystem).

    `Alias` is configured to provide more readable metrics. See [fluentbit monitoring documentation](https://docs.fluentbit.io/manual/administration/monitoring#configuring-aliases).

    Tail `DB` parameter configured to keeping track of the monitoring files. See [Fluentbit tail input: keeping state"](https://docs.fluentbit.io/manual/pipeline/inputs/tail#keep_state)

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
      Alias output.aggregator
      match *
      Host ${FLUENT_AGGREGATOR_HOST}
      Port ${FLUENT_AGGREGATOR_PORT}
      Self_Hostname ${FLUENT_SELFHOSTNAME}
      Shared_Key ${FLUENT_AGGREGATOR_SHARED_KEY}
      tls On
      tls.verify Off
  ```
  Fluentbit is configured to forward all logs to fluentd aggregator using a secure channel (TLS)
  container environment variables are used to confure fluentd connection details and shared key.

  `Alias` is configured to provide more readable metrics. See [fluentbit monitoring documentation](https://docs.fluentbit.io/manual/administration/monitoring#configuring-aliases).

- Fluentbit [FILTERS] configuration

  ```
  [FILTER]
    Name kubernetes
    Match kube.*
    Buffer_Size 512k
    Kube_Tag_Prefix kube.var.log.containers.
    Merge_Log On
    Merge_Log_Key log_processed
    Merge_Log_Trim Off
    Keep_Log Off
    K8S-Logging.Parser On
    K8S-Logging.Exclude On
    Annotations Off
    Labels Off
  ```

  This filter is only applied to kubernetes logs(containing kube.* tag).
  Fluent-bit kubernetes filter do to main tasks:
 
  - It enriches logs with Kubernetes metadata

    Parsing log tag information (obtaining pod_name, container_name, container_id namespace) and querying the Kube API (obtaining pod_id, pod labels and annotations).

    See [Fluent-bit kuberentes filter documentation](https://docs.fluentbit.io/manual/pipeline/filters/kubernetes).    Kubernetes annotation and labels are not included in the enrichment process (`Annotations Off` and `Labels Off`)
    All kubernetes metadata is stored within the processed log as a `kubernetes` map.

    {{site.data.alerts.important}} **About Buffer_Size when connecting to Kuberenetes API**

    Kuberentes filter's `Buffer_Size` default value is set to 32K which it is not enough for getting data of some of the PODs. With default value, Kubernetes filter was not able to get metadata information for some of the PODs (i.e.: elasticsearh). Increasing its value to 512k makes it work.

    {{site.data.alerts.end}}

  - It further parses `log` field within the CRI log format

    It needs to be enabled (`Merge_Log On`), and, by default it applies a JSON parser to log content. Using specific Kuberenetes POD annotations (`fluentbit.io/parser`, a specific parser for `log` field can be specified at POD and container level (This annotation mechanism need to be activated (`K8sS_Logging.Parser On`).

    See [Fluent-bit kuberentes filter documentation: Processing log value](https://docs.fluentbit.io/manual/pipeline/filters/kubernetes#processing-the-log-value).

    Parsed log field will be added to the processed log as a `log_processed` map (`Merge_Log_Key`).

    {{site.data.alerts.important}} **About Log_Merge and ES ingestion errors** 

    Activating Merge_Log functionality might result in conflicting field types when tryin to ingest into elasticsearch causing its rejection. See [issue #58](https://github.com/ricsanfre/pi-cluster/issues/58).

    To solve this issue a filter rule in the aggregation layer (fluentd) has to be created. This rule will remove `log_processed` field and it will create a new field `json_message.<container-name>`, making unique the fields before ingesting into ES.

    ```
    <filter kube.**>
      @type record_transformer
      enable_ruby true
      remove_keys log_processed
      <record>
        json_message.${record["k8s.container.name"]} ${(record.has_key?('log_processed'))? record['log_processed'] : nil}
      </record>
    </filter>
    ```

    {{site.data.alerts.end}}
  
  Additional filters are configured to reformat `kubernetes` nested map.

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

Additional pod init-container for creating `/var/log/fluentbit` directory in each node:

- To store fluentbit Tail plugin database keeping track of monitored files and offsets (`Tail` input `DB` parameter): `/var/log/fluentbit/tail-db`
- To store fluentbit buffering: `/var/log/fluentbit/storage`

```yml
initContainers:
  - name: init-fluentbit-directory
    image: busybox
    command: ['/bin/sh', '-c', 'if [ ! -d /var/log/fluentbit ]; then mkdir -p /var/log/fluentbit; fi ; if [ ! -d /var/log/fluentbit/tail-db ]; then mkdir -p /var/log/fluentbit/tail-db; fi ; if [ ! -d /var/log/fluentbit/storage ]; then mkdir -p /var/log/fluentbit/storage; fi']
    volumeMounts:
      - name: varlog
        mountPath: /var/log
```

`initContainer` is based on `busybox` image that creates a directory `/var/logs/fluentbit`


#### Sidecar container for exporting storage metrics

When enabling filesystem buffering (production usual configuration), Fluentbit storage metrics should be monitored as well. These metrics are not exposed by Fluentbit in prometheus format (metrics endpoint: `/api/v1/metrics/prometheus`). They are exposed in JSON format at `/api/v1/storage` endpoint.

The storage output looks like this: 
```shell
curl -s http://10.42.2.28:2020/api/v1/storage | jq
{
  "storage_layer": {
    "chunks": {
      "total_chunks": 0,
      "mem_chunks": 0,
      "fs_chunks": 0,
      "fs_chunks_up": 0,
      "fs_chunks_down": 0
    }
  },
  "input_chunks": {
    "input.kube": {
      "status": {
        "overlimit": false,
        "mem_size": "0b",
        "mem_limit": "47.7M"
      },
      "chunks": {
        "total": 0,
        "up": 0,
        "down": 0,
        "busy": 0,
        "busy_size": "0b"
      }
    },
    "input.os": {
      "status": {
        "overlimit": false,
        "mem_size": "0b",
        "mem_limit": "47.7M"
      },
      "chunks": {
        "total": 0,
        "up": 0,
        "down": 0,
        "busy": 0,
        "busy_size": "0b"
      }
    },
    "storage_backlog.2": {
      "status": {
        "overlimit": false,
        "mem_size": "0b",
        "mem_limit": "0b"
      },
      "chunks": {
        "total": 0,
        "up": 0,
        "down": 0,
        "busy": 0,
        "busy_size": "0b"
      }
    }
  }
}
```
where 10.42.2.28 is the IP of fluentbit POD (one of them)

{{site.data.alerts.note}}

To do troubleshooting of APIs with curl command in kuberentes a utility POD can be deployed. In this case [ricsanfre/docker-curl-jq](https://github.com/ricsanfre/docker-curl-jq) docker image is used (simple alpine image containing bash, curl and jq)

It can deployed with command:

```shell
kubectl run -it --rm --image=ricsanfre/docker-curl-jq curly
```

{{site.data.alerts.end}}

There is a open issue in Fluentbit to export storage metrics with prometheus format (https://github.com/fluent/fluent-bit/pull/5334).

As alternative, prometheus-json-exporter can be deployed as sidecar to translate storage JSON metrics to Prometheus format. This [FluentCon presentation](https://www.youtube.com/watch?v=OhlyY6glf0A) shows how to do it and to integrate it with Prometheus.

The prometheus-json-exporter config.yml file need to be provided. It has been included as part of fluent-bit ConfigMap as `extraFiles` helm chart variable.

```yml
  extraFiles:
    json-exporter-config.yml: |
    modules:
      default:
        metrics:
          - name: fluenbit_storage_layer
            type: object
            path: '{.storage_layer}'
            help: The total number of chunks in the fs storage
            values:
              fs_chunks_up: '{.chunks.fs_chunks_up}'
              fs_chunks_down: '{.chunks.fs_chunks_down}'
```

This configuration translate to Prometheus format metrics `fs_chunks_up` and `fs_chunks_down`

This configurationf file is mounted in prometheus-json-exporter sidecarcontainer

To deploy sidecar prometheus-json-exporter `extraContainers`:

```yml
# Sidecar container to export storage metrics
extraContainers:
  - name: json-exporter
    image: quay.io/prometheuscommunity/json-exporter
    command: ['/bin/json_exporter']
    args: ['--config.file=/json-exporter-config.yml']
    ports:
      - containerPort: 7979
        name: http
        protocol: TCP
    volumeMounts:
      - mountPath: /json-exporter-config.yml
        name: config
        subPath: json-exporter-config.yml
```

`json-exporter` start wiht `json-exporter.config.yml` and listen on port 7979.


When deployed, the exporter can be tested with the following command:

```shell
curl "http://10.42.2.28:7979/probe?target=http://localhost:2020/api/v1/storage"
# HELP fluenbit_storage_layer_fs_chunks_down The total number of chunks in the fs storage
# TYPE fluenbit_storage_layer_fs_chunks_down untyped
fluenbit_storage_layer_fs_chunks_down 0
# HELP fluenbit_storage_layer_fs_chunks_up The total number of chunks in the fs storage
# TYPE fluenbit_storage_layer_fs_chunks_up untyped
fluenbit_storage_layer_fs_chunks_up 1
```

## Logs from external nodes

For colleting the logs from external nodes (nodes not belonging to kubernetes cluster: i.e: `gateway`),fluentbit will be installed and logs will be forwarded to fluentd aggregator service running within the cluster.

There are official installation packages for Ubuntu. Installation instructions can be found in [Fluentbit documentation: "Ubuntu installation"](https://docs.fluentbit.io/manual/installation/linux/ubuntu).

Fluentbit installation and configuration tasks have been automated with Ansible developing a role: role [**ricsanfre.fluentbit**](https://galaxy.ansible.com/ricsanfre/fluentbit). This role install fluentbit and configure it.

### Fluent bit configuration

{{site.data.alerts.note}}
**ricsanfre.fluentbit** role configuration is defined through a set of ansible variables. This variables are defined at `control` inventory group (group_vars/control.yml), to which `gateway`and `pimaster` belong to.
{{site.data.alerts.end}}

Configuration is quite similar to the one defined for the fluentbit-daemonset, removing kubernetes logs collection and filtering and maintaining only OS-level logs collection.

`/etc/fluent-bit/fluent-bit.conf`
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

[INPUT]
    Name tail
    Tag host.*
    DB /run/fluentbit-state.db
    Path /var/log/auth.log,/var/log/syslog
    Parser syslog-rfc3164-nopri

[FILTER]
    Name lua
    Match host.*
    script /etc/fluent-bit/adjust_ts.lua
    call local_timestamp_to_UTC

[OUTPUT]
    Name forward
    Match *
    Host fluentd.picluster.ricsanfre.com
    Port 24224
    Self_Hostname gateway
    Shared_Key s1cret0
    tls true
    tls.verify false
```

`/etc/fluent-bit/custom_parsers.conf`
```
[PARSER]
    Name syslog-rfc3164-nopri
    Format regex
    Regex /^(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\/\.\-]*)(?:\[(?<pid>[0-9]+)\])?(?:[^\:]*\:)? *(?<message>.*)$/
    Time_Key time
    Time_Format %b %d %H:%M:%S
    Time_Keep False
```

With configuration Fluentbit will monitoring log entries in `/var/log/auth.log` and `/var/log/syslog` files, parsing them using a custom parser `syslog-rfc3165-nopri` (syslog default parser removing priority field) and forward them to fluentd aggregator service running in K3S cluster. Fluentd destination is configured using DNS name associated to fluentd aggregator service external IP.
