---
layout: post
title:  Kubernetes Pi Cluster relase v1.7
date:   2023-06-24
author: ricsanfre
description: PiCluster News - announcing release v1.7
---


Today I am pleased to announce the seventh release of Kubernetes Pi Cluster project (v1.7). 

Main features/enhancements of this release are:


## Hybrid x86/ARM nodes support

Adding support for hybrid x86/ARM bare metal nodes, combining in the same cluster Raspberry PI nodes (ARM) and x86 mini PCs (HP Elitedesk 800 G3).

Initially the intent of this project was to build a kuberentes cluster using only Raspberry PI nodes. Due to Raspberry shortage during last 2 years, which makes impossible to buy them at reasonable prices, I have decided to look for alternatives to be able to scale up my cluster.

Use old x86 refurbished mini PCs, with Intel i5 processors, has been the solution. These mini PCs provide similar performance to RaspberryPi's Quadcore ARM Cortex-A72, but its memory can be expanded up to 32GB of RAM (Raspberry PI higher model only supports 8GB RAM). As a drawback power consumption of those mini PCs are higher that Raspberry PIs.

The overall price of a mini PC, intel i5 + 8 GB RAM + 256 GB SSD disk + power supply, ([aprox 130 €](https://www.amazon.es/HP-EliteDesk-800-G3-reacondicionado/dp/B09TL2N2M8/)) is cheaper than the overal cost of building a cluster node using a Rasbperry PI: cost of Raspberry PI 8GB (100€) + Power Adapter (aprox 10 €) + SSD Disk ([aprox 20 €](https://www.amazon.es/Kingston-SSD-A400-Disco-s%C3%B3lido/dp/B01N5IB20Q)) + USB3.0 to SATA converter ([aprox 20€](https://www.amazon.es/Startech-USB3S2SAT3CB-Adaptador-3-0-2-5-negro/dp/B00HJZJI84))


![!Cluster-3.0](/assets/img/pi-cluster-3.0.png)


Ansible automation code has been update to be able to configure both type of nodes.

## Ubuntu OS installation automation 

### Ubuntu Raspberry PI automation

Process of burning Raspberry Pi's ubuntu cloud image to USB Flash Disk/SSD and copying the initial cloud-init configuration has been automated using a Linux based PC.

See ["Automating Image creation (USB Booting)"](/docs/ubuntu/rpi/#automating-image-creation-usb-booting)


### Ubuntu autoinstall over PXE (x86 nodes)

Ubuntu OS installation on x86 nodes has been automated using PXE. PXE server has been added to the cluster, and installation process can be launched from network.

See ["OS Installation - x86 (PXE sever)"](/docs/ubuntu/x86/) and ["PXE Server"](/docs/pxe-server/).


## Ubuntu OS upgrade from 20.04 to 22.04

OS has been upgraded to latest LTS (Long Term Support) release: Ubuntu 22.04.2.
Ansible OS configuration tasks have been updated to fit the new OS release.

## K3S Upgrade automation

k3s software version upgrade automated using Rancher's system-upgrade-controller. This controller uses a [custom resource definition (CRD)], `plan`, to schedule upgrades based on the configured plans. See [K3S Automated Upgrades documentation](https://docs.k3s.io/upgrades/automated)


ArgoCD packaged application has been created to deploy system-upgrade-controller app and to generate upgrade plans. Just modifiying a couple of files in the github repository, K3s can be upgraded automatically.

## New Kuberentes S3 Storage service based on Minio

Deploy Minio as Kuberentes service, so it can be used as common long-term backend for Grafana's observability stack (Loki, Tempo and in the future Mimir).
Previous Minio service, cluster external service, is maintained only as backend of the backup solution and it has been redeployed as a cluster offsite service, running in OCI (Oracle Cloud Infrastructure)

Implementation details:

- [vanilla Minio helm chart](https://github.com/minio/minio/tree/master/helm/minio) has been used instead of new Operator. Not need to support multi-tenant installations and  Vanilla Minio helm chart supports also the automatic creation of buckets, policies and users.
- Deploy Minio as Argo CD application
- Reconfigure Loki and Tempo to use the new Minio internal service
- Re-deploy Minio external service as cluster offsite service, running on Oracle Cloud Infrastructure


## ElasticSearch/Fluentd Enhancements

### Users and Roles configuration

[Auth Realms](https://www.elastic.co/guide/en/elasticsearch/reference/current/realms.html) to configure ES' users and roles. No tricks are used to define `elastic` admin passwords and defining [Auth File Realms](https://www.elastic.co/guide/en/elasticsearch/reference/current/file-realm.html) and roles which is directly supported by [ECK operator](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-users-and-roles.html).

Specific user and role have been created for fluentd and prometheus-elasticsearch-exporter. Default `elastic` super user is not used anymore. ES roles has been created only with the minimum set of permisson required. For example, fluentd requires permission to create Index, index templates, ILM, ingest data, etc.).

### ILM policies and Index templates configuration

Fluentd has been reconfigured to create different ES indices per application (dynamic indices) and to apply ES ILM policies (data retention) and index templates (data mapping)

[Index Templates](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-templates.html) are used for controlling the way ES automatically maps/discover log's field data types and the way ES indexes these fields. [ES Index Lifecycle Management (ILM)](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-lifecycle-management.html) is used for automating the management of indices, and setting data retention policies.

Fluentd's elastic-search-plugin support the creation of dynamic indices, creation of ILM policies and index templates.


## Implementation Details

Fluend elastic-search-plugin already support ILM and Index templates configuration: [See plugin FAQ](https://github.com/uken/fluent-plugin-elasticsearch/blob/master/README.Troubleshooting.md#example-ilm-settings)


## Release v1.7.0 Notes

Hybrid x86/ARM kubernetes cluster support (x86 and ARM cluster nodes can be used within the same Pi-Cluster).

### Release Scope:

  - Hybrid x86/ARM kubernetes cluster support.
    - Combine Raspberry PI 4B nodes and x86 mini PCS (HP Elitedesk 800 G3) in the same cluster.
    - Ansible code update for supporting configuration of Raspberry PI nodes and x86 nodes.

  - Ubuntu OS installation automation
    - Automate process of creating boot USB disk for Raspberry PI nodes.
    - x86 nodes autoinstallation using PXE

  - Node's Operating System upgrade from Ubuntu 20.04 LTS to Ubuntu 22.04 LTS.
    - Node's installation/configuration documentation update.
    - Ansible OS configuration tasks updated to fit the new OS release.

  - K3s automated upgrade
     - Deploy Rancher's system-upgrade-controller app. This controller uses a [custom resource definition (CRD)], `plan`, to schedule upgrades based on the configured plans.
     - ArgoCD packaged application created to deploy system-upgrade-controller app and to generate upgrade plans.

  - Logging solution enhancements
    - ES/Kibana upgrade to release 8.6
    - ElasticSearch's ILM policies (data retention policies) and Index templates (data model) configuration for Fluentd logs.
    - Fluentd dynamic indices creation and configuration.
    - Elasticsearch roles and users definition. File Auth Realm configured through ECK. Different roles and users created (fluentd, prometheus-elasticsearch-exporter)

  - Automation enhancements
    - New Ansible-runtime environment in a docker container, ansible-runner containing all ansible packages and its dependencies. Isolating ansible run-time environment from local server.
