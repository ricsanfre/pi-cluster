---
title: Welcome to Rasperry Pi Cluster Project
permalink: /docs/home/
redirect_from: /docs/index.html
---


## Scope
The scope of this project is to create a kubernetes cluster at home using **Raspberry Pis** and **Ansible** to automate the deployment and configuration.

This is an educational project to explore kubernetes cluster configurations using an ARM architecture and its automation using Ansible.

As part of the project the goal is to use a lightweight Kubernetes flavor based on [K3S](https://ks3.io/) and deploy cluster basic services such as: 1) distributed block storage for POD's persistent volumes like [LongHorn](https://longhorn.io/), 2) centralized monitoring tool like [Prometheus](https://prometheus.io/) 3) centralized log managemeent like EFK stack ([Elasticsearch](https://www.elastic.co/elasticsearch/)-[Fluentbit](https://fluentbit.io/)-[Kibana](https://www.elastic.co/kibana/) and 3) backup/restore solution for the cluster like [Velero](https://velero.io/) and [Restic](https://restic.net/).


The following picture shows the set of opensource solutions used for building this cluster:

![Cluster-Icons](/assets/img/pi-cluster-icons.png)


## Design Principles

- Use ARM 64 bits operating system enabling the possibility of using Raspberry PI B nodes with 8GB RAM. Currently only Ubuntu supports 64 bits ARM distribution for Raspberry Pi.
- Use ligthweigh Kubernetes distribution (K3S). Kuberentes distribution with a smaller memory footprint which is ideal for running on Raspberry PIs
- Use of distributed storage block technology, instead of centralized NFS system, for pod persistent storage.  Kubernetes block distributed storage solutions, like Rook/Ceph or Longhorn, in their latest versions have included ARM 64 bits support.
- Use of opensource projects under the [CNCF: Cloud Native Computing Foundation](https://www.cncf.io/) umbrella
- Use latest versions of each opensource project to be able to test the latest Kubernetes capabilities.
- Use of [Ansible](https://docs.ansible.com/) for automating the configuration of the cluster and [cloud-init](https://cloudinit.readthedocs.io/en/latest/) to automate the initial installation of the Raspberry Pis.

## What I have built so far

From hardware perspective I built two different versions of the cluster

- Release 1.0: Basic version using dedicated USB flash drive for each node and centrazalized SAN as additional storage

![Cluster-1.0](/assets/img/pi-cluster.png)

- Release 2.0: Adding dedicated SSD disk to each node of the cluster and improving a lot the overall cluster performance

![!Cluster-2.0](/assets/img/pi-cluster-2.0.png)



## What I have developed so far

From software perspective I have develop the following: Ansible playbooks and roles

1. `cloud-init` config files and Ansible playbooks/roles for automatizing the installation and deployment of Pi-Cluster. 


   All source code can be found in the following github repository

   | Repo | Description | Github |
   | ---| --- | --- | 
   |  pi-cluster | PI Cluster Ansible  | [{{site.data.icons.github}}]({{site.git_address}})|
   {: .table } 
   

2. Aditionally several ansible roles have been developed to automate different configuration tasks on Ubuntu-based servers that can be reused in other projects. These roles are used by Pi-Cluster Ansible Playbooks

   Each ansible role source code can be found in its dedicated Github repository and is published in Ansible-Galaxy to facilitate its installation with `ansible-galaxy` command.

   | Ansible role | Description | Github |
   | ---| --- | --- | 
   |  [ricsanfre.security](https://galaxy.ansible.com/ricsanfre/security) | Automate SSH hardening configuration tasks  | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-security)|
   | [ricsanfre.ntp](https://galaxy.ansible.com/ricsanfre/ntp)  | Chrony NTP service configuration | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-ntp) |
   | [ricsanfre.firewall](https://galaxy.ansible.com/ricsanfre/firewall) | NFtables firewall configuration | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-firewall) |
   | [ricsanfre.dnsmasq](https://galaxy.ansible.com/ricsanfre/dnsmasq) | Dnsmasq configuration | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-dnsmasq) |
   | [ricsanfre.storage](https://galaxy.ansible.com/ricsanfre/storage)| Configure LVM | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-storage) |
   | [ricsanfre.iscsi_target](https://galaxy.ansible.com/ricsanfre/iscsi_target)| Configure iSCSI Target| [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-iscsi_target) |
   | [ricsanfre.iscsi_initiator](https://galaxy.ansible.com/ricsanfre/iscsi_initiator)| Configure iSCSI Initiator | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-iscsi_initiator) |
   | [ricsanfre.k8s_cli](https://galaxy.ansible.com/ricsanfre/k8s_cli)| Install kubectl and Helm utilities | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-k8s_cli) |
   | [ricsanfre.fluentbit](https://galaxy.ansible.com/ricsanfre/fluentbit)| Configure fluentbit | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-fluentbit) |
   | [ricsanfre.minio](https://galaxy.ansible.com/ricsanfre/minio)| Configure Minio S3 server | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-minio) |
   | [ricsanfre.backup](https://galaxy.ansible.com/ricsanfre/backup)| Configure Restic | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-backup) |
   {: .table } 


3. This documentation website [picluster.ricsanfre.com](https://picluster.ricsanfre.com), hosted in Github pages.

   Static website generated with [Jekyll](https://jekyllrb.com/).

   Source code can be found in the Pi-cluster repository under [`docs` directory]({{site.git_address}}/tree/master/docs)


## Software used and latest version tested

The software used and the latest version tested of each component

| Type | Software | Latest Version tested | Notes |
|-----------| ------- |-------|----|
| OS | Ubuntu | 20.04.3 | OS need to be tweaked for Raspberry PI when booting from external USB  |
| Control | Ansible | 2.12.1  | |
| Control | cloud-init | 21.4 | version pre-integrated into Ubuntu 20.04 |
| Kubernetes | K3S | v1.22.5 | K3S version| 
| Kubernetes | Helm | v3.6.3 ||
| Computing | containerd | v1.5.8-k3s1 | version pre-integrated into K3S |
| Networking | Flannel | v0.15.1 | version pre-integrated into K3S |
| Networking | CoreDNS | v1.8.4 | version pre-integrated into K3S |
| Networking | Metal LB | v0.11.0 | Helm chart version:  metallb-0.11.0 |
| Service Proxy | Traefik | traefik-10.3.001 | Helm chart: traefik-10.3.001 version pre-integrated into K3S |
| Storage | Longhorn | v1.2.3 | Helm chart version: longhorn-1.2.3 |
| SSL Certificates | Certmanager | v1.6.1 | Helm chart version: cert-manager-v1.6.1  |
| Logging | ECK Operator |  1.9.1 | Helm chart version: eck-operator-1.9.1 |
| Logging | Elastic Search | 7.15 | Deployed with ECK Operator |
| Logging | Kibana | 7.15 | Deployed with ECK Operator |
| Logging | Fluentbit | 1.8.11 | Helm chart version: fluent-bit-0.19.16 |
| Monitoring | Kube Prometheus Stack | 0.53.1 | Helm chart version: kube-prometheus-stack-28.0.1 |
| Backup | Minio | 2021-12-29T06:49:06Z | |
| Backup | Restic | 0.12.1 | |
| Backup | Velero |1.7.1 | Helm chart version: velero-2.27.2 |
{: .table }
