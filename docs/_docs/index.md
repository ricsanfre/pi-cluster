---
title: What is this project about?
permalink: /docs/home/
description: The scope of this project is to create a kubernetes cluster at home using Raspberry Pis and low cost mini PCs, and to automate its deployment and configuration applying IaC (infrastructure as a code) and GitOps methodologies with tools like Ansible and FluxCD. How to automatically deploy K3s baesed kubernetes cluster, Longhorn as distributed block storage for PODs' persistent volumes, Prometheus as monitoring solution, EFK+Loki stack as centralized log management solution, Velero and Restic as backup solution and Istio as service mesh architecture.
last_modified_at: "07-12-2024"
---


## Scope

The main goal of  this project is to create a kubernetes cluster at home using ARM/x86 bare metal nodes (**Raspberry Pis** and low cost refurbished **mini PCs**) and to automate its deployment and configuration applying **IaC (infrastructure as a code)** and **GitOps** methodologies with tools like [Ansible](https://docs.ansible.com/), [cloud-init](https://cloudinit.readthedocs.io/en/latest/) and [Flux CD](https://fluxcd.io/).

The project scope includes the automatic installation and configuration of a lightweight Kubernetes flavor based on [K3S](https://k3s.io/), and deployment of cluster basic services such as:
- Distributed block storage for POD's persistent volumes, [LongHorn](https://longhorn.io/).
- S3 Object storage, [Minio](https://min.io/).
- Backup/restore solution for the cluster, [Velero](https://velero.io/) and [Restic](https://restic.net/). 
- Certificate management, [Cert-Manager](https://cert-manager.io).
- Secrets Management solution with [Vault](https://www.vaultproject.io/) and [External Secrets](https://external-secrets.io/)
- Identity Access Management(IAM) providing Single-sign On, [Keycloak](https://www.keycloak.org/)
- Observability platform based on:
   - Metrics monitoring solution, [Prometheus](https://prometheus.io/)
   - Logging and analytics solution, combined EFK+LG stacks ([Elasticsearch](https://www.elastic.co/elasticsearch/)-[Fluentd](https://www.fluentd.org/)/[Fluentbit](https://fluentbit.io/)-[Kibana](https://www.elastic.co/kibana/) + [Loki](https://grafana.com/oss/loki/)-[Grafana](https://grafana.com/oss/grafana/))
   - Distributed tracing solution, [Tempo](https://grafana.com/oss/tempo/).

Also deployment of services for building a cloud-native microservices architecture are include as part of the scope:

- Service mesh architecture, [Istio](https://istio.io/)
- API security with Oauth2.0 and OpenId Connect, using IAM solution, [Keycloak](https://www.keycloak.org/)
- Streaming platform, [Kafka](https://kafka.apache.org/)

## Design Principles

- Use hybrid x86/ARM bare metal nodes, combining in the same cluster Raspberry PI nodes (ARM) and x86 mini PCs (HP Elitedesk 800 G3).
- Use lightweight Kubernetes distribution (K3S). Kubernetes distribution with a smaller memory footprint which is ideal for running on Raspberry PIs
- Use distributed storage block technology, instead of centralized NFS system, for pod persistent storage.  Kubernetes block distributed storage solutions, like Rook/Ceph or Longhorn, in their latest versions have included ARM 64 bits support.
- Use opensource projects under the [CNCF: Cloud Native Computing Foundation](https://www.cncf.io/) umbrella
- Use latest versions of each opensource project to be able to test the latest Kubernetes capabilities.
- Automate deployment of cluster using IaC (infrastructure as a code) and GitOps methodologies with tools like:
  - [cloud-init](https://cloudinit.readthedocs.io/en/latest/) to automate the initial OS installation of the cluster nodes.
  - [Ansible](https://docs.ansible.com/) for automating the configuration of the cluster nodes, installation of kubernetes and external services, and triggering cluster bootstrap (FluxCD bootstrap).
  - [Flux CD](https://fluxcd.io/) to automatically provision Kubernetes applications from git repository.


## Technology Stack

The following picture shows the set of opensource solutions used for building this cluster:

![cluster-tech-stack](/assets/img/pi-cluster-tech-stack.png)


|                      | Name         | Description                                                                                                             |
| -------------------- | ------------ |:----------------------------------------------------------------------------------------------------------------------- |
| ![ansible-icon](/assets/img/logos/ansible.svg){:width="32"}      | [Ansible](https://www.ansible.com) | Automate OS configuration, external services installation and k3s installation and bootstrapping |
| ![fluxcd-icon](/assets/img/logos/flux-cd.png){:width="32"}       | [FluxCD](https://fluxcd.io/) | GitOps tool for deploying applications to Kubernetes |
| ![cloudinit-icon](/assets/img/logos/cloud-init.svg){:width="32"} | [Cloud-init](https://cloudinit.readthedocs.io/en/latest/) | Automate OS initial installation |
| ![ubuntu-icon](/assets/img/logos/ubuntu.svg){:width="32"}        | [Ubuntu](https://ubuntu.com/)                    | Cluster nodes  OS                          |
| ![openwrt-icon](/assets/img/logos/openwrt-icon.png){:width="32"} | [OpenWrt](https://openwrt.org/)                   | Router/Firewall OS                        |
| ![K3s-icon](/assets/img/logos/k3s.svg){:width="32"}              | [K3S](https://k3s.io/)                       | Lightweight distribution of Kubernetes         |
| ![containerd-icon](/assets/img/logos/containerd.svg){:width="32"}| [Containerd](https://containerd.io/)         | Container runtime integrated with K3S          |
| ![cilium-icon](/assets/img/logos/cilium.svg){:width="32"}        | [Cilium CNI](https://cilium.io)              | Kubernetes Networking (CNI) and Load Balancer  |
| ![coredns-icon](/assets/img/logos/coredns.svg){:width="32"}      | [CoreDNS](https://coredns.io/)               | Kubernetes DNS                                 |
| ![external-dns-icon](/assets/img/logos/external-dns.png){:width="32"} | [External-DNS](https://kubernetes-sigs.github.io/external-dns/) | External DNS synchronization   |
| ![haproxy-icon](/assets/img/logos/haproxy.svg){:width="32"} | [HAProxy](https://www.haproxy.org/)   | Kubernetes API Load-balancer                                       |
| ![nginx-icon](/assets/img/logos/nginx.svg){:width="32"}     | [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)  | Kubernetes Ingress Controller   |
| ![longhorn-icon](/assets/img/logos/longhorn.svg){:width="32"} | [Longhorn](https://longhorn.io/)    | Kubernetes distributed block storage |
| ![minio-icon](/assets/img/logos/minio.svg){:width="20"}     | [Minio](https://min.io/)              | S3 Object Storage solutio            |
| ![cert-manager-icon](/assets/img/logos/cert-manager.svg){:width="32"} | [Cert-Manager](https://cert-manager.io) | TLS Certificates management  |
| ![vault-icon](/assets/img/logos/vault.svg){:width="32"} | [Hashicorp Vault](https://www.vaultproject.io/) | Secrets Management solution |
| ![external-secrets-icon](/assets/img/logos/external-secrets.svg){:width="32"} | [External Secrets Operator](https://external-secrets.io/) | Sync Kubernetes Secrets from Hashicorp |
| ![keycloak-icon](/assets/img/logos/keycloak.svg){:width="32"}         | [Keycloak](https://www.keycloak.org/)   | Identity Access Managemen     |
| ![OAuth2-proxy-icon](/assets/img/logos/OAuth2-proxy.svg){:width="32"}     | [OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/)  | OAuth2.0 Proxy |
| ![velero-icon](/assets/img/logos/velero.svg){:width="32"}           | [Velero](https://velero.io/)        | Kubernetes Backup and Restore solution   |
| ![restic-icon](/assets/img/logos/restic.png){:width="32"}           | [Restic](https://restic.net/)       | OS Backup and Restore solution           |
| ![prometheus-icon](/assets/img/logos/prometheus.svg){:width="32"}   | [Prometheus](https://prometheus.io/)  | Metrics monitoring and alerting        |
| ![fluentd-icon](/assets/img/logos/fluentd.svg){:width="32"}         | [Fluentd](https://www.fluentd.org/)   | Logs forwarding and distribution       |
| ![fluentbit-icon](/assets/img/logos/fluentbit.svg){:width="32"}     | [Fluent-bit](https://fluentbit.io/)   | Logs collection                        |
| ![loki-icon](/assets/img/logos/loki.png){:width="32"}             | [Grafana Loki](https://grafana.com/oss/loki/)    | Logs aggregation              |
| ![elastic-icon](/assets/img/logos/elastic.svg){:width="32"}       | [ElasticSearch](https://www.elastic.co/elasticsearch/)      | Log analytics      |
| ![kibana-icon](/assets/img/logos/kibana.svg){:width="32"}           | [Kibana](https://www.elastic.co/kibana/)      | Logs analytics Dashboards      |
| ![tempo-icon](/assets/img/logos/tempo.svg){:width="32"}            | [Grafana Tempo](https://grafana.com/oss/tempo/)     | Distributed tracing monitoring   |
| ![grafana-icon](/assets/img/logos/grafana.svg){:width="32"}          | [Grafana](https://grafana.com/oss/grafana/)    | Monitoring Dashboards        |
| ![istio-icon](/assets/img/logos/istio-icon-color.svg){:width="32"} | [Istio](https://istio.io/)    | Kubernetes Service Mesh     |
| ![kafka-icon](/assets/img/logos/apache_kafka.svg){:width="32"}   | [Kafka Strimzi Operator](https://strimzi.io/)   | Kubermetes Operator for running Kafka, Event Streaming and distribution  |
| ![cloudnative-pg-icon](/assets/img/logos/cloudnative-pg.png){:width="32"}  | [CloudNative-PG](https://cloudnative-pg.io/)  | Kubernetes Operator for running PosgreSQL  |
| ![mongodb-icon](/assets/img/logos/mongodb.svg){:width="32"}         | [MongoDB Operator](https://github.com/mongodb/mongodb-kubernetes-operator)     | [[Kubernetes Operator]] for running MongoDB |
{: .table .border-dark }


## Deprecated Technology

The following technologies have been used in previous releases of PiCluster but they have been deprecated and not longer maintained


|                      | Name         | Description                                                                                                             |
| -------------------- | ------------ |:----------------------------------------------------------------------------------------------------------------------- |
| ![metallb-icon](/assets/img/logos/metallb.svg){:width="32"} | [Metal-LB](https://metallb.universe.tf) | Load-balancer implementation for bare metal Kubernetes clusters. Replaced by Cilium CNI load balancing capabilities |
| ![traefik-icon](/assets/img/logos/traefik.svg){:width="32"} | [Traefik](https://traefik.io/traefik/)  | Kubernetes Ingress Controller. Replaced by NGINX Ingress Controller  |
| ![argocd-icon](/assets/img/logos/argocd.svg){:width="32"}  | [ArgoCD](https://argo-cd.readthedocs.io/en/stable/)  | GitOps tool. Replaced by FluxCD |
| ![flannel-icon](/assets/img/logos/flannel.svg){:width="20"}  | [Flannel](https://github.com/flannel-io/flannel/) | Kubernetes CNI plugin. Embedded into K3s. Replaced by Cilium CNI |
{: .table .border-dark }




## External Resources and Services

Even whe the premise is to deploy all services in the kubernetes cluster, there is still a need for a few external services/resources. Below is a list of external resources/services and why we need them.

### Cloud external services

{{site.data.alerts.note}}
 These resources are optional, the homelab still works without them but it won't have trusted certificates.
{{site.data.alerts.end}}

|  |Provider | Resource | Purpose |
| --- | --- | --- | --- |
| ![letsencrypt-icon](/assets/img/logos/letsencrypt.svg){:width="60"}| [Letsencrypt](https://letsencrypt.org/) | TLS CA Authority | Signed valid TLS certificates |
| ![ionos-icon](/assets/img/logos/ionos.png){:width="60"} |[IONOS](https://www.ionos.es/) | DNS | DNS and [DNS-01 challenge](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge) for certificates |
{: .table .border-dark }

**Alternatives:**

1. Use a private PKI (custom CA to sign certificates).

   Currently supported. Only minor changes are required. See details in [Doc: Quick Start instructions](/docs/ansible/).

2. Use other DNS provider.

   Cert-manager / Certbot used to automatically obtain certificates from Let's Encrypt can be used with other DNS providers. This will need further modifications in the way cert-manager application is deployed (new providers and/or webhooks/plugins might be required).

   Currently only acme issuer (letsencytp) using IONOS as dns-01 challenge provider is configured. Check list of [supported dns01 providers](https://cert-manager.io/docs/configuration/acme/dns01/#supported-dns01-providers).

### Self-hosted external services 

There is another list of services that I have decided to run outside the kubernetes cluster selfhosting them.

|  |External Service | Resource | Purpose |
| --- | --- | --- | --- |
| ![minio-icon](/assets/img/logos/minio.svg){:width="20"} |[Minio](https://min.io) | S3 Object Store | Cluster Backup  |
| ![vault-icon](/assets/img/logos/vault.svg){:width="32"} |[Hashicorp Vault](https://www.vaultproject.io/) | Secrets Management | Cluster secrets management |
{: .table .border-dark .align-middle }


Minio backup servive is hosted in a VM running in Public Cloud, using [Oracle Cloud Infrastructure (OCI) free tier](https://www.oracle.com/es/cloud/free/).

Vault service is running in one of the cluster nodes, `node1`, since Vault kubernetes authentication method need access to Kuberentes API, I won't host Vault service in Public Cloud.


## What I have built so far

From hardware perspective I built two different versions of the cluster

- Cluster 1.0: Basic version using dedicated USB flash drive for each node and centrazalized SAN as additional storage

![Cluster-1.0](/assets/img/pi-cluster.png)

- Cluster 2.0: Adding dedicated SSD disk to each node of the cluster and improving a lot the overall cluster performance

![!Cluster-2.0](/assets/img/pi-cluster-2.0.png)

- Cluster 3.0: Creating hybrid ARM/x86 kubernetes cluster, combining Raspberry PI nodes with x86 mini PCs

![!Cluster-3.0](/assets/img/pi-cluster-3.0.png)


## What I have developed so far

{{site.data.alerts.important}}
All source code can be found in the project's github repository [{{site.data.icons.github}}]({{site.git_address}}).

{{site.data.alerts.end}}


From software perspective, I have developed the following:

1. **Cloud-init** template files for initial OS installation in Raspberry PI nodes

   Source code can be found in Pi Cluster Git repository under [`metal/rpi/cloud-init`]({{site.git_address}}/tree/master/metal/rpi/cloud-init) directory.

2. Automate initial OS installation in x86_64 nodes using PXE server and Ubuntu's **auto-install** template files.

3. **Ansible** playbook and roles for configuring cluster nodes and installating and bootstraping K3S cluster  
   
   Source code can be found in Pi Cluster Git repository under [`/ansible`]({{site.git_address}}/tree/master/ansible) directory.

   Aditionally several ansible roles have been developed to automate different configuration tasks on Ubuntu-based servers that can be reused in other projects. These roles are used by Pi-Cluster Ansible Playbooks

   Each ansible role source code can be found in its dedicated Github repository and is published in Ansible-Galaxy to facilitate its installation with `ansible-galaxy` command.

   | Ansible role | Description | Github |
   | ---| --- | --- | 
   |  [ricsanfre.security](https://galaxy.ansible.com/ricsanfre/security) | Automate SSH hardening configuration tasks  | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-security)|
   | [ricsanfre.ntp](https://galaxy.ansible.com/ricsanfre/ntp)  | Chrony NTP service configuration | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-ntp) |
   | [ricsanfre.firewall](https://galaxy.ansible.com/ricsanfre/firewall) | NFtables firewall configuration | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-firewall) |
   | [ricsanfre.dnsmasq](https://galaxy.ansible.com/ricsanfre/dnsmasq) | Dnsmasq configuration | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-dnsmasq) |
   | [ricsanfre.bind9](https://galaxy.ansible.com/ricsanfre/bind9) | Bind9 configuration | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-bind9) |
   | [ricsanfre.storage](https://galaxy.ansible.com/ricsanfre/storage)| Configure LVM | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-storage) |
   | [ricsanfre.iscsi_target](https://galaxy.ansible.com/ricsanfre/iscsi_target)| Configure iSCSI Target| [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-iscsi_target) |
   | [ricsanfre.iscsi_initiator](https://galaxy.ansible.com/ricsanfre/iscsi_initiator)| Configure iSCSI Initiator | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-iscsi_initiator) |
   | [ricsanfre.k8s_cli](https://galaxy.ansible.com/ricsanfre/k8s_cli)| Install kubectl and Helm utilities | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-k8s_cli) |
   | [ricsanfre.fluentbit](https://galaxy.ansible.com/ricsanfre/fluentbit)| Configure fluentbit | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-fluentbit) |
   | [ricsanfre.minio](https://galaxy.ansible.com/ricsanfre/minio)| Configure Minio S3 server | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-minio) |
   | [ricsanfre.backup](https://galaxy.ansible.com/ricsanfre/backup)| Configure Restic | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-backup) |
   | [ricsanfre.vault](https://galaxy.ansible.com/ricsanfre/vault)| Configure Hashicorp Vault | [{{site.data.icons.github}}](https://github.com/ricsanfre/ansible-role-vault) |
   {: .table .border-dark } 

4. **Packaged Kuberentes applications** (Helm, Kustomize, manifest files) to be deployed using FluxCD

   Source code can be found in Pi Cluster Git repository under [`/kubernetes`]({{site.git_address}}/tree/master/kubernetes) directory.

5. This **documentation website**, *picluster.ricsanfre.com*, hosted in Github pages.

   Static website generated with [Jekyll](https://jekyllrb.com/).

   Source code can be found in the Pi-cluster repository under [`/docs`]({{site.git_address}}/tree/master/docs) directory.


## Software used and latest version tested

The software used and the latest version tested of each component

| Type | Software | Latest Version tested | Notes |
|-----------| ------- |-------|----|
| OS | Ubuntu | 24.04.3 | |
| Control | Ansible | 2.18.6  | |
| Control | cloud-init | 23.1.2 | version pre-integrated into Ubuntu 22.04.2 |
| Kubernetes | K3S | v1.34.1 | K3S version|
| Kubernetes | Helm | v3.17.3 ||
| Kubernetes | etcd | v3.6.4-k3s3 | version pre-integrated into K3S |
| Computing | containerd | v2.1.4-k3s2 | version pre-integrated into K3S |
| Networking | Cilium | 1.18.3 | |
| Networking | CoreDNS | v1.12.3 | Helm chart version: 1.44.3 |
| Networking | External-DNS | 0.19.0 | Helm chart version: 1.19.0 |
| Metric Server | Kubernetes Metrics Server | v0.8.0 | Helm chart version: 3.13.0|
| Service Mesh | Istio | v1.27.2 | Helm chart version: 1.27.2 |
| Service Proxy | Ingress NGINX | v1.13.3 | Helm chart version: 4.13.3 |
| Storage | Longhorn | v1.10.0 | Helm chart version: 1.10.0 |
| Storage | Minio | RELEASE.2024-12-18T13-15-44Z | Helm chart version: 5.4.0 |
| TLS Certificates | Certmanager | v1.19.1 | Helm chart version: v1.19.1  |
| Logging | ECK Operator |  3.1.0 | Helm chart version: 3.1.0 |
| Logging | Elastic Search | 8.19.6 | Deployed with ECK Operator |
| Logging | Kibana | 8.19.6 | Deployed with ECK Operator |
| Logging | Fluentbit | 4.1.0 | Helm chart version: 0.54.0 |
| Logging | Fluentd | 1.17.1 | Helm chart version: 0.5.3 [Custom docker image](https://github.com/ricsanfre/fluentd-aggregator) from official v1.17.1|
| Logging | Loki | 3.5.7 | Helm chart grafana/loki version: 6.45.2  |
| Monitoring | Kube Prometheus Stack | v0.86.1 | Helm chart version: 79.0.0 |
| Monitoring | Prometheus Operator | v0.86.1 | Installed by Kube Prometheus Stack. Helm chart version: 79.0.0  |
| Monitoring | Prometheus | v3.7.3 | Installed by Kube Prometheus Stack. Helm chart version: 79.0.0 |
| Monitoring | AlertManager | v0.28.1 | Installed by Kube Prometheus Stack. Helm chart version: 79.0.0 |
| Monitoring | Prometheus Node Exporter | v1.10.2 | Installed as dependency of Kube Prometheus Stack chart. Helm chart version: 79.0.0 |
| Monitoring | Kube State Metrics | 2.17.0 | Installed as dependency of Kube Prometheus Stack chart. Helm chart version: 79.0.0 |
| Monitoring | Prometheus Elasticsearch Exporter | 1.9.0 | Helm chart version: prometheus-elasticsearch-exporter-7.0.0 |
| Monitoring | Grafana | 12.2.1 | Helm chart version: 10.1.4 |
| Tracing | Grafana Tempo | 2.9.0 | Helm chart: tempo-distributed (v1.52.6) |
| Backup | Minio External (self-hosted) | RELEASE.2025-10-15T17-29-55Z | |
| Backup | Restic | 0.18.0 | |
| Backup | Velero | 1.17.0 | Helm chart version: 11.1.1 |
| Secrets | Hashicorp Vault | 1.20.3 | |
| Secrets| External Secret Operator | 0.20.3 | Helm chart version: 0.20.3 |
| Identity Access Management | Keycloak | 26.4.2 | Keycloak Operator |
| Identity Access Management | Oauth2.0 Proxy | 7.12.0 | Helm chart version: 8.3.2 |
| GitOps | Flux CD | v2.7.3 |  |
{: .table .border-dark }
