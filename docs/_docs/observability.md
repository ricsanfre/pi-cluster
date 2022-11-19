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
- [Loki](https://grafana.com/oss/loki/) (logs monitoring)
- [Grafana Tempo](https://grafana.com/oss/tempo/) (traces monitoring)
- [Prometheus](https://prometheus.io/) (metrics monitoring)
- [Grafana](https://grafana.com/oss/grafana/) (monitoring single pane of glass)

Logging solution is complemented with a log analytics solution based on Elasticsearch and Kibana.

![K3S-logs-observability-analytics](/assets/img/logs_loki_es.png)

Common logs collection and distrution layer based on fluentbit/fluentd is used to feed logs to Logs Analytics platform (ES) and Logs Monitoring platform (Loki).

