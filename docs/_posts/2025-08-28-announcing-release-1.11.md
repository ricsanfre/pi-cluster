---
layout: post
title:  Kubernetes Pi Cluster relase v1.11
date:   2025-08-28
author: ricsanfre
description: PiCluster News - announcing release v1.11
---


Today I am pleased to announce the eleventh release of Kubernetes Pi Cluster project (v1.11).

Main features/enhancements of this release are:


## FluxCD Operator

Cluster bootstrapping process have been migrated from CLI to [FluxCD Operator](https://github.com/controlplaneio-fluxcd/flux-operator).

Flux Operator is a Kubernetes controller for managing the lifecycle of Flux CD. It uses Kubernetes Operator design pattern so, Flux deployment can be configured via customized CRDs.

The Flux Operator is an open-source project developed by ControlPlane that offers an alternative to the Flux Bootstrap procedure, it removes the operational burden of managing Flux across fleets of clusters by fully automating the installation, configuration, and upgrade of the Flux controllers based on a declarative API.

See details in [FluxCD- Bootstrap cluster using FluxCD Operator](docs/fluxcd/#fluxcd-operator).

## Enabling Spegel Mirroring

K3S's Embedded Registry Mirror (Spegel) has been activated, so images pulling process can be speed-up

[Spegel](https://spegel.dev/) is a stateless distributed OCI registry mirror that allows peer-to-peer sharing of container images between nodes in a Kubernetes cluster.

Spegel enables each node in a Kubernetes cluster to act as a local registry mirror, allowing nodes to share images between themselves. Any image already pulled by a node will be available for any other node in the cluster to pull. This has the benefit of reducing workload startup times and egress traffic as images will be stored locally within the cluster

See further details in [K3S Installation - Embedded Mirror Registry](/docs/k3s-installation/#enabling-embedded-registry-mirror).

## Prometheus refactoring

Cluster K3s monitoring with Prometheus has been refactored so automatic upgrade process of Prometheus dashboards and rules for K3s from Prometheus mixins is now in place.
In order to solve duplicate metrics issue with K3s, dashboards and Prometheus rules, embedded into Kube-prom-stack helm char, had to be manually updated with every new release, to update jobs labels to match K3s configuration (kubelet component as unique process to be monitored). See details in [picluster- issue#67](https://github.com/ricsanfre/pi-cluster/issues/67)

The `kube-prometheus` project uses monitoring mixins to generate alerts and dashboards. Monitoring mixins are a collection of Jsonnet libraries that generate Grafana dashboards and Prometheus rules and alerts. The [`kubernetes-mixin`](https://github.com/kubernetes-monitoring/kubernetes-mixin) is a mixin that generates dashboards and alerts for Kubernetes. The `node-exporter`, `coredns`, `grafana`, `prometheus` and `prometheus-operator` mixins are also used to generate dashboards and alerts for the Kubernetes cluster.

To generate K3s-compliant Prometheus Monitoring Mixins, replicating building process of kube-prom-stack, a set of scripts have been created to automate the process of generating Prometheus rules and Grafana dashboards for K3s (automatically updating job label) from Prometheus mixins.

See further details in [K3S Installation - Prometheus Mixin](/docs/prometheus/#creating-grafana-and-prometheus-rules-from-available-mixins).

## Logs collection/distribution refactoring (Fluentbit and Fluentd)

Logs collection and distribution system has been refactored.

Fluent-bit configuration has been updated to use new YAML configuration, extracting configuration to external configMap and enabling hot-reloading. Also old  configuration options, not in use have been removed (TZ management, Kubernetes merge fields), and documentation has been updated accordingly.

Also, Fluentd configuration has been extracted to use external configMap instead of embedded helm chart configuration and all records manipulation rules have been moved to Fluent-bit to optimize logs processing. Documentation has been also updated accordingly.

See further details in [Logs collection - Fluent-bit](/docs/fluent-bit) and [Logs aggregation and distribution - Fluentd](/docs/fluentd).

## Keycloak refactoring

Installation of Keycloak using Keycloak Operator instead of Bitnami's Helm Chart. Keycloak Operator simplifies the deployment and management of Keycloak instances on Kubernetes by automating tasks such as installation, configuration, scaling, and updates.

It allows deployment of Keycloak in High Availability mode using an external database (PostgreSQL) in a declarative way (Kubernetes Operator pattern).

Also, [keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli) has been added to automatically configure Keycloak from config files. **keycloak-config-cli** is a Keycloak utility to ensure the desired configuration state for a realm based on a JSON/YAML file. It can be used to apply GitOps and IaC (Infrastructure as Code) concepts to Keycloak configuration.

See further details in [Keycloak Installation - Keycloak operator](/docs/sso/#keycloak-operator) and [Keycloak Configuration - keycloak-config-cli](/docs/sso/#automating-configuration-changes-with-keycloak-config-cli).

Also observability of Keycloak has been improved by adding Prometheus monitoring and Grafana dashboards. See details in [Keycloak Monitoring](/docs/sso/#keycloak-observability).


## Improve cluster observability

Add monitoring of all External Services (services running out-side the Kubernetes Cluster) and Internal Services (services running in the Kubernetes Cluster) with Prometheus.

-  Monitoring of cluster external services has been improved
    -  OS level metrics and logs of external nodes (`node1`) using Prometheus NodeExporter integrated with Kube-Prometheus-stack and Fluent-bit agent for collecting logs integrated with Fluentd service running in the Kubernetes cluster. Further details in [External Service Node - Observability](/docs/external/#observability)
    -  Monitoring of external services running in `node1`: 
        -   Kuberentes API load balancer (HAProxy). Further details in [K3s Monitoring - HA Proxy](/docs/prometheus/#haproxy-metrics)
        -   Secret Management solution (Vault). Further details in [Vault - Observability](/docs/vault/#observability)
        -   Bind9 DNS using Prometheus Bind Exporter. Further details in [DNS Homelab Architecture - Observability](/docs/dns/#observability)
    -  Monitoring of external services running in Cloud: Minio backup service. Further details in [Minio - Observability](/docs/s3-backup/#observability)
    -  Monitoring of cluster router based on OpenWrt. OpenWrt metrics are collected using Prometheus OpenWrt Exporter and syslogs are forwarded to syslog server running in Fluentd service. Further details in [OpenWrt - Observability](/docs/openwrt/#openwrt-observability)

-  Monitoring of all Internal Services (services running in the Kubernetes Cluster) has been also improved.
    -   Fix monitoring issues with some of the services: etcd, Grafana, ElasticSearch
    -   Add monitoring of remaining services: Cert-Manager, External-Secrets, FluxCD.


## Project Documentation review

Whole project documentation has been reviewed and updated.

-  Deprecated technologies documentation has been updated, highlighting documentation as deprecated and without maintenance and reviewing references to deprecated technologies in all documentation.
-  Documentation has been reviewed and standardized with common layout of sections: Installation, Configuration, Obervability, etc.
-  Some of the main documents have been refactored splitting content into different pages to improve readability and maintenance:
    -  Prometheus documentation
        -  Grafana installation/configuration has been extracted to its own page. [Observability Visualization (Grafana)](/docs/grafana/)
        -  Monitoring configuration of each service has been extracted to Observability section to corresponding service document
    -  Fluentbit/Fluentd documentation
        -  Fluent-bit and Fluentd documentation has been separated into two different documents. [Logs collection - Fluent-bit](/docs/fluent-bit) and [Logs aggregation and distribution - Fluentd](/docs/fluentd).
    -  Cert-manager documentation
        -  Cert-bot documentation has been extracted to a separate document: [TLS Certificates (Certbot)](/docs/certbot/)
    -  Backup documentation
        -  OS-file system backup (Restic) documentation has been extracted from Kubernetes backup document to a separate document: [OS Filesystem Backup (Restic)](/docs/restic/)


## Release v1.11.0 Notes

Major update of project documentation, Prometheus/Fluent-bit/Fluentd refactoring, Spegel Mirroring, Keycloak Operator, Flux Operator

### Release Scope

-   Flux Bootstrap process migration from CLI to FluxCD Operator]
-   Add Registry Mirror (Spegel)
-   Prometheus refactoring
     -   Automate upgrade process of prometheus dashboards and rules for K3s from Prometheus mixins.
     -   Use of ScrapeConfig CRD for external services monitoring
-   Logs collection/distribution refactoring (Fluentbit and Fluentd)
    -   Fluentbit
        -   Use new YAML configuration
        -   Extract configuration to external configMap and enable hot-reloading
        -   Remove old configuration options
            -   TZ management
            -   Kubernetes merge fields
    -   Fluentd
        -   Extract configuration to external configMap
        -   Move records manipulation rules to Fluent-bit
-   Kafka Zookeeper deprecation and migration to KRAFT
-   Monitor with Prometheus all External Services (services running out-side the Kubernetes Cluster):
    -   Metrics and logs at OS level (`node1`)
        -   Metrics export using NodeExporter
        -   Logs collection using Fluent-bit collector
    -   Services running in `node1`
        -   Logs and node-level metrics
        -   HAProxy
        -   Vault
        -   Bind9
        -   OpenWrt
    -   Services running in Cloud
        - Minio external service
-   Monitor with Prometheus all Internal Services (services running in the Kubernetes Cluster).
     -   Fix monitoring issues with some of the services:
          -   etcd
          -   Grafana
         -   ElasticSearch
     -   Add monitoring of remaining services
         -   Cert-Manager
         -   External-Secrets
         -   FluxCD
         -   MongoDB
-    Keycloak application refactoring
      -   Installation in HA mode using Keycloak Operator instead of Bitnami's Helm Chart
      -   keycloak-config-cli to automatically configure Keycloak from config files.

-   Project documentation review
    - Update deprecated technologies documentation.
        - Highlight documentation as deprecated and without maintenance
        - Review references to deprecated technologies in all documentation
    - Standardize documentation
        - Common layout of sections: Installation, Configuration, Obervability, etc.
        - Refactor documentation
            - Prometheus doc
                - Extract Grafana installation/configuration to its own page
                - Extract monitoring configuration of each service to Observability section to corresponding service document
            - Fluentbit/Fluentd documentation
                - Extract Fluent-bit and Fluentd documentation to separate documents
            - Cert-manager doc
                - Extract cert-bot documentation to a separate document
            - Backup documentation
                - Extract OS-backup(Resti) to a separate document