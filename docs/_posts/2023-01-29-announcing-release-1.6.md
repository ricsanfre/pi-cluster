---
layout: post
title:  Kubernetes Pi Cluster relase v1.6
date:   2023-01-29
author: ricsanfre
---

Today I am pleased to announce the sixth release of Kubernetes Pi Cluster project (v1.6). 

Main features/enhancements of this release are:

## GitOps methodology adoption (ArgoCD)

In previous releases Ansible were used not only to configure cluster nodes OS and install K3S, but also to deploy Kubernetes applications in an imperative way, through the sequiential execution of installation/configuration commands (`helm install` and `kubectl apply -f`) contained in Ansible playbooks/roles and all helm chart values files and manifests needed to be applied in form of jinja2 templates.

In this new release, deployment of Kuberentes applications is completely managed by [Argo CD](https://argo-cd.readthedocs.io/), being Git repository the single source of truth for helm charts configuration files and kubernetes manifest. Kubernetes applications keep synch with manifest files stored in Git repository, enabling the implementation of a Continuous Delivery (CD) pipeline.

![picluster-cicd-gitops-architecture](/assets/img/cicd-gitops-architecture.png)

The automation source code has been completely refactored:
- New packaged Kubernetes applications, in form of  helm charts or sets of manifest files, have been developed, so they can be deployed with ArgoCD.
- Changes in Ansible automation code to automatically boot the cluster using ArgoCD
- Remove old ansible code to deploy Kuberentes applications

Check further details about [ArgoCD installation and configuration](/docs/argocd) in the documentation and the new [Quick Start Instructions](/docs/ansible/).

## New Secrets Management solution (Hashicorp Vault)

Related to the previous feature, a Secret Management tool has been integrated in the cluster to maanage the creation of secrets needed by the Cluster Applications.  

[HashiCorp Vault](https://www.vaultproject.io/) is used now as Secret Management solution for Raspberry PI cluster. All cluster secrets (users, passwords, api tokens, etc) are securely encrypted and stored in Vault.

Vault is deployed as a external service, not runing as Kuberentes application. [External Secrets Operator](https://external-secrets.io/) is used to automatically generate the Kubernetes Secrets from Vault data that Kubernetes applications could need.

![picluster-secretsmanagement-architecture](/assets/img/vault-externalsecrets.png)

Cluster bootstrap process, using Ansible, takes care of the installation and configuration of Hashicorp Vault and the initial load of secrets needed by the cluster applications.

Check further details in [Vautl Installation doc](/docs/vault).

## From Monitoring to Observability platform

Move from a Monitoring platform, based on Prometheus (metrics) and EFK (logs) to a Observability Platform adding traces monitoring and a single plane of glass.

New observability solution based on [Loki](https://grafana.com/oss/loki/) (logs), [Tempo](https://grafana.com/oss/tempo/) (traces), [Prometheus](https://prometheus.io/) (metrics) and Grafana as single plane of glass for monitoring.

![observability-architecture](/assets/img/observability-architecture.png)

Main features:

- Grafana Loki as complement of the available EFK platform, not a replacement. ES is used mainly for Log Analytics (log content is completely indexed) while Loki can be used for Observability (only log labels are indexed) having together logs, metrics and traces in the same Grafana Dashboards.

- Common logs collection/distrution layer based on fluentbit/fluentd is used to feed logs to ES and to Loki, instead of deploying a separate collector ([Loki promtail](https://grafana.com/docs/loki/latest/clients/promtail/))

- Grafana Tempo as distributed tacing solution integrating [Linkerd distributed tracing](https://linkerd.io/2.11/tasks/distributed-tracing/) capability.


## Upgrade software components to latest stable version

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
{: .table .table-white .border-dark }

## Release v1.6.0 Notes

Apply GitOps methodology using ArgoCD to deploy and manage Kubernetes Applications, integrate Hashicorp Vault secret management solution and transform monitoring platform into observability platform (logs, traces and metrics monitoring).

### Release Scope:

  - GitOps methodology
    - Argo CD deployment
    - New packaged Kubernetes applications (helm charts and manifest files) to be deployed using ArgoCD
    - Automate cluster bootstraping with ArgoCD using Ansible
    - Ansible playbooks/roles/vars refactoring
  
  - Integrate Secrets Management solution
    - Hashicorp Vault deployment
    - Kuberentes authorization mechanism integration
    - External Secrets Operator deployment

  - Observability platform
    - Grafana Loki and Grafana Tempo deployment
    - Grafana as cluster operations single pane of glass
    - Fluentbit/Fluentd configuration to distribute logs to ES and Loki
    - Linkerd distributed tracing integration
    - Traefik tracing integration and automatic correlation with access logs 

  - Automation enhancements
    - Integration of Ansible vault and GPG to automate the encrypt/decrypt process
    - Automatic generation of credentials and load in Vault
    - Add Makefile