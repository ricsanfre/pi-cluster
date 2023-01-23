---
title: What is this project about?
permalink: /docs/home/
redirect_from: /docs/index.html
description: The scope of this project is to create a kubernetes cluster at home using Raspberry Pis and to automate its deployment and configuration applying IaC (infrastructure as a code) and GitOps methodologies with tools like Ansible and ArgoCD. How to automatically deploy K3s baesed kubernetes cluster, Longhorn as distributed block storage for PODs' persistent volumes, Prometheus as monitoring solution, EFK+Loki stack as centralized log management solution, Velero and Restic as backup solution and Linkerd as service mesh architecture.
last_modified_at: "17-01-2023"
---


## Scope
The scope of this project is to create a kubernetes cluster at home using **Raspberry Pis** and to automate its deployment and configuration applying **IaC (infrastructure as a code)** and **GitOps** methodologies with tools like [Ansible](https://docs.ansible.com/), [cloud-init](https://cloudinit.readthedocs.io/en/latest/) and [Argo CD](https://argo-cd.readthedocs.io/en/stable/).

As part of the project, the goal is to use a lightweight Kubernetes flavor based on [K3S](https://k3s.io/) and deploy cluster basic services such as: 1) distributed block storage for POD's persistent volumes, [LongHorn](https://longhorn.io/), 2) backup/restore solution for the cluster, [Velero](https://velero.io/) and [Restic](https://restic.net/), 3) service mesh architecture, [Linkerd](https://linkerd.io/), and 4) observability platform based on metrics monitoring solution, [Prometheus](https://prometheus.io/), logging and analytics solution, EFḰ+LG stack ([Elasticsearch](https://www.elastic.co/elasticsearch/)-[Fluentd](https://www.fluentd.org/)/[Fluentbit](https://fluentbit.io/)-[Kibana](https://www.elastic.co/kibana/) + [Loki](https://grafana.com/oss/loki/)-[Grafana](https://grafana.com/oss/grafana/)), and distributed tracing solution, [Tempo](https://grafana.com/oss/tempo/).


The following picture shows the set of opensource solutions used for building this cluster:

![Cluster-Icons](/assets/img/pi-cluster-icons.png)

| Logo | Name | Description |
| ---| --- | --- |
| <img width="32" src="https://simpleicons.org/icons/ansible.svg"> | [Ansible](https://docs.ansible.com/) | Automate OS configuration, external services installation and k3s installation and bootstrapping |
| <img width="32" src="https://cncf-branding.netlify.app/img/projects/argo/icon/color/argo-icon-color.svg"> | [ArgoCD](https://argo-cd.readthedocs.io/en/stable/) | GitOps tool built to deploy applications to Kubernetes |
| <img width="32" src="https://cloudinit.readthedocs.io/en/latest/_static/logo.png"> | [Cloud-init](https://cloudinit.readthedocs.io/en/latest/) | Automate installation OS |
| <img width="32" src="https://assets.ubuntu.com/v1/ce518a18-CoF-2022_solid+O.svg"> | [Ubuntu](https://ubuntu.com/) | OS for cluster nodes |
| <img width="32" src="https://cncf-branding.netlify.app/img/projects/k3s/icon/color/k3s-icon-color.svg"> | [K3S](https://k3s.io/) | Lightweight distribution of Kubernetes |
{: .table }


## Design Principles

- Use ARM 64 bits operating system enabling the possibility of using Raspberry PI B nodes with 8GB RAM. Currently only Ubuntu supports 64 bits ARM distribution for Raspberry Pi.
- Use ligthweigh Kubernetes distribution (K3S). Kuberentes distribution with a smaller memory footprint which is ideal for running on Raspberry PIs
- Use of distributed storage block technology, instead of centralized NFS system, for pod persistent storage.  Kubernetes block distributed storage solutions, like Rook/Ceph or Longhorn, in their latest versions have included ARM 64 bits support.
- Use of opensource projects under the [CNCF: Cloud Native Computing Foundation](https://www.cncf.io/) umbrella
- Use latest versions of each opensource project to be able to test the latest Kubernetes capabilities.
- Use of [cloud-init](https://cloudinit.readthedocs.io/en/latest/) to automate the initial OS installation.
- Use of [Ansible](https://docs.ansible.com/) for automating the configuration of the cluster nodes, installation of kubernetes and external services, and triggering cluster bootstrap (ArgoCD bootstrap).
- Use of [Argo CD](https://argo-cd.readthedocs.io/en/stable/) to automatically provision Kubernetes applications from git repository.

## What I have built so far

From hardware perspective I built two different versions of the cluster

- Release 1.0: Basic version using dedicated USB flash drive for each node and centrazalized SAN as additional storage

![Cluster-1.0](/assets/img/pi-cluster.png)

- Release 2.0: Adding dedicated SSD disk to each node of the cluster and improving a lot the overall cluster performance

![!Cluster-2.0](/assets/img/pi-cluster-2.0.png)


## What I have developed so far

From software perspective I have develop, cloud-init templates, Ansible code and packaged Kubernetes applications to be deployed with ArgoCD.

All source code can be found in the following github repository

   | Repo | Description | Github |
   | ---| --- | --- | 
   |  pi-cluster | PI Cluster Ansible  | [{{site.data.icons.github}}]({{site.git_address}})|
   {: .table }

1. **Cloud-init** template files for initial OS installation

   Source code can be found in Pi Cluster Git repository under [`/cloud-init`]({{site.git_address}}/tree/master/cloud-init) directory.


2. **Ansible** playbook and roles for configuring cluster nodes and installating and bootstraping K3S cluster  
   
   Source code can be found in Pi Cluster Git repository under [`/ansible`]({{site.git_address}}/tree/master/ansible) directory.

   Aditionally several ansible roles have been developed to automate different configuration tasks on Ubuntu-based servers that can be reused in other projects. These roles are used by Pi-Cluster Ansible Playbooks

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
   | [ricsanfre.vault](https://galaxy.ansible.com/ricsanfre/vault)| Configure Hashicorp Vault | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-vault) |
   {: .table } 

3. **Packaged Kuberentes applications** (Helm, Kustomize, manifest files) to be deployed using ArgoCD

   Source code can be found in Pi Cluster Git repository under [`/argocd`]({{site.git_address}}/tree/master/argocd) directory.

4. This **documentation website** [picluster.ricsanfre.com](https://picluster.ricsanfre.com), hosted in Github pages.

   Static website generated with [Jekyll](https://jekyllrb.com/).

   Source code can be found in the Pi-cluster repository under [`/docs`]({{site.git_address}}/tree/master/docs) directory.


## Software used and latest version tested

The software used and the latest version tested of each component

| Type | Software | Latest Version tested | Notes |
|-----------| ------- |-------|----|
| OS | Ubuntu | 20.04.3 | OS need to be tweaked for Raspberry PI when booting from external USB  |
| Control | Ansible | 2.12.1  | |
| Control | cloud-init | 21.4 | version pre-integrated into Ubuntu 20.04 |
| Kubernetes | K3S | v1.24.7 | K3S version|
| Kubernetes | Helm | v3.6.3 ||
| Metrics | Kubernetes Metrics Server | v0.6.1 | version pre-integrated into K3S |
| Computing | containerd | v1.6.8-k3s1 | version pre-integrated into K3S |
| Networking | Flannel | v0.19.2 | version pre-integrated into K3S |
| Networking | CoreDNS | v1.9.1 | version pre-integrated into K3S |
| Networking | Metal LB | v0.13.7 | Helm chart version:  0.13.7 |
| Service Mesh | Linkerd | v2.12.2 | Helm chart version: linkerd-control-plane-1.9.4 |
| Service Proxy | Traefik | v2.9.1 | Helm chart version: 18.1.0  |
| Storage | Longhorn | v1.3.2 | Helm chart version: 1.3.2 |
| TLS Certificates | Certmanager | v1.10.0 | Helm chart version: v1.10.0  |
| Logging | ECK Operator |  2.4.0 | Helm chart version: 2.4.0 |
| Logging | Elastic Search | 8.1.2 | Deployed with ECK Operator |
| Logging | Kibana | 8.1.2 | Deployed with ECK Operator |
| Logging | Fluentbit | 2.0.4 | Helm chart version: 0.21.0 |
| Logging | Fluentd | 1.15.2 | Helm chart version: 0.3.9. [Custom docker image](https://github.com/ricsanfre/fluentd-aggregator) from official v1.15.2|
| Logging | Loki | 2.6.1 | Helm chart grafana/loki version: 3.3.0 |
| Monitoring | Kube Prometheus Stack | 0.61.1 | Helm chart version: 43.3.1 |
| Monitoring | Prometheus Operator | 0.61.1 | Installed by Kube Prometheus Stack. Helm chart version: 43.3.1   |
| Monitoring | Prometheus | 2.40.5 | Installed by Kube Prometheus Stack. Helm chart version: 43.3.1 |
| Monitoring | AlertManager | 0.25.0 | Installed by Kube Prometheus Stack. Helm chart version: 43.3.1 |
| Monitoring | Grafana | 9.3.1 | Helm chart version grafana-6.48.2. Installed as dependency of Kube Prometheus Stack chart. Helm chart version: 43.3.1 |
| Monitoring | Prometheus Node Exporter | 1.5.0 | Helm chart version: prometheus-node-exporter-4.8.2. Installed as dependency of Kube Prometheus Stack chart. Helm chart version: 43.3.1 |
| Monitoring | Prometheus Elasticsearch Exporter | 1.5.0 | Helm chart version: prometheus-elasticsearch-exporter-4.15.1 |
| Backup | Minio | RELEASE.2022-09-22T18-57-27Z | |
| Backup | Restic | 0.12.1 | |
| Backup | Velero | 1.9.3 | Helm chart version: 2.32.1 |
| Secrets | Hashicorp Vault | 1.12.2 | |
| Secrets| External Secret Operator | 0.7.1 | Helm chart version: 0.7.1 |
| GitOps | Argo CD | v2.5.6 | Helm chart version: 5.17.1 |
{: .table }
