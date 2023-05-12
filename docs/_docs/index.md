---
title: What is this project about?
permalink: /docs/home/
redirect_from: /docs/index.html
description: The scope of this project is to create a kubernetes cluster at home using Raspberry Pis and to automate its deployment and configuration applying IaC (infrastructure as a code) and GitOps methodologies with tools like Ansible and ArgoCD. How to automatically deploy K3s baesed kubernetes cluster, Longhorn as distributed block storage for PODs' persistent volumes, Prometheus as monitoring solution, EFK+Loki stack as centralized log management solution, Velero and Restic as backup solution and Linkerd as service mesh architecture.
last_modified_at: "25-01-2023"
---


## Scope
The scope of this project is to create a kubernetes cluster at home using **Raspberry Pis** and to automate its deployment and configuration applying **IaC (infrastructure as a code)** and **GitOps** methodologies with tools like [Ansible](https://docs.ansible.com/), [cloud-init](https://cloudinit.readthedocs.io/en/latest/) and [Argo CD](https://argo-cd.readthedocs.io/en/stable/).

As part of the project, the goal is to use a lightweight Kubernetes flavor based on [K3S](https://k3s.io/) and deploy cluster basic services such as: 1) distributed block storage for POD's persistent volumes, [LongHorn](https://longhorn.io/), 2) backup/restore solution for the cluster, [Velero](https://velero.io/) and [Restic](https://restic.net/), 3) service mesh architecture, [Linkerd](https://linkerd.io/), and 4) observability platform based on metrics monitoring solution, [Prometheus](https://prometheus.io/), logging and analytics solution, EFḰ+LG stack ([Elasticsearch](https://www.elastic.co/elasticsearch/)-[Fluentd](https://www.fluentd.org/)/[Fluentbit](https://fluentbit.io/)-[Kibana](https://www.elastic.co/kibana/) + [Loki](https://grafana.com/oss/loki/)-[Grafana](https://grafana.com/oss/grafana/)), and distributed tracing solution, [Tempo](https://grafana.com/oss/tempo/).


## Design Principles

- Use ARM 64 bits operating system enabling the possibility of using Raspberry PI B nodes with 8GB RAM. Currently only Ubuntu supports 64 bits ARM distribution for Raspberry Pi.
- Use ligthweigh Kubernetes distribution (K3S). Kuberentes distribution with a smaller memory footprint which is ideal for running on Raspberry PIs
- Use of distributed storage block technology, instead of centralized NFS system, for pod persistent storage.  Kubernetes block distributed storage solutions, like Rook/Ceph or Longhorn, in their latest versions have included ARM 64 bits support.
- Use of opensource projects under the [CNCF: Cloud Native Computing Foundation](https://www.cncf.io/) umbrella
- Use latest versions of each opensource project to be able to test the latest Kubernetes capabilities.
- Use of [cloud-init](https://cloudinit.readthedocs.io/en/latest/) to automate the initial OS installation.
- Use of [Ansible](https://docs.ansible.com/) for automating the configuration of the cluster nodes, installation of kubernetes and external services, and triggering cluster bootstrap (ArgoCD bootstrap).
- Use of [Argo CD](https://argo-cd.readthedocs.io/en/stable/) to automatically provision Kubernetes applications from git repository.


## Technology Stack

The following picture shows the set of opensource solutions used for building this cluster:

![Cluster-Icons](/assets/img/pi-cluster-icons.png)

<div class="d-flex">
<table class="table table-white table-borderer border-dark w-auto align-middle">
    <tr>
        <th></th>
        <th>Name</th>
        <th>Description</th>
    </tr>
    <tr>
        <td><img width="32" src="https://simpleicons.org/icons/ansible.svg"></td>
        <td><a href="https://www.ansible.com">Ansible</a></td>
        <td>Automate OS configuration, external services installation and k3s installation and bootstrapping</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/argo/icon/color/argo-icon-color.svg"></td>
        <td><a href="https://argoproj.github.io/cd">ArgoCD</a></td>
        <td>GitOps tool for deploying applications to Kubernetes</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cloud-init.github.io/images/cloud-init-orange.svg"></td>
        <td><a href="https://cloudinit.readthedocs.io/en/latest/">Cloud-init</a></td>
        <td>Automate OS initial installation</td>
    </tr>
    <tr>
        <td><img width="32" src="https://assets.ubuntu.com/v1/ce518a18-CoF-2022_solid+O.svg"></td>
        <td><a href="https://ubuntu.com/">Ubuntu</a></td>
        <td>Cluster nodes OS</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/k3s/icon/color/k3s-icon-color.svg"></td>
        <td><a href="https://k3s.io/">K3S</a></td>
        <td>Lightweight distribution of Kubernetes</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/containerd/icon/color/containerd-icon-color.svg"></td>
        <td><a href="https://containerd.io/">containerd</a></td>
        <td>Container runtime integrated with K3S</td>
    </tr>
    <tr>
        <td><img width="20" src="https://raw.githubusercontent.com/flannel-io/flannel/master/logos/flannel-glyph-color.svg"></td>
        <td><a href="https://github.com/flannel-io/flannel">Flannel</a></td>
        <td>Kubernetes Networking (CNI) integrated with K3S</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/coredns/icon/color/coredns-icon-color.svg"></td>
        <td><a href="https://coredns.io/">CoreDNS</a></td>
        <td>Kubernetes DNS</td>
    </tr>
    <tr>
        <td><img width="32" src="https://metallb.universe.tf/images/logo/metallb-blue.png"></td>
        <td><a href="https://metallb.universe.tf/">Metal LB</a></td>
        <td>Load-balancer implementation for bare metal Kubernetes clusters</td>
    </tr>
    <tr>
        <td><img width="32" src="https://landscape.cncf.io/logos/traefik.svg"></td>
        <td><a href="https://traefik.io/">Traefik</a></td>
        <td>Kubernetes Ingress Controller</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/linkerd/icon/color/linkerd-icon-color.svg"></td>
        <td><a href="https://linkerd.io/">Linkerd</a></td>
        <td>Kubernetes Service Mesh</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/longhorn/icon/color/longhorn-icon-color.svg"></td>
        <td><a href="https://longhorn.io/">Longhorn</a></td>
        <td>Kubernetes distributed block storage</td>
    </tr>
    <tr>
        <td><img width="60" src="https://min.io/resources/img/logo.svg"></td>
        <td><a href="https://min.io/">Minio</a></td>
        <td>S3 Object Storage solution</td>
    </tr>
    <tr>
        <td><img width="32" src="https://landscape.cncf.io/logos/cert-manager.svg"></td>
        <td><a href="https://cert-manager.io">Cert-manager</a></td>
        <td>TLS Certificates management</td>
    </tr>
    <tr>
        <td><img width="32" src="https://simpleicons.org/icons/vault.svg"></td>
        <td><a href="https://www.vaultproject.io/">Hashicorp Vault</a></td>
        <td>Secrets Management solution</td>
    </tr>
    <tr>
        <td><img width="32" src="https://landscape.cncf.io/logos/external-secrets.svg"></td>
        <td><a href="https://external-secrets.io/">External Secrets Operator</a></td>
        <td>Sync Kubernetes Secrets from Hashicorp Vault</td>
    </tr>
    <tr>
        <td><img width="60" src="https://velero.io/img/Velero.svg"></td>
        <td><a href="https://velero.io/">Velero</a></td>
        <td>Kubernetes Backup and Restore solution</td>
    </tr>
    <tr>
        <td><img width="32" src="https://github.com/restic/restic/raw/master/doc/logo/logo.png"></td>
        <td><a href="https://restic.net/">Restic</a></td>
        <td>OS Backup and Restore solution</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/prometheus/icon/color/prometheus-icon-color.png"></td>
        <td><a href="https://prometheus.io/">Prometheus</a></td>
        <td>Metrics monitoring and alerting</td>
    </tr>
    <tr>
        <td><img width="32" src="https://cncf-branding.netlify.app/img/projects/fluentd/icon/color/fluentd-icon-color.png"></td>
        <td><a href="https://www.fluentd.org/">Fluentd</a></td>
        <td>Logs forwarding and distribution</td>
    </tr>
    <tr>
        <td><img width="60" src="https://fluentbit.io/images/logo.svg"></td>
        <td><a href="https://fluentbit.io/">Fluentbit</a></td>
        <td>Logs collection</td>
    </tr>
    <tr>
        <td><img width="32" src="https://github.com/grafana/loki/blob/main/docs/sources/logo.png?raw=true"></td>
        <td><a href="https://grafana.com/oss/loki/">Loki</a></td>
        <td>Logs aggregation</td>
    </tr>
    <tr>
        <td><img width="32" src="https://static-www.elastic.co/v3/assets/bltefdd0b53724fa2ce/blt36f2da8d650732a0/5d0823c3d8ff351753cbc99f/logo-elasticsearch-32-color.svg"></td>
        <td><a href="https://www.elastic.co/elasticsearch/">Elasticsearch</a></td>
        <td>Logs analytics</td>
    </tr>
    <tr>
        <td><img width="32" src="https://static-www.elastic.co/v3/assets/bltefdd0b53724fa2ce/blt4466841eed0bf232/5d082a5e97f2babb5af907ee/logo-kibana-32-color.svg"></td>
        <td><a href="https://www.elastic.co/kibana/">Kibana</a></td>
        <td>Logs analytics Dashboards</td>
    </tr>
    <tr>
        <td><img width="32" src="https://grafana.com/static/assets/img/logos/grafana-tempo.svg"></td>
        <td><a href="https://grafana.com/oss/tempo/">Tempo</a></td>
        <td>Distributed tracing monitoring</td>
    </tr>
    <tr>
        <td><img width="32" src="https://grafana.com/static/img/menu/grafana2.svg"></td>
        <td><a href="https://grafana.com/oss/grafana/">Grafana</a></td>
        <td>Monitoring Dashboards</td>
    </tr>
</table>
</div>


## External Resources and Services

Even whe the premise is to deploy all services in the kubernetes cluster, there is still a need for a few external services/resources. Below is a list of external resources/services and why we need them.

### Cloud external services

{{site.data.alerts.note}}
 These resources are optional, the homelab still works without them but it won't have trusted certificates.
{{site.data.alerts.end}}

|  |Provider | Resource | Purpose |
| --- | --- | --- | --- |
| <img width="60" src="https://letsencrypt.org/images/letsencrypt-logo-horizontal.svg" >| [Letsencrypt](https://letsencrypt.org/) | TLS CA Authority | Signed valid TLS certificates |
| <img width="60" src="https://www.ionos.de/newsroom/wp-content/uploads/2022/03/LOGO_IONOS_Blue_RGB-1.png"> |[IONOS](https://www.ionos.es/) | DNS | DNS and [DNS-01 challenge](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge) for certificates |
{: .table .table-white .border-dark }

**Alternatives:**

1. Use a private PKI (custom CA to sign certificates).

   Currently supported. Only minor changes are required. See details in [Doc: Quick Start instructions](/docs/ansible).

2. Use other DNS provider.

   Cert-manager / Certbot used to automatically obtain certificates from Let's Encrypt can be used with other DNS providers. This will need further modifications in the way cert-manager application is deployed (new providers and/or webhooks/plugins might be required).

   Currently only acme issuer (letsencytp) using IONOS as dns-01 challenge provider is configured. Check list of [supported dns01 providers](https://cert-manager.io/docs/configuration/acme/dns01/#supported-dns01-providers).

### Self-hosted external services 

There is another list of services that I have decided to run outside the kuberentes cluster selfhosting them.

|  |External Service | Resource | Purpose |
| --- | --- | --- | --- |
| <img width="60" src="https://min.io/resources/img/logo.svg"> |[Minio](https://mini.io) | S3 Object Store | Cluster Backup  |
| <img width="32" src="https://simpleicons.org/icons/vault.svg"> |[Hashicorp Vault](https://www.vaultproject.io/) | Secrets Management | Cluster secrets management |
{: .table .table-white .border-dark .align-middle }


Minio backup servive is hosted in a VM running in Public Cloud, using [Oracle Cloud Infrastructure (OCI) free tier](https://www.oracle.com/es/cloud/free/).

Vault service is running in `gateway` node, since Vault kubernetes authentication method need access to Kuberentes API, I won't host Vault service in Public Cloud.


## What I have built so far

From hardware perspective I built two different versions of the cluster

- Release 1.0: Basic version using dedicated USB flash drive for each node and centrazalized SAN as additional storage

![Cluster-1.0](/assets/img/pi-cluster.png)

- Release 2.0: Adding dedicated SSD disk to each node of the cluster and improving a lot the overall cluster performance

![!Cluster-2.0](/assets/img/pi-cluster-2.0.png)


## What I have developed so far

{{site.data.alerts.important}}
All source code can be found in the project's github repository [{{site.data.icons.github}}]({{site.git_address}}).

{{site.data.alerts.end}}


From software perspective, I have developed the following:

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
   {: .table .table-white .border-dark } 

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
| Kubernetes | K3S | v1.26.3 | K3S version|
| Kubernetes | Helm | v3.9.4 ||
| Metrics | Kubernetes Metrics Server | v0.6.2 | version pre-integrated into K3S |
| Computing | containerd | v1.6.19-k3s1 | version pre-integrated into K3S |
| Networking | Flannel | v0.21.4 | version pre-integrated into K3S |
| Networking | CoreDNS | v1.9.4 | version pre-integrated into K3S |
| Networking | Metal LB | v0.13.9 | Helm chart version:  0.13.9 |
| Service Mesh | Linkerd | v2.13.3 | Helm chart version: linkerd-control-plane-1.12.3 |
| Service Proxy | Traefik | v2.9.10 | Helm chart version: 22.1.0  |
| Storage | Longhorn | v1.4.1 | Helm chart version: 1.4.1 |
| Storage | Minio | RELEASE.2023-04-28T18-11-17Z | Helm chart version: 5.0.9 |
| TLS Certificates | Certmanager | v1.11.1| Helm chart version: v1.11.1  |
| Logging | ECK Operator |  2.7.0 | Helm chart version: 2.7.0 |
| Logging | Elastic Search | 8.6.0 | Deployed with ECK Operator |
| Logging | Kibana | 8.6.0 | Deployed with ECK Operator |
| Logging | Fluentbit | 2.0.10 | Helm chart version: 0.25.0 |
| Logging | Fluentd | 1.15.2 | Helm chart version: 0.3.9. [Custom docker image](https://github.com/ricsanfre/fluentd-aggregator) from official v1.15.2|
| Logging | Loki | 2.8.2 | Helm chart grafana/loki version: 5.5.1 |
| Monitoring | Kube Prometheus Stack | 0.61.1 | Helm chart version: 43.3.1 |
| Monitoring | Prometheus Operator | 0.61.1 | Installed by Kube Prometheus Stack. Helm chart version: 43.3.1   |
| Monitoring | Prometheus | 2.40.5 | Installed by Kube Prometheus Stack. Helm chart version: 43.3.1 |
| Monitoring | AlertManager | 0.25.0 | Installed by Kube Prometheus Stack. Helm chart version: 43.3.1 |
| Monitoring | Grafana | 9.3.1 | Helm chart version grafana-6.48.2. Installed as dependency of Kube Prometheus Stack chart. Helm chart version: 43.3.1 |
| Monitoring | Prometheus Node Exporter | 1.5.0 | Helm chart version: prometheus-node-exporter-4.8.2. Installed as dependency of Kube Prometheus Stack chart. Helm chart version: 43.3.1 |
| Monitoring | Prometheus Elasticsearch Exporter | 1.5.0 | Helm chart version: prometheus-elasticsearch-exporter-4.15.1 |
| Tracing | Grafana Tempo | 2.1.1 | Helm chart: tempo-distributed (1.4.0) |
| Backup | Minio External (self-hosted) | RELEASE.2023-04-20T17:56:55Z| |
| Backup | Restic | 0.13.1 | |
| Backup | Velero | 1.9.3 | Helm chart version: 2.32.1 |
| Secrets | Hashicorp Vault | 1.12.2 | |
| Secrets| External Secret Operator | 0.8.1 | Helm chart version: 0.8.1 |
| GitOps | Argo CD | v2.7.2 | Helm chart version: 5.33.2 |
{: .table .table-white .border-dark }
