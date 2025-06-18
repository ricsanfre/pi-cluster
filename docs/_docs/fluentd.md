---
title: Log aggregation and distribution with Fluentd
permalink: /docs/fluentd/
description: How to deploy log distribution solution for Kubernetes Cluster using Fluentd.
last_modified_at: "17-06-2025"
---

Fluentd is deploy as log aggregator, collecting all logs forwarded by Fluentbit agent and routing all logs to different backends (i.e ElasticSearch, Loki, Kafka, S3 bucket).

## What is Fluentd ?

Fluentd is an opensource log collection filtering and distribution tool.

Fluent-bit is a CNCF graduated project

### Fluentd as log aggregator/distributor

Fluentd will be deployed as a log distribution instead of fluent-bit because it provides a richer set of plugins to connect sources and destinations and to transform the logs. 
Particulary when using ElastiSearch as output, [fluentd's elasticsearch output plugin](https://github.com/uken/fluent-plugin-elasticsearch) offers more capabilities, ILM and index template management, that the corresponding [fluent-bit elasticsearch plugin](https://docs.fluentbit.io/manual/pipeline/outputs/elasticsearch).

## How does Fluentd work?

Fluent-bit and fluentd has a very simillar approach in the way logs are processed and routed, how the data pipelines are defined and using a plugin-based architecture (input, parsers, filters and output plugins)

![fluentd-architecture](/assets/img/fluentd-architecture.png)

A Fluentd event consists of three components:

-   `tag`: Specifies the origin where an event comes from. It is used for message routing.
-   `time`: Specifies the time when an event happens with nanosecond resolution.
-   `record`: Specifies the actual log as a JSON object.

### Fluentd data pipelines

[Fluentd](https://fluentbit.io) collects and process logs (also known as _records_) from different input sources, then parses and filters these records before they're stored. After data is processed and in a safe state, meaning either in memory or in the file system, the records are routed through the proper output destinations.

<pre class="mermaid">
graph LR;
  input-->parser
  parser-->filter
  filter-->storage[buffering]
  storage-->router((router))
  router-->output1([output1])
  router-->output2([output2])
  router-->output3([outputN])

  classDef box fill:#326ce5,stroke:#fff,stroke-width:0px,color:#000;  
  class input,parser,filter,storage,router,output1,output2,output3 box;
  %%{init: {'themeVariables': { 'lineColor': 'red'}}}%%
</pre>

## Installing Fluent-bit

### Building customized fluentd image

[Fluentd official images](https://github.com/fluent/fluentd-docker-image) do not contain any of the required plugins (elasticsearch, prometheus monitoring, etc.).

There are prebuild available [fluentd images for kubernetes](https://github.com/fluent/fluentd-kubernetes-daemonset), but they are customized to parse kubernetes logs (deploy fluentd as forwarder and not as aggregator) and there are different images per output plugin (one for elasticsearch, one for kafka, etc.)

Since I am currently dispatching logs to 2 different destinations (ElasticSearch and Loki) and in the future I might configure the aggregator to dispatch logs to another source (i.e Kafka for building a analytics Data Pipeline), I have decided to build a customized fluentd image with just the plugins I need, and containing default configuration to deploy fluentd as aggregator.

{{site.data.alerts.tip}}

[fluentd-kubernetes-daemonset images](https://github.com/fluent/fluentd-kubernetes-daemonset) should work for deploying fluentd as Deployment. For outputing to the ES you just need to select the adequate [fluentd-kubernetes-daemonset image tag](https://hub.docker.com/r/fluent/fluentd-kubernetes-daemonset/tags).

As alternative, you can create your own customized docker image or use mine. You can find it in [ricsanfre/fluentd-aggregator github repository](https://github.com/ricsanfre/fluentd-aggregator).
The multi-architecture (amd64/arm64) image is available in docker hub:

- `ricsanfre/fluentd-aggregator:v1.17.1-debian-1.0`

{{site.data.alerts.end}}

As base image, the [official fluentd docker image](https://github.com/fluent/fluentd-docker-image) can be used. To customize it, follow the instructions in the project repository: ["Customizing the image to intall additional plugins"](https://github.com/fluent/fluentd-docker-image#3-customize-dockerfile-to-install-plugins-optional).

In our case, the list of plugins that need to be added to the default fluentd image are:

- `fluent-plugin-elasticsearch`: ES as backend for routing the logs.
  This plugin supports the creation of index templates and ILM policies associated to them during the process of creating a new index in ES.

- `fluent-plugin-prometheus`: Enabling prometheus monitoring

- `fluent-plugin-record-modifier`: record_modifier filter faster and lightweight than embedded transform_record filter.

- `fluent-plugin-grafana-loki`: enabling Loki as destination for routing the logs

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
ARG BASE_IMAGE=fluent/fluentd:v1.17.1-debian-1.0


FROM $BASE_IMAGE

## 1- Update base image installing fluent plugins. Executing commands `gem install <plugin_name>`

# Use root account to use apk
USER root

RUN buildDeps="sudo make gcc g++ libc-dev" \
 && apt-get update \
 && apt-get install -y --no-install-recommends $buildDeps \
 && sudo gem install fluent-plugin-elasticsearch -v '~> 5.4.3' \
 && sudo gem install fluent-plugin-prometheus -v '~> 2.2' \
 && sudo gem install fluent-plugin-record-modifier -v '~> 2.2'\
 && sudo gem install fluent-plugin-grafana-loki -v '~> 1.2'\
 && sudo gem sources --clear-all \
 && SUDO_FORCE_REMOVE=yes \
    apt-get purge -y --auto-remove \
                  -o APT::AutoRemove::RecommendsImportant=false \
                  $buildDeps \
 && rm -rf /var/lib/apt/lists/* \
 && rm -rf /tmp/* /var/tmp/* /usr/lib/ruby/gems/*/cache/*.ge

## 2) (Optional) Copy customized fluentd config files (fluentd as aggregator)

COPY ./conf/fluent.conf /fluentd/etc/
COPY ./conf/forwarder.conf /fluentd/etc/
COPY ./conf/prometheus.conf /fluentd/etc/

## 3) Modify entrypoint.sh to configure sniffer class
COPY entrypoint.sh /fluentd/entrypoint.sh

# Environment variables
ENV FLUENTD_OPT=""

## 4) Change to fluent user to run fluentd
# Run as fluent user. Do not need to have privileges to access /var/log directory
USER fluent
ENTRYPOINT ["tini",  "--", "/fluentd/entrypoint.sh"]
CMD ["fluentd"]
```


### Helm chart Installation

For installing fluentd, helm chart from the community will be used.

Fluentd will be deployed as Kubernetes `Deployment` (not default as Daemonset), enabling multiple PODs service replicas, so it can be accesible by Fluentbit pods.

Since it does not need to access neither host directories for collecting logs or Kubernetes API to enrich the collected logs, all default privileges when installing as a `DaemonSet`, will be removed.

-   Step 1: Create fluent namespace (if it has not been previously created)

    ```shell
    kubectl create namespace fluent
    ```

-   Step 2: Create Config Map containing fluentd configuration file


-   Step 2. Create fluentd TLS certificate to secure communication between fluent-bit and fluentd (forwarder protocol).

    To configure fluentd to use TLS, the path to the files containing the TLS certificate and private key need to be provided. The TLS Secret containing the certificate and key can be mounted in fluentd POD in a specific location (`/etc/fluent/certs`), so fluentd proccess can use them.

    Certmanager's ClusterIssuer `ca-issuer`, created during [certmanager installation](/docs/certmanager/), can be used to generate automatically fluentd's TLS Secret automatically.

    Create the Certificate resource:

    ```yml
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: fluentd-tls
      namespace: fluent
    spec:
      # Secret names are always required.
      secretName: fluentd-tls
      duration: 2160h # 90d
      renewBefore: 360h # 15d
      commonName: fluentd.${CLUSTER_DOMAIN}
      isCA: false
      privateKey:
        algorithm: ECDSA
        size: 256
      usages:
        - server auth
        - client auth
      dnsNames:
        - fluentd.${CLUSTER_DOMAIN}
      isCA: false
      # ClusterIssuer: ca-issuer.
      issuerRef:
        name: ca-issuer
        kind: ClusterIssuer
        group: cert-manager.io
    ```

    {{site.data.alerts.note}}

    Substitute variables in the above yaml (`${var}`) file before deploying manifest.
    -   Substitute `${CLUSTER_DOMAIN}` with the domain used in the cluster. For example: `homelab.ricsanfre.com`

    {{site.data.alerts.end}}

    Then, Certmanager automatically creates a Secret like this:

    ```yml
    apiVersion: v1
    kind: Secret
    metadata:
      name: fluentd-tls
      namespace: fluent
    type: kubernetes.io/tls
    data:
      ca.crt: <ca cert content base64 encoded>
      tls.crt: <tls cert content base64 encoded>
      tls.key: <private key base64 encoded>
    ```

-   Step 2. Create forward protocol shared key

    Generate base64 encoded shared key
    ```shell
    echo -n 'supersecret' | base64
    ```

    Create a Secret `fluentd-secrets` containing all secrets (fluent shared key, elastic search user and passworkd)
    ```yml
    apiVersion: v1
    kind: Secret
    metadata:
      name: fluent-secrets
      namespace: fluent
    type: Opaque
    data:
      fluentd-shared-key: <base64 encoded password>
      es-username: <base64 encoded user name>
      es-password: <base64 encoded user name>
    ```

    Elastic Search user, `fluentd` and its password should match the ones created when installing ElasticSearch. See ["ElasticSearch Installation: File-based authentication"](docs/elasticsearch/#file-based-authentication)


## Configuring Fluentd


### Input Configuration (Forward input plugin)

### ElasticSearch Output Configuration

### Loki Output Configuration