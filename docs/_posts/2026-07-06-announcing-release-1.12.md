---
layout: post
title:  Kubernetes Pi Cluster release v1.12
date:   2026-07-06
author: ricsanfre
description: PiCluster News - announcing release v1.12
---

Today I am pleased to announce the twelfth release of Kubernetes Pi Cluster project (v1.12).

Main features/enhancements of this release are:


## Ansible Runner Refactoring

The Ansible execution environment has been completely refactored to support a dual execution mode: Docker-based (default) and local UV-based.

Both modes share the same `ansible.cfg`, inventory, playbooks, and Galaxy requirements, with execution mode controlled by the `ANSIBLE_RUNNER_MODE` environment variable in the `ansible-runner.sh` wrapper script. The local mode uses `uv` for Python dependency management — Python packages are now defined in `ansible/pyproject.toml` with a pinned `uv.lock` for reproducible installs, replacing the previous `requirements.txt` approach. The pip-based dependency workflow has been fully migrated to uv, which brings several advantages: dramatically faster package resolution and installation (10–100× compared to pip), a single lockfile (`uv.lock`) ensuring identical dependency graphs across all environments, and built-in virtual environment management eliminating the need for separate `venv`/`virtualenv` tooling. This provides a lightweight alternative to the Docker-based runner for quick iteration and local lint/syntax loops.

The Docker-based runner has been rebuilt using a multi-stage Docker build that copies tools (kubectl, helm, helmfile, tofu) from their official images, ensuring version consistency and simplifying maintenance. Ansible Vault and GPG key generation have been removed from the runner container as part of the migration to HashiCorp Vault for secrets management.

See further details in [Ansible Control Node Instructions](/docs/ansible-instructions/) and the [Ansible Dual Execution Environment design document]({{ site.github.repository_url }}/blob/master/design/ansible-dual-execution-environment.md).


## Migrate Ansible Credentials to HashiCorp Vault

The secrets management strategy has been migrated from Ansible Vault (file-based AES256 encryption with GPG) to HashiCorp Vault for centralized, auditable secrets management.

**Before migration (AS-IS):**

```
┌─────────────────────────────────────────┐
│   Ansible Controller / Localhost        │
├─────────────────────────────────────────┤
│  .vault/vault_pass.sh                   │
│         ↓                               │
│  ansible.cfg: vault_password_file=...   │
│         ↓                               │
│  vars/vault.yml (AES256 encrypted)      │
│         ↓                               │
│  Playbooks include encrypted vars       │
└─────────────────────────────────────────┘
```

Secrets lived as encrypted files in the repository, decrypted at runtime via a GPG-based password script, with no centralized audit trail or lifecycle management.

**After migration (TO-BE):**

```
┌─────────────────────────────────────────┐
│   HashiCorp Vault Server                │
│   (Already deployed on vault host)      │
│                                         │
│   KV Secrets Engine (v2):               │
│   - secret/ansible/*                    │
│   - secret/bind9/*                      │
│   - secret/minio/*                      │
│   - secret/kubernetes/*                 │
│   ... etc                               │
└─────────────────────────────────────────┘
         ↑                   ↑
         │ VAULT_TOKEN       │ VAULT_ADDR
         │                   │
┌────────────────────────────────────────┐
│  Ansible Controller / Localhost        │
├────────────────────────────────────────┤
│  Environment Variables:                │
│  - VAULT_ADDR                          │
│  - VAULT_TOKEN                         │
│  - VAULT_CACERT (optional)             │
│                                        │
│  Playbooks use:                        │
│  - community.hashi_vault.kv_get        │
│  - community.hashi_vault.kv_put        │
│  - Jinja2 lookups                      │
└────────────────────────────────────────┘
```

All secrets are stored in HashiCorp Vault's KV Secrets Engine (v2) under structured paths. Ansible playbooks perform on-demand lookups using the `community.hashi_vault` collection, with Vault connection parameters passed directly to modules rather than set as environment variables. A vault environment file (`~/.secrets/vault.env`) is auto-generated during deployment for handoff between orchestration stages.

The external services orchestration flow follows a staged pipeline fully backed by HashiCorp Vault: deploy Vault → configure Vault via OpenTofu → deploy RustFS → configure RustFS via Terraform → load remaining credentials. OpenTofu declaratively manages Vault resources (secrets, policies, roles) from structured JSON/YAML definition files.

Secret naming has been standardized across the entire codebase — Ansible playbooks, Kubernetes ExternalSecret resources, and Terraform Vault resources all follow consistent naming conventions with hyphen-separated keys.

See further details in [Vault Documentation](/docs/vault/) and the [HashiCorp Vault Migration design document]({{ site.github.repository_url }}/blob/master/design/hashicorp-vault-migration.md).


## Ubuntu 24.04 Upgrade

All cluster nodes have been upgraded from Ubuntu 22.04 (Jammy) to Ubuntu 24.04 (Noble Numbat).

The upgrade involved updating cloud-init autoinstall configurations for x86 nodes, updating PXE server boot files for network-based provisioning, and removing the `linux-modules-extra-raspi` package (no longer needed for Raspberry Pi on 24.04). K3s was upgraded to the latest stable release supporting the new kernel and OS.

See further details in [Installing Ubuntu 24.04](/docs/installing-ubuntu/) and [PXE Server Documentation](/docs/pxe-server/).


## HAProxy to Kube-VIP Migration

The cluster's control plane load balancer has been migrated from HAProxy to [Kube-VIP](https://kube-vip.io/), a Kubernetes-native high-availability and load-balancing solution.

Kube-VIP provides a virtual IP (VIP) for the K3s API server using ARP-based leader election, removing the dependency on an external HAProxy instance running on `node1`. This simplifies the cluster architecture: the control plane VIP is now managed within the Kubernetes cluster itself, with automatic failover between control plane nodes.

Kube-VIP is deployed as a FluxCD HelmRelease and its installation is integrated into the K3s installation Ansible playbook. The legacy HAProxy monitoring and dashboards have been decommissioned, and Prometheus monitoring with a dedicated Grafana dashboard has been configured for Kube-VIP.

See further details in [K3s Installation - Kube-VIP](/docs/installing-k3s/) and the [Kube-VIP Monitoring design document]({{ site.github.repository_url }}/blob/master/design/kube-vip-monitoring.md).


## Replace NGINX Ingress Controller with Envoy Gateway

The NGINX Ingress Controller has been fully replaced by [Envoy Gateway](https://gateway.envoyproxy.io/), a Kubernetes Gateway API implementation powered by Envoy Proxy.

The migration was driven by two converging changes in the Kubernetes ecosystem. First, the [NGINX Ingress Controller project was officially retired](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) by the Kubernetes project in November 2025. Second, the legacy Ingress API is no longer receiving new features — the Kubernetes community has standardized on the Gateway API as the recommended solution for exposing services, and all active development now targets Gateway API controllers.

Envoy Gateway embraces the modern Kubernetes Gateway API standard, providing a more flexible and extensible traffic management model compared to the legacy Ingress API. All applications (Bookinfo, Kafka external access, OpenTelemetry demo) have been reconfigured to use Envoy Gateway's HTTPRoute and Gateway resources.

The migration also included the decommissioning of OAuth2 Proxy (replaced by Envoy Gateway's native external auth capabilities), removal of NGINX-specific monitoring dashboards, and configuration of Envoy Gateway's built-in OpenTelemetry integration for distributed tracing of ingress traffic.

See further details in [Envoy Gateway Documentation](/docs/envoy-gateway/).


## OpenTofu Controller

[FluxCD Tofu Controller](https://github.com/weaveworks/tf-controller) has been added to enable GitOps-driven infrastructure-as-code management directly from the Kubernetes cluster.

Tofu Controller is a FluxCD-native controller that manages OpenTofu (and Terraform) resources through Kubernetes CRDs. It allows Terraform configurations stored in Git repositories to be automatically planned and applied, following the same GitOps reconciliation model used by FluxCD for Helm releases and Kustomize resources.

The controller is configured with cross-namespace references enabled, allowing Terraform CRDs in service namespaces to reference GitRepository sources in the `flux-system` namespace.

See further details in [FluxCD - Tofu Controller](/docs/fluxcd/).


## Terraform to Configure External Services

All four services that require day-2 configuration — Vault, RustFS, Elastic Stack, and Keycloak — have been migrated to Terraform (OpenTofu) for infrastructure-as-code management, following a consistent data-driven pattern: resource definitions in structured JSON/YAML files with thin `.tf` configurations that feed providers via `for_each`.

**External services on `node1`** (Vault and RustFS) follow an Ansible-install / Terraform-configure split: Ansible provisions the infrastructure (packages, TLS certs, initialization) while Terraform manages ongoing configuration state with drift detection and audit trails. The five-stage `external_services.yml` pipeline alternates between the two tools — deploy Vault → configure Vault → deploy RustFS → configure RustFS → load credentials.

See further details in the [External Services Terraform Configuration design document]({{ site.github.repository_url }}/blob/master/design/external-services-terraform-configuration.md).

**Internal services on Kubernetes** (Elastic Stack and Keycloak) are installed via Helm and configured via separate Terraform runs triggered by FluxCD's Tofu Controller. Elastic Stack configuration (users, roles, ILM policies, index templates) is managed through `terraform/elastic/`. Keycloak realm configuration (clients, users, groups, identity providers, authentication flows) has been migrated from `keycloak-config-cli` to `terraform/keycloak/`.

See further details in the [Internal Services Terraform Configuration design document]({{ site.github.repository_url }}/blob/master/design/internal-services-terraform-configuration.md), [Elastic Documentation](/docs/elasticsearch/), and [Keycloak Documentation](/docs/sso/).


## Common Redis-Valkey Database Service

A shared [Valkey](https://valkey.io/) database service has been deployed using the official [Valkey Operator](https://github.com/valkey-io/valkey-operator), providing a Redis-compatible datastore for cluster applications.

Valkey is a high-performance, open-source key-value datastore and a drop-in replacement for Redis. The operator manages Valkey clusters in a declarative way, handling deployment, scaling, and failover automatically.

The database tier has been consolidated into a shared `databases` namespace, where Valkey, PostgreSQL (CloudNativePG), and MongoDB operators co-exist. Anti-affinity rules prefer scheduling database workloads on amd64 nodes. Prometheus monitoring is enabled for Valkey clusters, with metrics integrated into the cluster's observability stack.

See further details in [Databases - Valkey](/docs/databases/).


## MinIO Replacement with RustFS

The S3-compatible object storage has been migrated from [MinIO](https://min.io/) to [RustFS](https://rustfs.com/), a ground-up rewrite of object storage infrastructure in Rust.

The migration was driven by the progressive degradation of MinIO's open-source community edition, which made it no longer viable for self-hosted homelab environments:

- **February 2025** — Admin UI removed from the community edition. The console was repurposed as a browser-only object browser.
- **October 2025** — Pre-compiled binary releases discontinued. The community edition became source-code only, with no Docker images or binary packages.
- **April 2026** — MinIO archived its public repository and removed community version documentation from its website.

RustFS provides an S3-compatible API and emulates a robust subset of the MinIO Admin IAM API, making it fully compatible with the existing MinIO Terraform provider (`aminueza/minio`). This compatibility exists because RustFS explicitly emulates two critical API standards: the universal AWS S3 API Schema for bucket operations, and the MinIO Admin REST API IAM subset for user and policy management.

**Terraform resource compatibility with RustFS:**

| Terraform Resource | Compatibility | Reason |
| :--- | :--- | :--- |
| `minio_s3_bucket` | Fully Supported | Handled via universal S3 API layer |
| `minio_iam_user` | Fully Supported | RustFS emulates `/minio/admin/v3/add-user` |
| `minio_iam_policy` | Fully Supported | RustFS emulates `/minio/admin/v3/add-canned-policy` |
| `minio_iam_user_policy_attachment` | Fully Supported | Supported by the RustFS identity engine mapping |
| `minio_server_config_*` | Unsupported | Attempts to alter proprietary MinIO system configurations (`minio.sys`) that do not exist in RustFS |

The migration involved deploying RustFS via Ansible on `node1`, migrating existing bucket data, and updating all references from MinIO to RustFS across documentation, Vault secrets (renamed from `secret/minio/*` to `secret/s3/*`), and service configurations (Vault, Tempo, Loki, Velero backends).

RustFS is deployed as an external service on `node1` together with Vault, maintaining the existing architecture where critical infrastructure services run outside the cluster.

See further details in [RustFS Documentation](/docs/rustfs-baremetal/) and the [RustFS Terraform Compatibility design document]({{ site.github.repository_url }}/blob/master/design/rustfs-terraform-compatibility.md).


## MongoDB Monitoring

Prometheus monitoring has been enabled for the MongoDB clusters managed by the Percona MongoDB Operator.

The MongoDB instances expose metrics through the Percona Monitoring and Management (PMM) agent, which is scraped by Prometheus using a PodMonitor with basic authentication. A Grafana dashboard adapted from the MongoDB Ops Manager dashboard provides visibility into MongoDB cluster health, query performance, replication status, and resource utilization.

Istio PeerAuthentication policies have been configured with PERMISSIVE mode for database metrics ports to allow Prometheus scraping while maintaining mTLS for other traffic.

See further details in [Databases - MongoDB Monitoring](/docs/databases/).


## Kafka Security

Security has been enabled for the Apache Kafka clusters managed by Strimzi Operator.

Kafka brokers are now configured with TLS encryption for client and inter-broker communication, SASL/SCRAM authentication, and ACL-based authorization. Kafka users and ACLs are managed through Strimzi's `KafkaUser` CRDs, with credentials stored in HashiCorp Vault and synchronized to Kubernetes via External Secrets Operator.

Ansible playbooks have been updated to create the necessary Kafka secrets in Vault, and the Kafka external listener has been reconfigured to work with Envoy Gateway for TLS passthrough with SNI-based routing.

See further details in [Kafka Documentation](/docs/kafka/).


## Grafana Operator

The Grafana deployment has been migrated from the Helm-based `grafana/grafana` chart to the [Grafana Operator](https://github.com/grafana/grafana-operator), enabling Kubernetes-native management of Grafana instances and their resources.

The Grafana Operator manages the complete Grafana lifecycle (deployment, configuration, upgrades) through Kubernetes CRDs. Grafana dashboards, datasources, folders, and alerting resources are now defined as native Kubernetes objects (`GrafanaDashboard`, `GrafanaDatasource`, `GrafanaFolder`), enabling true GitOps for observability configuration.

Existing dashboards have been converted to Grafana Operator resources, and Renovate's custom manager configuration has been updated to track dashboard versions with the new resource format. The K3s installation playbook now installs the Grafana Operator CRDs as part of the cluster bootstrap process.

See further details in [Grafana Operator Documentation](/docs/grafana-operator/).


## Observability Solution (OpenTelemetry) Refactoring

The cluster's OpenTelemetry-based observability solution has been comprehensively refactored to implement a unified signal processing architecture.

A dedicated **OpenTelemetry Collector** has been deployed to receive, process, and distribute all three observability signals — metrics, logs, and traces — to their respective backends:

- **Metrics** → Prometheus (via OTLP HTTP exporter)
- **Logs** → Elasticsearch (with proper namespace and service attributes)
- **Traces** → Grafana Tempo (with metrics-generator enabled for span metrics)

The OTEL Collector replaces the previously embedded Tempo collector, providing a centralized pipeline that enriches telemetry data with consistent Kubernetes resource attributes (`service.namespace`, `service.name`, `k8s.*`). Grafana dashboards have been updated to query OTEL-native metrics and log indices.

This refactoring enables true correlation across signals in Grafana: trace-to-log integration via derived fields, span metrics in dashboards, and unified service-level observability.

See further details in [OpenTelemetry Collector Documentation](/docs/opentelemetry-collector/) and [Observability Documentation](/docs/observability/).


## New Observability/Service Mesh Demo Application

A new **E-commerce Demo Application** has been developed to illustrate distributed application architectures in Kubernetes, showcasing how the cluster's platform services work together to provide databases, messaging, authentication, secure communications, and observability.

The application is built with a SpringBoot microservices backend and a React frontend, using a single, consistent language stack with built-in OpenTelemetry instrumentation via the Spring Boot Starter, which automatically instruments HTTP requests, database queries, and messaging systems without code changes. The source code is available at [github.com/ricsanfre/spring-microservices-otel-k8s](https://github.com/ricsanfre/spring-microservices-otel-k8s).

The official [OpenTelemetry Demo](https://opentelemetry.io/docs/demo/) application was evaluated but ultimately not adopted. While it is well-maintained and designed to showcase OpenTelemetry capabilities, it proved unsuitable as a cluster reference application for several reasons. Its polyglot architecture spans multiple programming languages and frameworks, increasing the complexity of consistent instrumentation and making it harder to understand as a cohesive example. More critically, it is not designed as a production-ready application: it lacks any authentication and authorization mechanism — no OAuth2/OIDC integration, no secured access to Kafka brokers or database backends — and its hardcoded service topology cannot be adapted to use the cluster's existing platform services (Kafka, Elasticsearch, Valkey, PostgreSQL) without modifying application code. A custom SpringBoot-based application was chosen instead, providing full control over the architecture, native integration with all cluster platform services, and a realistic production-like security posture.

The new demo illustrates the following platform capabilities:

- **Databases (SQL, NoSQL, in-memory)**: PostgreSQL for transactional data (users, orders), MongoDB for document storage (products, reviews), and Valkey for caching (shopping cart) — all provisioned from the shared `databases` platform namespace.
- **Streaming asynchronous messaging**: Kafka handles event-driven communication between services (order placement triggers notifications and review requests).
- **Authentication and authorization (OAuth2/OIDC)**: Keycloak acts as the IAM solution, providing OAuth2 client credentials and OIDC-based single sign-on for the React frontend, integrated via Spring Security.
- **Secure communications with Service Mesh**: Istio ambient mesh provides transparent mTLS encryption between all 7 microservices (frontend, user, cart, product, order, reviews, and notification), with zero sidecar overhead.
- **Observability with OpenTelemetry**: All services emit OTLP traces, metrics, and logs to the OpenTelemetry Collector, which distributes them to Tempo (traces), Prometheus (metrics), and Elasticsearch (logs). Full OpenTelemetry APM dashboards provide correlated visibility across all signals.

Grafana Tempo has been upgraded and reconfigured with enabled metrics-generator for span metrics, streaming over HTTP, trace-to-log correlation with Loki, and proper resource limits for all components.

See further details in the [E-Commerce Demo Application design document]({{ site.github.repository_url }}/blob/master/design/e-commerce-demo-application.md), [Tracing Documentation](/docs/tracing/), [Observability Documentation](/docs/observability/), and the [application source repository](https://github.com/ricsanfre/spring-microservices-otel-k8s).


## Additional Improvements

- **Helm Repository Refactoring**: All FluxCD HelmRelease resources have been migrated to use Flux `HelmRepository` CRDs referencing OCI-based or HTTP chart repositories, replacing the legacy `HelmChartTemplate` pattern with inline repository URLs.
- **OpenWRT TLS Automation**: TLS certificate deployment to the OpenWRT home router has been automated via an Ansible playbook, using Let's Encrypt certificates managed by Certbot.
- **Istio Ambient Mesh**: Key services have been migrated to Istio's ambient mesh mode, leveraging ztunnel for transparent mTLS without sidecar proxies. Database infrastructure services are configured with PERMISSIVE PeerAuthentication for Prometheus metrics scraping compatibility.
- **Documentation**: New documentation pages added for Envoy Gateway, Grafana Operator, OpenTelemetry Collector, and RustFS. All existing documentation updated to reflect the architecture changes.


## Release v1.12.0 Notes

Major update of the cluster platform: Ansible Runner refactoring, secrets migration to HashiCorp Vault, Ubuntu 24.04 upgrade, ingress migration from NGINX to Envoy Gateway, control plane load balancing with Kube-VIP, MinIO replacement with RustFS, Valkey shared database service, Grafana Operator, OpenTelemetry refactoring, and infrastructure-as-code expansion with OpenTofu Controller and Terraform-based external services configuration.

### Release Scope

- Ansible Runner Refactoring
    - Dual execution environment: Docker-based and local UV-based
    - Migrate Python dependency management from pip to uv (10–100× faster, reproducible lockfile)
    - Wrapper script for consistent command interface across environments
    - Multi-stage Docker build with tool versioning from official images
    - Removal of Ansible Vault and GPG key management from the runner
- Migrate Ansible Credentials to HashiCorp Vault
    - Replace file-based Ansible Vault encryption with on-demand HashiCorp Vault lookups
    - Standardize secret naming conventions across Ansible, Kubernetes, and Terraform
    - Integrate Terraform (OpenTofu) for Vault and MinIO configuration
- Ubuntu 24.04 Upgrade
    - Upgrade all cluster nodes from Ubuntu 22.04 to 24.04 (Noble Numbat)
    - Update cloud-init, PXE boot, and K3s configurations for Noble compatibility
- HAProxy to Kube-VIP Migration
    - Replace HAProxy load balancer with Kube-VIP for K3s API server VIP
    - Deploy via FluxCD HelmRelease with K3s installation integration
    - Prometheus monitoring and Grafana dashboard for Kube-VIP
- Replace NGINX Ingress Controller with Envoy Gateway
    - Migrate from retired NGINX Ingress to Envoy Gateway (Kubernetes Gateway API)
    - Decommission OAuth2 Proxy and NGINX-specific monitoring
    - Reconfigure all applications (Bookinfo, Kafka, OTEL demo) for Gateway API
- OpenTofu Controller
    - Deploy FluxCD Tofu Controller for GitOps-driven infrastructure-as-code
    - Cross-namespace references for Terraform CRDs
- Terraform to Configure External Services
    - Elastic Stack: users, roles, ILM policies, index templates via Terraform
    - Keycloak: realm configuration via Terraform, replacing keycloak-config-cli
    - Data-driven pattern with structured resource definition files
- Common Redis-Valkey Database Service
    - Deploy Valkey Operator for shared Redis-compatible datastore
    - Consolidate database operators in shared `databases` namespace
    - Prometheus monitoring and anti-affinity scheduling rules
- MinIO Replacement with RustFS
    - Migrate from MinIO to RustFS S3-compatible object storage
    - Maintain Terraform provider compatibility (aminueza/minio)
    - Update Vault secrets, service backends, and documentation
- MongoDB Monitoring
    - Enable Prometheus monitoring for MongoDB via Percona PMM agent
    - Adapted Grafana dashboard from MongoDB Ops Manager
    - Istio PeerAuthentication for metrics scraping compatibility
- Kafka Security
    - Enable TLS encryption, SASL/SCRAM authentication, and ACL authorization
    - Manage credentials via Vault + External Secrets Operator
    - Reconfigure external listener for Envoy Gateway TLS passthrough
- Grafana Operator
    - Migrate from Helm-based Grafana to Grafana Operator
    - Kubernetes CRDs for Dashboards, Datasources, and Folders
    - GitOps-native observability configuration
- Observability Solution (OpenTelemetry) Refactoring
    - Deploy dedicated OTEL Collector for unified signal processing
    - Metrics → Prometheus, Logs → Elasticsearch, Traces → Tempo
    - Trace-to-log correlation, span metrics, service-level observability
- New Observability/Service Mesh Demo Application
    - Custom SpringBoot + React e-commerce app (7 microservices) replacing official OpenTelemetry Demo
    - Illustrates distributed architecture: databases (PostgreSQL, MongoDB, Valkey), Kafka messaging, Keycloak OAuth2/OIDC, Istio ambient mesh, OpenTelemetry observability
    - Upgrade and reconfigure Tempo (metrics-generator, HTTP streaming, resource limits)
- Additional Improvements
    - Helm Repository Refactoring
    - OpenWRT TLS Automation
    - Istio Ambient Mesh enhancement
    - New documentation for Envoy Gateway, Grafana Operator, OTEL Collector, and RustFS
