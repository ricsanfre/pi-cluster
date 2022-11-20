---
title: Observability solution
permalink: /docs/observability/
description: Observability solution for Raspberry Pi Cluster. Solution based on Grafana Loki (logs), Prometheus (metrics) and Tempo (traces). Observability solution combined with Logs analytics solution based on ElasticSearch and Kibana.
last_modified_at: "19-11-2022"

---


The observability/monitoring solution for Raspberry Pi cluster is the following:

![observability-architecture](/assets/img/observability-architecture.png)

This solution allow to monitor application traces, logs and metrics providing a single pane of glass where all information from an application can be showed in dashboards.

Monitoring solution is based on the following components:
- [Loki](https://grafana.com/oss/loki/) (logging)
- [Grafana Tempo](https://grafana.com/oss/tempo/) (distributed tracing)
- [Prometheus](https://prometheus.io/) (monitoring)
- [Grafana](https://grafana.com/oss/grafana/) (single pane of glass)

Logging solution is complemented with a log analytics solution based on Elasticsearch and Kibana.

![K3S-logs-observability-analytics](/assets/img/logs_loki_es.png)

Common log collection and distrution layer, implemented with fluentbit/fluentd, feeds logs to Log Analytics platform (ES) and Log Monitoring platform (Loki).


## Observability solution installation procedure

The procedure for deploying observability solution stack is described in the following pages:

1. **Logging**
   - [Logging Architecture (EFK + LG)](/docs/logging/)
   - [Log Aggregation - Loki installation and configuration](/docs/loki/)
   - [Log Analytics - Elasticsearch and Kibana installation and configuration](/docs/elasticsearch/)
   - [Log collection and distribution - Fluentbit/Fluentd installation and configuration](/docs/logging-forwarder-aggregator/)
2. **Monitoring**
   - [Prometheus installation and configuration](/docs/prometheus/)
3. **Distributing tracing**
   - [Grafana Tempo installation and configuration](/docs/tracing/)