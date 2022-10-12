---
layout: post
title:  Kubernetes Pi Cluster relase v1.5
date:   2022-10-12
author: ricsanfre
---

Today I am pleased to announce the fifth release of Kubernetes Pi Cluster project (v1.5). 

Main features/enhancements of this release are:


## Let's Encrypt certificates integration

Adding Let's Encrypt integration in CertManager to generate automatically valid TLS certificates.

CertManager is configured to deliver valid certificates through its integration with Let's Encrypt using ACME DNS challenges. ACME HTTPS challenge, also supported by CertManager-LetsEncrypt, is not configured since it requires to expose the cluster services to the public internet.

Configuration is provided for using IONOS DNS provider, using developer API available to automate challenge resolution and [IONOS cert-manager webhook](https://github.com/fabmade/cert-manager-webhook-ionos).

Similar configuration can be implemented for other supported DNS providers. See supported list and further documentation in [Certmanager documentation: "ACME DNS01" ](https://cert-manager.io/docs/configuration/acme/dns01/).

Valid certificates signed by Letscript are used for cluster exposed services. For internal services, like Linkerd, self-signed certificates are used.

[Cerbot](https://certbot.eff.org/) and [certbot-dns-ionos plugin](https://github.com/helgeerbe/certbot-dns-ionos) installation details are also provided to generate Let's Encrypt certificates outside the cluster, using the same ACME DNS challenge.


## Adding CSI Snapshot support

Enabling within K3S cluster the new Kubernetes CSI feature: [Volume Snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/) to be able to programmatically create backups and so orchestrate consistent backups within Velero

CSI  Snapshot feature is supported by Longhorn and Velero. See Longhorn documentation: [CSI Snapshot Support](https://longhorn.io/docs/1.2.2/snapshots-and-backups/csi-snapshot-support/create-a-backup-via-csi/) and [Velero CSI Snapshots documentation](https://velero.io/docs/v1.9/csi/).

K3S currently does not come with a preintegrated Snapshot Controller, needed to enable CSI Snapshot functionallity. An [external snapshot controller](https://github.com/kubernetes-csi/external-snapshotter) has been deployed.

## Prometheus memory footprint optimization

Memory footprint reduction is achieved by removing  all metrics duplicates from K3S monitoring. See details in [issue #67](https://github.com/ricsanfre/pi-cluster/issues/67)

Before the optimization, K3S duplicates came from monitoring kube-proxy, kubelet and apiserver components. kube-controller-manager and kube-scheduler monitoring was already removed in the past. See [issue #22](https://github.com/ricsanfre/pi-cluster/issues/22) 

**Before removing K3S duplicates**:

| Active Series | Memory Usage |
|:---:|:---:|
| ![Prometheus_Active_series_before](https://user-images.githubusercontent.com/84853324/187235196-15aa874d-7ffe-434e-b14a-1c2a41364b79.png) | ![Prometheus_memory_before](https://user-images.githubusercontent.com/84853324/187235370-75064b56-ce58-4f4a-92a1-5d52d429d58c.png) |


Number of active time series: 157k

Memory usage: 1GB

**After removing duplicates**

| Active Series | Memory Usage |
|:---:|:---:|
![Prometheus_Active_series_after](https://user-images.githubusercontent.com/84853324/187251837-6b49bc30-29a3-436f-9627-a86ecbb48f37.png) | ![Prometheus_memory_after](https://user-images.githubusercontent.com/84853324/187251961-7eae10e5-bc04-4375-94da-49680654e4c9.png) |

Number of active time series: 73k

Memory usage: 550 MB

Number of active time series has been reduced from 150k to 73k ( 50% reduction) and memory consumption has be reduced from 1GB to 550 MB (50% reduction)


## Upgrade Linkerd to version 2.12

Upgrade Linkerd to the latest stable version, 2.12, released in Aug. See this [linkerd announcement](https://buoyant.io/blog/announcing-linkerd-2-12).

New features of release 2.12:
- Per-route polices
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) support
- Access logging

Installation procedure in this release is completely different to previous releases.


## Ansible Playbooks Improvements

### Encrypt passwords and keys used in playbooks with Ansible Vault

Encrypt all passwords/keys that previously were stored in plain-text within ansible variables. [Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html) is used.


Solution implemented:

- Include all secrets, keys in a specific var yaml file: `vautl.yml` located in `vars` directory.

  ```yml
  ---
  # Encrypted variables - Ansible Vault
  vault:
    # SAN
    san:
      iscsi:
        node_pass: s1cret0
        password_mutual: 0tr0s1cret0
    # K3s secrets
    k3s:
      k3s_token: s1cret0
    # traefik secrets
    traefik:
      basic_auth_passwd: s1cret0
    # Minio S3 secrets
    minio:
      root_password: supers1cret0
      longhorn_key: supers1cret0
      velero_key: supers1cret0
      restic_key: supers1cret0
    # elastic search
    elasticsearch:
      admin_password: s1cret0
    # Fluentd
    fluentd:
      shared_key: s1cret0
    # Grafana
    grafana:
      admin_password: s1cret0
  ```

- Encrypt the file with Ansible vault

  ```shell
  ansible-vault encrypt vault.yml
  ```
   
  Provide ansible vault password to encrypt the file.

  The file can be decrypted using the following command

  ```shell
  ansible-vault decrypt vault.yml
  ```

- Reference the vault variables in playbooks, group_vars, etc.

  For example in: k3s_cluster group variables.
  
  ```yml
  # k3s shared token
  k3s_token: "{{ vault.k3s.k3s_token }}"
  ```

  All referenced variables that are encrypted by ansible vault belong to `vault` yaml dictionary, so they can be clearly identified and their values located in `vault.yml` file.

- Include task to load vault variables file in each playbook's pre-task section:

  ```yml
  - name: my_playbook
    hosts: my_server
    pre_tasks:
      - name: Include vault variables
        include_vars: "vars/vault.yml"
        tags: ["always"]
    roles:
    ....
   ```

- Execute ansible playbooks with `--ask-vault-pass` argument, so the password used to encrypt vault file can be provided when starting the playbook.

  ```shell
  ansible-playbook my-playbook.yml --ask-vault-pass
  ```

### Automatic provision of Prometheus Rules from yaml files

Automation of creation of `PrometheusRule` resources, used by PrometheusOperator, to configure Prometheus rules. Individual rules, defined as yaml files.

Functionality for automatically provision Grafana Dashboards, json files, located within a directory (`dashboards`) has been replicated. Prometheus rules, in yaml format, located in `rules` directory will be used to create `PrometheusRule` objects.

## Upgrade software components to latest stable version


| Type | Software | Latest Version tested | Notes |
|-----------| ------- |-------|----|
| OS | Ubuntu | 20.04.3 | OS need to be tweaked for Raspberry PI when booting from external USB  |
| Control | Ansible | 2.12.1  | |
| Control | cloud-init | 21.4 | version pre-integrated into Ubuntu 20.04 |
| Kubernetes | K3S | v1.24.6 | K3S version|
| Kubernetes | Helm | v3.6.3 ||
| Metrics | Kubernetes Metrics Server | v0.5.2 | version pre-integrated into K3S |
| Computing | containerd | v1.6.8-k3s1 | version pre-integrated into K3S |
| Networking | Flannel | v0.19.2 | version pre-integrated into K3S |
| Networking | CoreDNS | v1.9.1 | version pre-integrated into K3S |
| Networking | Metal LB | v0.13.5 | Helm chart version:  metallb-0.13.5 |
| Service Mesh | Linkerd | v2.12.1 | Helm chart version: linkerd-control-plane-1.9.3 |
| Service Proxy | Traefik | v2.9.1 | Helm chart: traefik-13.0.0  |
| Storage | Longhorn | v1.3.1 | Helm chart version: longhorn-1.3.1 |
| SSL Certificates | Certmanager | v1.9.1 | Helm chart version: cert-manager-v1.9.1  |
| Logging | ECK Operator |  2.4.0 | Helm chart version: eck-operator-2.4.0 |
| Logging | Elastic Search | 8.1.2 | Deployed with ECK Operator |
| Logging | Kibana | 8.1.2 | Deployed with ECK Operator |
| Logging | Fluentbit | 1.9.9 | Helm chart version: fluent-bit-0.20.9 |
| Logging | Fluentd | 1.15.2 | Helm chart version: 0.3.9. [Custom docker image](https://github.com/ricsanfre/fluentd-aggregator) from official v1.15.2|
| Monitoring | Kube Prometheus Stack | 0.60.1 | Helm chart version: kube-prometheus-stack-41.0.0 |
| Monitoring | Prometheus Operator | 0.59.2 | Installed by Kube Prometheus Stack. Helm chart version: kube-prometheus-stack-41.0.0   |
| Monitoring | Prometheus | 2.39 | Installed by Kube Prometheus Stack. Helm chart version: kube-prometheus-stack-41.0.0 |
| Monitoring | AlertManager | 0.24 | Installed by Kube Prometheus Stack. Helm chart version: kube-prometheus-stack-41.0.0 |
| Monitoring | Grafana | 9.1.7 | Helm chart version grafana-6.32.10. Installed as dependency of Kube Prometheus Stack chart. Helm chart version: kube-prometheus-stack-41.0.0 |
| Monitoring | Prometheus Node Exporter | 1.3.1 | Helm chart version: prometheus-node-exporter-3.3.1. Installed as dependency of Kube Prometheus Stack chart. Helm chart version: kube-prometheus-stack-41.0.0 |
| Monitoring | Prometheus Elasticsearch Exporter | 1.5.0 | Helm chart version: prometheus-elasticsearch-exporter-4.15.0 |
| Backup | Minio | RELEASE.2022-09-22T18-57-27Z | |
| Backup | Restic | 0.12.1 | |
| Backup | Velero | 1.9.2 | Helm chart version: velero-2.31.9 |
{: .table }


## Release v1.5.0 Notes

Upgrade backup service adding Kubernetes CSI Snapshot feature, Prometheus memory optimization removing K3S duplicate metrics, enabling Let's Encrypt TLS certificates, and upgrading Linkerd to release 2.12.

### Release Scope:

  - Use of Let's Encrypt TLS certificates
    - Certmanager configuration of Let's Encrypt support. ACME DNS01 challenge provider
    - Certbot deployment
    - IONOS DNS provider integration
  - Upgrade backup service adding CSI Snapshot support
    - Enable Kubernetes CSI Snapshot feature, installing external snapshot controller.
    - Configure Longhorn CSI Snapshots support
    - Configure Velero CSI Snapshot support
  - Prometheus memory footprint optimization
    - Removing of duplicate metrics coming from K3S endpoints.
  - Upgrade Linkerd to version 2.12
  - Ansible Playbooks improvements
     - Encrypt passwords and keys used in playbooks with Ansible Vault
     - Automatic provsion of Prometheus Rules from yaml files.
   


