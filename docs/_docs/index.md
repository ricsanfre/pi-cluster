---
title: Welcome to Rasperry Pi Cluster Project
permalink: /docs/home/
redirect_from: /docs/index.html
---


## Scope
The scope of this project is to create a kubernetes cluster at home using **Raspberry Pis** and **Ansible** to automate the deployment and configuration.

This is an educational project to explore kubernetes cluster configurations using an ARM architecture and its automation using Ansible.

As part of the project the goal is to use a lightweight Kubernetes flavor based on [K3S](https://ks3.io/) and deploy cluster basic services such as: 1) distributed block storage for POD's persistent volumes like [LongHorn](https://longhorn.io/), 2) centralized monitoring tool like [Prometheus](https://prometheus.io/) 3) centralized log managemeent like EFK stack ([Elasticsearch](https://www.elastic.co/elasticsearch/)-[Fluentbit](https://fluentbit.io/)-[Kibana](https://www.elastic.co/kibana/) and 3) backup/restore solution for the cluster like [Velero] and [Restic](https://restic.io/).


The following picture shows the set of opensource solutions used for building this cluster:

![Cluster-Icons](/assets/img/pi-cluster-icons.png)


## Design Principles

- Use ARM 64 bits operating system enabling the possibility of using Raspberry PI B nodes with 8GB RAM. Currently only Ubuntu supports 64 bits ARM distribution for Raspberry Pi.
- Use ligthweigh Kubernetes distribution (K3S). Kuberentes distribution with a smaller memory footprint which is ideal for running on Raspberry PIs
- Use of distributed storage block technology, instead of centralized NFS system, for pod persistent storage.  Kubernetes block distributed storage solutions, like Rook/Ceph or Longhorn, in their latest versions have included ARM 64 bits support.
- Use of opensource projects under the [CNCF: Cloud Native Computing Foundation](https://www.cncf.io/) umbrella
- Use latest versions of each opensource project to be able to test the latest Kubernetes capabilities.
- Use of [Ansible](https://docs.ansible.com/) for automating the configuration of the cluster and [cloud-init](https://cloudinit.readthedocs.io/en/latest/) to automate the initial installation of the Raspberry Pis.

## What I have built till now

From hardware perspective I built two different versions of the cluster

- Release 1.0: Basic version using dedicated Flash SSD disks for each node and centrazalized SAN as additional storage

![Cluster-1.0](/assets/img/pi-cluster.png)

- Release 2.0: Adding dedicated SSD disk to each node of the cluster and improving a lot the overall cluster performance

![!Cluster-2.0](/assets/img/pi-cluster-2.0.png)

## Software used and latest version tested

The software used and the latest version tested of each component

| Type | Software | Latest Version tested | Notes |
|-----------| ------- |-------|----|
| OS | Ubuntu | 20.04.3 | OS need to be tweaked for Raspberry PI when booting from external USB  |
| Control | Ansible | 2.12.1  | |
| Control | cloud-init | 21.4 | version pre-integrated into Ubuntu 20.04 |
| Kubernetes | K3S | | K3S version| 
| Networking | Flannel | | version pre-integrated into K3S |
| Networking | CoreDNS | | version pre-integrated into K3S |
| Networking | Metal LB |  | Helm chart version: |
| Service Proxy | Traefik | | version pre-integrated into K3S |
| Storage | Longhorn | | Helm chart version: |
| SSL Certificates | Certmanager | | Helm chart version: |
| Logging | ECK Operator | | Helm chart version: |
| Logging | Elastic Search | | Deployed with ECK Operator |
| Logging | Kibana | | Deployed with ECK Operator |
| Logging | Fluentbit | | Helm chart version: |
| Monitoring | Kube Stack Operator | | Helm chart version: |
| Backup | Minio | | |
| Backup | Restic | | |
| Backup | Velero | | Helm chart version: |
{: .table }
