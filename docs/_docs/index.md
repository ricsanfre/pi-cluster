---
title: Welcome to Rasperry Pi Cluster Project
permalink: /docs/home/
redirect_from: /docs/index.html
---


<p align="left">
  <img src="/assets/img/pi-cluster.png" alt="pi-cluster-1.0"/>
  <img src="/assets/img/pi-cluster-2.0.png" />
</p>

## Scope
The scope of this project is to create a kubernetes cluster at home using Raspberry Pis and Ansible to automate the deployment and configuration.

This is an educational project to explore kubernetes cluster configurations using an ARM architecture and its automation using Ansible. 
As part of the project the goal is to deploy on the Kuberenets cluster basic services such as distributed block storage for persistent volumes (Rook/Ceph or `LongHorn`), centralized monitoring tools like `Prometheus` and `EFK` (Elasticsearch-Fluentd-Kibana) and backup/restore solution like `Velero` and `Restic`.

<p align="center">
  <img src="/assets/img/pi-cluster-icons.png"/>
</p>

## Design Principles

- Use ARM 64 bits operating system enabling the possibility of using Raspberry PI B nodes with 8GB RAM. Currently only Ubuntu supports 64 bits ARM distribution for Raspberry Pi.
- Use ligthweigh Kubernetes distribution (K3S). Kuberentes distribution with a smaller memory footprint which is ideal for running on Raspberry PIs
- Use of distributed storage block technology, instead of centralized NFS system, for pod persistent storage.  Kubernetes block distributed storage solutions, like Rook/Ceph or Longhorn, in their latest versions have included ARM 64 bits support.
- Use of Ansible for automating the configuration of the cluster.
