---
title: Service Mesh (Linkerd)
permalink: /docs/service-mesh/
---


## Why a Service Mesh

Introduce Service Mesh architecture to add observability, traffic management, and security capabilities to internal communications within the cluster.

[Linkerd](https://linkerd.io/) will be deployed in the cluster as a Service Mesh implementation.


## Why Linkerd and not Istio

Most known Service Mesh implementation, [Istio](https://istio.io), is not currently supporting ARM64 architecture.

[Linkerd](https://linkerd.io/), which is a CNCF graduated project, does support ARM64 architectures since release 2.9 (see [linkerd 2.9 announcement](https://linkerd.io/2020/11/09/announcing-linkerd-2.9/).

Moreover,instead of using [Envoy proxy](https://www.envoyproxy.io/), sidecar container  to be deployed with any Pod as communication proxy, Linkerd uses its own ulta-light proxy which reduces the required resource footprint (cpu, memory) and makes it more suitable for Raspberry Pis.


## Linkerd installation

Linkerd installation using `linkerd` CLI.


- Step 1: Download `linkerd` CLI command

  ```shell
   
  curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh

  ```

  This command will install latest `linkerd` stable release.

  {{site.data.alerts.note}}

  The command above downloads the latest stable release of Linkerd available at [github linkerd repo](https://github.com/linkerd/linkerd/releases/download/)

  {{site.data.alerts.end}}

