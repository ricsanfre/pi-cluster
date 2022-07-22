---
title: Log Management Arquitecture (EFK)
permalink: /docs/logging/
description: How to deploy centralized logging solution based on EFK stack (Elasticsearch- Fluentd/Fluentbit - Kibana) in our Raspberry Pi Kuberentes cluster.
last_modified_at: "22-07-2022"

---

**ELK Stack (Elaticsearch - Logstash - Kibana)** is a typical centralized architecture for log monitoring of IT infrastructure, where:

- Elasticsearch is used as logs storage and search engine.
- Logstash used for collecting, aggregate and distribute logs.
- Kibana is used as visualization layer.

As an alternative, **EFK stack (Elastic - Fluentd/Fluentbit - Kibana)** can be used. In this case, Fluentd, or its lightweight version Fluentbit, can be used, instead of Logstash, for doing the collection, parsing, aggregation and distribution of logs.

EFK stack will be deployed as centralized logging solution for the K3S cluster, and to collect the logs of external nodes part of my homelab (i.e.: `gateway`).

![K3S-EFK-Architecture](/assets/img/efk_logging_architecture.png)


## ARM/Kubernetes support

In June 2020, Elastic [announced](https://www.elastic.co/blog/elasticsearch-on-arm) that starting from 7.8 release they will provide multi-architecture docker images supporting AMD64 and ARM64 architectures.

Fluentd and Fluentbit both support ARM64 docker images for being deployed on Kubernetes clusters with the built-in configuration needed to automatically collect and parsing containers logs.


## Why EFK and not ELK

Fluentd/Fluentbit and Logstash offers similar capabilities (log parsing, routing etc) but I will select Fluentd/Fluentbit because:

- **Performance and footprint**: Logstash consumes more memory than Fluentd. Logstash is written in Java and Fluentd is written in Ruby (Fluentbit in C). Fluentd is an efficient log aggregator. For most small to medium-sized deployments, fluentd is fast and consumes relatively minimal resources.

- **Log Parsing**: Fluentd uses standard built-in parsers (JSON, regex, csv etc.) and Logstash uses plugins for this. This makes Fluentd favorable over Logstash, because it does not need extra plugins installed.

- **Kubernetes deployment**: Docker has a built-in logging driver for Fluentd, but doesn’t have one for Logstash. With Fluentd, no extra agent is required on the container in order to push logs to Fluentd. Logs are directly shipped to Fluentd service from STDOUT without requiring an extra log file. Logstash requires additional agent (Filebeat) in order to read the application logs from STDOUT before they can be sent to Logstash.

- **Fluentd** is a CNCF project.

## Collecting cluster logs

### Container logs

In Kubernetes, containerized applications that log to `stdout` and `stderr` have their log streams captured and redirected to log files on the nodes (`/var/log/containers`). To tail these log files, filter log events, transform the log data, and ship it off to the Elasticsearch logging backend, a process like, fluentd/fluentbit can be used.

To learn more about kubernetes logging architecture check out [“Cluster-level logging architectures”](https://kubernetes.io/docs/concepts/cluster-administration/logging) from the official Kubernetes docs. Logging architecture using [node-level log agents](https://kubernetes.io/docs/concepts/cluster-administration/logging/#using-a-node-logging-agent) is the one implemented with fluentbit/fluentd log collectors. Fluentbit/fluentd proccess run in each node as a kubernetes' daemonset with enough privileges to access to host file system where container logs are stored (`/var/logs/containers` in K3S implementation).

[Fluentbit and fluentd official helm charts](https://github.com/fluent/helm-charts) deploy the fluentbit/fluentd pods as privileged daemonset.

{{site.data.alerts.important}}

Log format used by Kubernetes is different depending on the container runtime used. `docker` container run-time generates logs in JSON format. 

`containerd` run-time, used by K3S, uses CRI log format:

```
<time_stamp> <stream_type> <P/F> <log>

where:
  - <time_stamp> has the format `%Y-%m-%dT%H:%M:%S.%L%z` Date and time including UTC offset
  - <stream_type> is `stdout` or `stderr`
  - <P/F> indicates whether the log line is partial (P), in case of multine logs, or full log line (F)
  - <log>: message log
```
{{site.data.alerts.end}}

{{site.data.alerts.note}}
In addition to container logs, same Fluentd/Fluentbit agents deployed as daemonset can collect and parse logs from systemd-based services and OS filesystem level logs (syslog, kern.log, etc).
{{site.data.alerts.end}}

### Kubernetes logs

In K3S all kuberentes componentes (API server, scheduler, controller, kubelet, kube-proxy, etc.) are running within a single process (k3s). This process when running with `systemd` writes all its logs to  `/var/log/syslog` file. This file need to be parsed in order to collect logs from Kubernetes (K3S) processes.

K3S logs can be also viewed with `journactl` command

In master node:

```shell
sudo journactl -u k3s
```

In worker node:

```shell
sudo journalctl -u k3s-agent
```

### Host logs

OS level logs (`/var/logs`) can be collected with the same agent deployed to collect containers logs (daemonset)  

{{site.data.alerts.important}}

Some of Ubuntu system logs stored are `/var/logs` (auth.log, systlog, kern.log) have a `syslog` format but with some differences from the standard:
 - Priority field is missing
 - Timestamp is formatted using system local time.

The syslog format is the following:
```
<time_stamp> <host> <process>[<PID>] <message>
Where:
  - <time_stamp> has the format `%b %d %H:%M:%S`: local date and time not including timezone UTC offset
  - <host>: hostanme
  - <process> and <PID> identifies the process generating the log
```
Fluentbit/fluentd custom parser need to be configured to parse this kind of logs.

{{site.data.alerts.end}}

## Log collection, aggregation and distribution architectures

### Forwarder-only architecture

Forwarder-only architecture pattern can be implemented with Fluentbit/Fluentd

![forwarder-only-architecture](/assets/img/logging-forwarder-only.png)

This pattern includes having a logging agent, based on fluentbit or fluentd. deployed on edge (forwarder), generally where data is created, such as Kubernetes nodes, virtual machines or baremetal servers. These forwarder agents collect, parse and filter logs from the edge nodes and send data direclty to a backend service.

**Advantages**

- No aggregator is needed; each agent handles [backpressure](https://docs.fluentbit.io/manual/administration/backpressure).

**Disadvantages**

- Hard to change configuration across a fleet of agents (E.g., adding another backend or processing)
- Hard to add more end destinations if needed


### Forwarder/Aggregator Architecture

As an alternative to forwarder-only logging architecture pattern, forwarder/aggregator architecture can be implemented with Fluentbit/Fluentd.

![forwarder-forwarder-aggregator-architecture](/assets/img/logging-forwarder-aggregator.png)

Similar to the forwarder-only deployment, lightweight logging agent instance is deployed on edge (forwarder) close to data sources (kubernetes nodes, virtual machines or baremetal servers). In this case, these forwarders do minimal processing and then use the forward protocol to send data to a much heavier instance of Fluentd or Fluent Bit (aggregator). This heavier instance may perform more filtering and processing before routing to the appropriate backend(s).

**Advantages**

- Less resource utilization on the edge devices (maximize throughput)

- Allow processing to scale independently on the aggregator tier.

- Easy to add more backends (configuration change in aggregator vs. all forwarders).

**Disadvantages**

- Dedicated resources required for an aggregation instance.

With this architecture, in the aggregation layer, logs can be filtered and routed not only to Elastisearch database (default route) but to a different backend to further processing. For example Kafka can be deployed as backend to build a Data Streaming Analytics architecture (Kafka, Apache Spark, Flink, etc) and route only the logs from a specfic application. 

{{site.data.alerts.note}}

For additional details about all common architecture patterns that can be implemented with Fluentbit and Fluentd see ["Common Architecture Patterns with Fluentd and Fluent Bit"](https://fluentbit.io/blog/2020/12/03/common-architecture-patterns-with-fluentd-and-fluent-bit/).

{{site.data.alerts.end}}

## EFK Installation procedure

The procedure for deploying EFK stack is described in the following pages:

1. [Elasticsearch and Kibana installation](/docs/elasticsearch/)

2. Log collection, aggregation and distribution. Two alternatives.

   2.1. [Fluentbit/Fluentd forwarder/aggregator architecture installation](/docs/logging-forwarder-aggregator/). Fluentd as aggregator and fluentbit as forwarder.

   2.2. [Fluentbit/Fluentd forwarder-only architecture installation](/docs/logging-forwarder-only/). Fluentbit or fluentd deployed as agent in all kubernetes nodes. These agents collect aggregate and send the logs to ES backend directly (no aggregation layer).

## References

- [Kubernetes Logging 101](https://www.magalix.com/blog/kubernetes-logging-101)

- [Kubernetes Logging: Comparing Fluentd vs. Logstash](https://platform9.com/blog/kubernetes-logging-comparing-fluentd-vs-logstash/)

- [How To Set Up an Elasticsearch, Fluentd and Kibana (EFK) Logging Stack on Kubernetes](https://www.digitalocean.com/community/tutorials/how-to-set-up-an-elasticsearch-fluentd-and-kibana-efk-logging-stack-on-kubernetes) 

- [Kubernetes Logging and Monitoring: The Elasticsearch, Fluentd, and Kibana (EFK) Stack](https://platform9.com/blog/kubernetes-logging-and-monitoring-the-elasticsearch-fluentd-and-kibana-efk-stack-part-1-fluentd-architecture-and-configuration/)

- [Running ELK on Kubernetes with ECK](https://coralogix.com/blog/running-elk-on-kubernetes-with-eck-part-1/)

- [How to Setup an ELK Stack and Filebeat on Kubernetes](https://www.deepnetwork.com/blog/2020/01/27/ELK-stack-filebeat-k8s-deployment.html)

- [Fluentd Kubernetes Deployment](https://docs.fluentd.org/container-deployment/kubernetes)

- [Common Architecture Patterns with Fluentd and Fluent Bit](https://fluentbit.io/blog/2020/12/03/common-architecture-patterns-with-fluentd-and-fluent-bit/)
