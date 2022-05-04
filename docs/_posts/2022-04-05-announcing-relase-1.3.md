---
layout: post
title:  Kubernetes Pi Cluster relase v1.3
date:   2022-04-5
author: ricsanfre
---

Today I am very happy to announce the third release of Kubernetes Pi Cluster project (v1.3). 

Main feature included in this release: adding service mesh architecture based on Linkerd


![picluster-linkerd](/assets/img/linkerd-architecture.png)


## The journey so far

This is the summary of the functionality added by the different releases of the project

### Release v1.3.0 - 2022-04-05

Adding service mesh architecture to kubernetes cluster

#### Release Scope:

  - Deployment of Linkerd service mesh architecture
  - Linkerd integration with Cert-manager for automatically generate Linkerd trust anchor and rotate Linkerd identity issuer certificate and private keys.
  - Meshing cluster services with Linkerd.
  - Disabling Elasticsearch TLS default configuration. Secure communications provided by Linkerd.

### Release v1.2.0 - 2022-02-03

Launched of this website (picluster.ricsanfre.com) and improvements in logging and monitoring solution

#### Release Scope:

  - New project website (picluster.ricsanfre.com) created from previous documentation files using Jekyll and GitHub pages
  - Fluentbit as unique logs collector solution (Fluentbit replacing Fluentd within the cluster)
  - Adding Velero and Minio Metrics to Prometheus
  - Activating Traefik's access logs and integrate them into EFK

### Release v1.1.0 - 2021-12-31

Redesign of the hardware architecture adding local storage (SSD disks) to all cluster nodes and including backup solution for the cluster based on Velero/Restic


![picluster-release1](/assets/img/pi-cluster-2.0.png)


![picluster-backup](/assets/img/pi-cluster-backup-architecture.png)


#### Release Scope:

  - New cluster hardware. Supporting two different cluster storage architectures (centralized SAN and dedicated disks)
  - Cluster backup solution based on Minio S3 server, Velero and Restic
  - Ansible playbooks refactoring
  - Traefik and Longhorn metrics integrated into Prometheus

### Release v1.0.0 - 2021-11-18
  
Initial complete release. First cluster hardware architecture using USB Flash-drives for booting the Raspberry Pis and building a iSCSI SAN server for providing local storage to cluster nodes.

![picluster-release1](/assets/img/pi-cluster.png)


#### Release Scope:

- Kuberentes K3S deployment on Raspeberry-PI 4 based nodes
- Centralized Storage Architecture using iSCSI SAN server.
- Configuration of basic Kubernetes services
  - Traefik as Ingress Controller
  - Metallb as Load Balancer
  - CertManager as SSL certificates manager
  - Longhorn as distributed storage solution
  - EFK as centralized logging solution
  - Prometheus as monitoring solution
- Automation through cloud-init and Ansible
  - Cloud-init configuration files for initial setup of the cluster nodes
  - Ansible playbooks and roles for automatically configure OS, install K3S and install basic services
- Documentation of the installation and configuration process
