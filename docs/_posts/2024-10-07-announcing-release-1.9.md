---
layout: post
title:  Kubernetes Pi Cluster relase v1.9
date:   2024-10-07
author: ricsanfre
description: PiCluster News - announcing release v1.9
---


Today I am pleased to announce the nineth release of Kubernetes Pi Cluster project (v1.9). 

Main features/enhancements of this release are:


## GitOps tool replacement: from ArgoCD to FluxCD

Migrate current GitOps solution, based on ArgoCd, to [FluxCD](https://fluxcd.io/).

Main reasons for this migration:

- FluxCd native support of Helm. 
  
  ArgoCD does not uses Helm to deploy applications, instead `helm template` command is used to generate the manifest files to be applied to the cluster. The engine used by Argo CD for applying manifests to the cluster, is not always fully compatible with all Helm possible configurations (hooks, lookups, random password) causing out-of-sync situations.

  FluxCD uses `helm` command to deploy Helm Charts, so Helm charts installed in this way support all the Helm-functions. Also it eases the debugging process, because `helm` cli tool can be used to see installed packages and configuration applied.

- Dependencies Definition support and improve performance in Bootstrap process. 
  
  ArgoCD does not support application dependencies definition, only synchronization waves can be defined, so applications can be allocated to one of the syncrhonization waves, so some kind of boostrapping order can be specify. The problem with this approach is that one synchronization wave cannot start till the previous one has ended succesfully, making the full process take longer times. 
  
  FluxCD support the definition of dependencies between applications so the cluster can be bootstrapped in order. Each application start its deployment as soon as all its dependencies are already synchronized, improving the time required to make a full cluster deployment.
  
- Avoid definition of extra-configuration in the manifest files to fix neverending out-of-sync ArgoCD issues. Due to how Argo CD drift assesment logic certain not mandatory fields or server assigned fields are marked as out-of-synch and they have to be configured to be ignored during the sync process.


Cluster bootstrap process using Ansible playbook has been updated to use FluxCD instead of ArgoCD

Git repo structure to store cluster configuration has been restructured and all applications have been repackaged, so FluxCD resources can be used, and advance Kustomize options (like variants and components) can be used so same set of manifest files can be used for different clusters environemnts.

See further details in ["GitOps (FluxCD)"](/docs/fluxcd/)


## Kuberentes CNI replacement: from Flannel to Cilium

Migrate K3s default Kubernetes CNI, Flannel, to Cilium.

Cilium CNI is deployed in the cluster as a replacement for the following networking components of in the cluster

- Flannel CNI, installed by default by K3S, which uses an VXLAN overlay as networking protocol. Cilium CNI networking using eBPF technology.

- Kube-proxy, so eBPF based can be used to increase performance.

- Metal-LB, load balancer. MetalLB was used for LoadBalancer IP Address Management (LB-IPAM) and L2 announcements for Address Resolution Protocol (ARP) requests over the local network. 

  Cilium 1.13 introduced LB-IPAM support and 1.14 added L2 announcement capabilities, making possible to replace MetalLB in my homelab. My homelab does not have a BGP router and so new L2 aware functionality can be used.

Main reasons for this migration:

- Inrease network performance. Cilium is a high performance CNI using eBPF Kernel technology. Flannel overlay network (VXLAN) may add some overhead that could slightly increase latency compared to Cilium.
- Simplify the networking architecture removing some of the components (kube-proxy and Metal LB)
- Improve security. 
  - Support for [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/). Flannel does not support it.
  - Cilium extends Kubernetes Network Policies adding support for application-aware network policies
- Cilium's observabilities capabilities provides network visibility. Hubble UI


See further details in ["Cilium (Kubernetes CNI)"](/docs/cilium/)

## Service Mesh replacement: from Linkerd to Istio

Migrate current service mesh solution, based on Linkerd, to Istio Ambient Mode (sidecar-less)

I have been testing and using [Linkerd](https://linkerd.io/) as Service Mesh solution for my cluster since relase 1.3 (April 2022).

I wanted to use an opensource solution for the cluster and Istio and Linkerd were assessed since both are CNCF graduated projects. 
Main reasons for selecting Linkerd over [Istio](https://istio.io/) were:

- ARM64 architecture support. It was important since my cluster was mainly built using Raspberry PIs. Istio did not support ARM architectures at that time.
- Better performance and reduced memory/cpu footprint. Linkerd Proxy vs Istio's Envoy Proxy
  
  Linkerd uses its own implementation of the communications proxy, a sidecar container that need to be deployed with any Pod as to intercept all inbound/outbound traffic. Instead of using a generic purpose proxy ([Envoy proxy](https://www.envoyproxy.io/)) used by others service mesh implementations (Istio, Consul), a specifc proxy tailored only to cover Kubernetes communications has been developed. Covering just Kubernetes scenario, allows Linkerd proxy to be a simpler, lighter, faster and more secure proxy.

  Linkerd ulta-light proxy with a reduced memory/cpu footprint and its better performance makes it more suitable for nodes with reduced computing capabilities like Raspberry Pis.

  As a reference of performance/footprint comparison this is what Linkerd claimed in 2021: [Istio vs Linkerd benchmarking](https://linkerd.io/2021/11/29/linkerd-vs-istio-benchmarks-2021/).

Since the initial evaluation was made:

- In Aug 2022, Istio, introduced ARM64 support in release 1.15. See [istio 1.15 announcement](https://istio.io/latest/news/releases/1.15.x/announcing-1.15/)

- In Feb 2024, Linkerd maintaner, Buyoyant, announced that it would no longer provide stable builds. See [Linkerd 2.15 release announcement](https://linkerd.io/2024/02/21/announcing-linkerd-2.15/#a-new-model-for-stable-releases). That decision prompted CNCF to open a health check on the project.

- Istio is developing a sidecarless architecture, [Ambient mode](https://istio.io/latest/docs/ops/ambient/), which is expected to use a reduced footprint. In March 2024, Istio announced the beta relase of Ambient mode for upcoming 1.22 istio release: See [Istio ambient mode beta release announcement](https://www.cncf.io/blog/2024/03/19/istio-announces-the-beta-release-of-ambient-mode/)

For those reasons, Service Mesh solution in the cluster has been migrated to Istio and Linkerd has be deprecated
 
![istio-sidecar-architecture](/assets/img/istio-architecture-ambient-L4.png)

See details in ["Service Mesh (Istio)"](/docs/istio/)

## Keycloak Database (HA configuration and backup)

Upgrade Keycloak deployment to use an PosgreSQL database in HA, using CloudNative-PG instead of Bitnami's embedded chart. 

[CloudNative-PG](https://cloudnative-pg.io/) provides a Kubernetes operator that covers the full lifecycle of a highly available PostgreSQL database cluster with a primary/standby architecture, using native streaming replication.

Deploy  so PosgreSQL databases can be deployed in a declarative way

It also supports the automation of database backup using an external S3 service.

See further details in ["Databases"](/docs/databases/) and ["Keycloak installation- Alternative installation using external database"](/docs/sso/#alternative-installation-using-external-database)

## Release v1.9.0 Notes

Cluster Upgrade to use Cilium CNI, as cluster networking solution, Istio, as Service Mesh solution, and Flux CD, as GitOps solution.

### Release Scope:

- Migrate GitOps solution from ArgoCD to FluxCD
  - Upgrade cluster bootstrap process to use FluxCD instead of ArgoCD
  - Re-package all kubernetes application to use FluxCD specific resources
  - Use advance Kustomize options (variants and componets) to have a reusable set of configurations


- Kubernetes CNI migration from Flannel to Cilium
  - Install K3s disabling installation of embedded Flannel CNI.
  - Replace cluster's load balancer, based on Metal LB by Cilium L4 load balancer capabilty.
  - Configure Cilium to replace `kube-proxy` component. That means to replace kube-proxy’s iptables based routing by [eBFP](https://ebpf.io/) technology.

  
- Migrate Service Mesh solution from Linkerd to Istio
  - Deploy Istio sidecar-less ambient mode
  - Integrate Istio with Cilium CNI
  - Deploy Istio's observability solution, [Kiali](https://kiali.io/)
  - Remove Likerd specific configuration
  
- Keycloak Database (HA and backup)
  - Deploy [CloudNative-PG](https://cloudnative-pg.io/) operator
  - Define declartive Keycloak cluster database configuration in HA
  - Configure backup of the database to external backup service (s3)
  - Renconfigure Keycloak deployment to use this external DB instead of embedded posgreSQL database (Bitnami's posgreSQL chart)

