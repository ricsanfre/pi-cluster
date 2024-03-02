---
title: What is this project about?
permalink: /docs/home/
redirect_from: /docs/index.html
description: The scope of this project is to create a kubernetes cluster at home using Raspberry Pis and low cost mini PCs, and to automate its deployment and configuration applying IaC (infrastructure as a code) and GitOps methodologies with tools like Ansible and ArgoCD. How to automatically deploy K3s baesed kubernetes cluster, Longhorn as distributed block storage for PODs' persistent volumes, Prometheus as monitoring solution, EFK+Loki stack as centralized log management solution, Velero and Restic as backup solution and Linkerd as service mesh architecture.
last_modified_at: "02-03-2024"
---


## Scope

The main goal of  this project is to create a kubernetes cluster at home using ARM/x86 bare metal nodes (**Raspberry Pis** and low cost refurbished **mini PCs**) and to automate its deployment and configuration applying **IaC (infrastructure as a code)** and **GitOps** methodologies with tools like [Ansible](https://docs.ansible.com/), [cloud-init](https://cloudinit.readthedocs.io/en/latest/) and [Argo CD](https://argo-cd.readthedocs.io/en/stable/).

The project scope includes the automation of the deployment and configuration of a lightweight Kubernetes flavor based on [K3S](https://k3s.io/),
and deploy cluster basic services such as:
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

Also services needed to learn about microservices architectures are include as part of the scope

- Service mesh architecture, [Linkerd](https://linkerd.io/)
- API security using Oauth2.0 and OpenId Connect, using IAM solution, [Keycloak](https://www.keycloak.org/)
- Streaming platform, [Kafka](https://kafka.apache.org/)

## Design Principles

- Use hybrid x86/ARM bare metal nodes, combining in the same cluster Raspberry PI nodes (ARM) and x86 mini PCs (HP Elitedesk 800 G3).
- Use lightweight Kubernetes distribution (K3S). Kubernetes distribution with a smaller memory footprint which is ideal for running on Raspberry PIs
- Use distributed storage block technology, instead of centralized NFS system, for pod persistent storage.  Kubernetes block distributed storage solutions, like Rook/Ceph or Longhorn, in their latest versions have included ARM 64 bits support.
- Use opensource projects under the [CNCF: Cloud Native Computing Foundation](https://www.cncf.io/) umbrella
- Use latest versions of each opensource project to be able to test the latest Kubernetes capabilities.
- Automate deployment of cluster using IaC (infrastructure as a code) and GitOps methodologies with tools like:
  - [cloud-init](https://cloudinit.readthedocs.io/en/latest/) to automate the initial OS installation of the cluster nodes.
  - [Ansible](https://docs.ansible.com/) for automating the configuration of the cluster nodes, installation of kubernetes and external services, and triggering cluster bootstrap (ArgoCD bootstrap).
  - [Argo CD](https://argo-cd.readthedocs.io/en/stable/) to automatically provision Kubernetes applications from git repository.


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
        <td><img width="32" src="/assets/img/logos/ansible.svg" alt="ansible logo"></td>
        <td><a href="https://www.ansible.com">Ansible</a></td>
        <td>Automate OS configuration, external services installation and k3s installation and bootstrapping</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/argocd.svg" alt="argocd logo"></td>
        <td><a href="https://argoproj.github.io/cd">ArgoCD</a></td>
        <td>GitOps tool for deploying applications to Kubernetes</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/cloud-init.svg" alt="cloud-init logo"></td>
        <td><a href="https://cloudinit.readthedocs.io/en/latest/">Cloud-init</a></td>
        <td>Automate OS initial installation</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/ubuntu.svg" alt="ubuntu logo"></td>
        <td><a href="https://ubuntu.com/">Ubuntu</a></td>
        <td>Cluster nodes OS</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/k3s.svg" alt="k3s logo"></td>
        <td><a href="https://k3s.io/">K3S</a></td>
        <td>Lightweight distribution of Kubernetes</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/containerd.svg" alt="containerd logo"></td>
        <td><a href="https://containerd.io/">containerd</a></td>
        <td>Container runtime integrated with K3S</td>
    </tr>
    <tr>
        <td><img width="20" src="/assets/img/logos/flannel.svg" alt="flannel logo"></td>
        <td><a href="https://github.com/flannel-io/flannel">Flannel</a></td>
        <td>Kubernetes Networking (CNI) integrated with K3S</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/coredns.svg" alt="coredns logo"></td>
        <td><a href="https://coredns.io/">CoreDNS</a></td>
        <td>Kubernetes DNS</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/haproxy.svg" alt="haproxy logo"></td>
        <td><a href="https://www.haproxy.org/">HA Proxy</a></td>
        <td>Kubernetes API Load-balancer</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/metallb.svg" alt="metallb logo"></td>
        <td><a href="https://metallb.universe.tf/">Metal LB</a></td>
        <td>Load-balancer implementation for bare metal Kubernetes clusters</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/nginx.svg" alt="nginx logo"></td>
        <td><a href="https://kubernetes.github.io/ingress-nginx/">Ingress NGINX</a></td>
        <td>Kubernetes Ingress Controller</td>
    </tr> 
    <tr>
        <td><img width="32" src="/assets/img/logos/traefik.svg" alt="traefik logo"></td>
        <td><a href="https://traefik.io/">Traefik</a></td>
        <td>Kubernetes Ingress Controller (alternative)</td>
    </tr>   
    <tr>
        <td><img width="32" src="/assets/img/logos/linkerd.svg" alt="linkerd logo"></td>
        <td><a href="https://linkerd.io/">Linkerd</a></td>
        <td>Kubernetes Service Mesh</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/longhorn.svg" alt="longhorn logo"></td>
        <td><a href="https://longhorn.io/">Longhorn</a></td>
        <td>Kubernetes distributed block storage</td>
    </tr>
    <tr>
        <td><img width="60" src="/assets/img/logos/minio.svg" alt="minio logo"></td>
        <td><a href="https://min.io/">Minio</a></td>
        <td>S3 Object Storage solution</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/cert-manager.svg" alt="cert-manager logo"></td>
        <td><a href="https://cert-manager.io">Cert-manager</a></td>
        <td>TLS Certificates management</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/vault.svg" alt="vault logo"></td>
        <td><a href="https://www.vaultproject.io/">Hashicorp Vault</a></td>
        <td>Secrets Management solution</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/external-secrets.svg" alt="external-secrets logo"></td>
        <td><a href="https://external-secrets.io/">External Secrets Operator</a></td>
        <td>Sync Kubernetes Secrets from Hashicorp Vault</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/keycloak.svg" alt="keycloak logo"></td>
        <td><a href="https://www.keycloak.org/">Keycloak</a></td>
        <td>Identity Access Management</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/OAuth2-proxy.svg" alt="oauth2-proxy logo"></td>
        <td><a href="https://oauth2-proxy.github.io/oauth2-proxy/">OAuth2.0 Proxy</a></td>
        <td>OAuth2.0 Proxy</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/velero.svg" alt="velero logo"></td>
        <td><a href="https://velero.io/">Velero</a></td>
        <td>Kubernetes Backup and Restore solution</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/restic.png" alt="restic logo"></td>
        <td><a href="https://restic.net/">Restic</a></td>
        <td>OS Backup and Restore solution</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/prometheus.svg" alt="prometheus logo"></td>
        <td><a href="https://prometheus.io/">Prometheus</a></td>
        <td>Metrics monitoring and alerting</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/fluentd.svg" alt="fluentd logo"></td>
        <td><a href="https://www.fluentd.org/">Fluentd</a></td>
        <td>Logs forwarding and distribution</td>
    </tr>
    <tr>
        <td><img width="60" src="/assets/img/logos/fluentbit.svg" alt="fluentbit logo"></td>
        <td><a href="https://fluentbit.io/">Fluentbit</a></td>
        <td>Logs collection</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/loki.png" alt="loki logo"></td>
        <td><a href="https://grafana.com/oss/loki/">Loki</a></td>
        <td>Logs aggregation</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/elastic.svg" alt="elasticsearch logo"></td>
        <td><a href="https://www.elastic.co/elasticsearch/">Elasticsearch</a></td>
        <td>Logs analytics</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/kibana.svg" alt="kibana logo"></td>
        <td><a href="https://www.elastic.co/kibana/">Kibana</a></td>
        <td>Logs analytics Dashboards</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/tempo.svg" alt="tempo logo"></td>
        <td><a href="https://grafana.com/oss/tempo/">Tempo</a></td>
        <td>Distributed tracing monitoring</td>
    </tr>
    <tr>
        <td><img width="32" src="/assets/img/logos/grafana.svg" alt="grafana logo"></td>
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
| <img width="60" src="/assets/img/logos/letsencrypt.svg" alt="letsencrypt logo" >| [Letsencrypt](https://letsencrypt.org/) | TLS CA Authority | Signed valid TLS certificates |
| <img width="60" src="/assets/img/logos/ionos.png" alt="ionos logo"> |[IONOS](https://www.ionos.es/) | DNS | DNS and [DNS-01 challenge](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge) for certificates |
{: .table .table-white .border-dark }

**Alternatives:**

1. Use a private PKI (custom CA to sign certificates).

   Currently supported. Only minor changes are required. See details in [Doc: Quick Start instructions](/docs/ansible/).

2. Use other DNS provider.

   Cert-manager / Certbot used to automatically obtain certificates from Let's Encrypt can be used with other DNS providers. This will need further modifications in the way cert-manager application is deployed (new providers and/or webhooks/plugins might be required).

   Currently only acme issuer (letsencytp) using IONOS as dns-01 challenge provider is configured. Check list of [supported dns01 providers](https://cert-manager.io/docs/configuration/acme/dns01/#supported-dns01-providers).

### Self-hosted external services 

There is another list of services that I have decided to run outside the kuberentes cluster selfhosting them.

|  |External Service | Resource | Purpose |
| --- | --- | --- | --- |
| <img width="60" src="/assets/img/logos/minio.svg" alt="minio logo"> |[Minio](https://mini.io) | S3 Object Store | Cluster Backup  |
| <img width="32" src="/assets/img/logos/vault.svg" alt="vault logo"> |[Hashicorp Vault](https://www.vaultproject.io/) | Secrets Management | Cluster secrets management |
{: .table .table-white .border-dark .align-middle }


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
| OS | Ubuntu | 22.04.2 | |
| Control | Ansible | 2.16.3  | |
| Control | cloud-init | 23.1.2 | version pre-integrated into Ubuntu 22.04.2 |
| Kubernetes | K3S | v1.29.1 | K3S version|
| Kubernetes | Helm | v3.12 ||
| Metrics | Kubernetes Metrics Server | v0.6.3 | version pre-integrated into K3S |
| Kubernetes | etcd | v3.5.9-k3s1 | version pre-integrated into K3S |
| Computing | containerd | v1.7.11-k3s2 | version pre-integrated into K3S |
| Networking | Flannel | v0.24.0 | version pre-integrated into K3S |
| Networking | CoreDNS | v1.10.1 | version pre-integrated into K3S |
| Networking | Metal LB | v0.14.3 | Helm chart version:  0.14.3 |
| Service Mesh | Linkerd | v2.14.10 | Helm chart version: linkerd-control-plane-1.16.11 |
| Service Proxy | Traefik | v2.10.6 | Helm chart version: 26.0.0  |
| Service Proxy | Ingress NGINX | v1.9.6 | Helm chart version: 4.9.1 |
| Storage | Longhorn | v1.5.3 | Helm chart version: 1.5.3 |
| Storage | Minio | RELEASE.2024-01-11T07-46-16Z | Helm chart version: 5.0.15 |
| TLS Certificates | Certmanager | v1.14.3| Helm chart version: v1.14.3  |
| Logging | ECK Operator |  2.11.1 | Helm chart version: 2.11.1 |
| Logging | Elastic Search | 8.6.0 | Deployed with ECK Operator |
| Logging | Kibana | 8.6.0 | Deployed with ECK Operator |
| Logging | Fluentbit | 2.2.2 | Helm chart version: 0.43.0 |
| Logging | Fluentd | 1.15.3 | Helm chart version: 0.5.2 [Custom docker image](https://github.com/ricsanfre/fluentd-aggregator) from official v1.15.3|
| Logging | Loki | 2.9.5 | Helm chart grafana/loki version: 5.43.3 |
| Monitoring | Kube Prometheus Stack | v0.71.2 | Helm chart version: 56.19.0 |
| Monitoring | Prometheus Operator | v0.71.2 | Installed by Kube Prometheus Stack. Helm chart version: 56.19.0  |
| Monitoring | Prometheus | v2.50.1 | Installed by Kube Prometheus Stack. Helm chart version: 56.19.0 |
| Monitoring | AlertManager | v0.27.0 | Installed by Kube Prometheus Stack. Helm chart version: 56.19.0 |
| Monitoring | Grafana | 10.3.3 | Installed as dependency of Kube Prometheus Stack chart 56.19.0 |
| Monitoring | Prometheus Node Exporter | v1.7.0 | Installed as dependency of Kube Prometheus Stack chart. Helm chart version: 56.19.0 |
| Monitoring | Prometheus Elasticsearch Exporter | 1.7.0 | Helm chart version: prometheus-elasticsearch-exporter-5.6.0 |
| Tracing | Grafana Tempo | 2.3.1 | Helm chart: tempo-distributed (1.8.5) |
| Backup | Minio External (self-hosted) | RELEASE.2024-01-31T20:20:33Z | |
| Backup | Restic | 0.13.1 | |
| Backup | Velero | 1.13.0 | Helm chart version: 6.0.0 |
| Secrets | Hashicorp Vault | 1.15.4 | |
| Secrets| External Secret Operator | 0.9.13 | Helm chart version: 0.9.13 |
| SSO | Keycloak | 23.0.7 | Bitnami Helm chart version: 18.7.1 |
| SSO| Oauth2.0 Proxy | 7.6.0 | Helm chart version: 7.1.0 |
| GitOps | Argo CD | v2.10.2 | Helm chart version: 6.5.1 |
{: .table .table-white .border-dark }
