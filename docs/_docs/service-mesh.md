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

  The `linkerd` binary is installed under `${HOME}/.linkerd2` folder.

  {{site.data.alerts.end}}


- Step 2: Update $PATH variable

  ```shell
  export PATH=$PATH:${HOME}/.linkerd2/bin"

  ```

- Step 3: Validate `linkerd` cli installation

  ```shell
  linkerd version

  ```

  The command shows the CLI version and also **Server version: unavailable** indicates that linkerd can be installed.

  Output of the commad should be like:

  ```shell
  Client version: stable-2.11.1
  Server version: unavailable
  ```

- Step 4: Validate that Linkerd can be installed

  ```shell
  linkerd check --pre
  ```

  This command validate kuberentes cluster installation

  Output of the command is like:

  ```shell
  Linkerd core checks
  ===================

  kubernetes-api
  --------------
  √ can initialize the client
  √ can query the Kubernetes API

  kubernetes-version
  ------------------
  √ is running the minimum Kubernetes API version
  √ is running the minimum kubectl version

  pre-kubernetes-setup
  --------------------
  √ control plane namespace does not already exist
  √ can create non-namespaced resources
  √ can create ServiceAccounts
  √ can create Services
  √ can create Deployments
  √ can create CronJobs
  √ can create ConfigMaps
  √ can create Secrets
  √ can read Secrets
  √ can read extension-apiserver-authentication configmap
  √ no clock skew detected

  linkerd-version
  ---------------
  √ can determine the latest version
  √ cli is up-to-date

  Status check results are √
  ```

- Step 5: Install linkerd

  ```shell
  linkerd install | kubectl apply -f -

  ```

- Step 6: Check installation

  ```shell
  linkerd check

  ```  
  
  This command checks linkerd installation

  Output of the command is like:

  ```shell
    Linkerd core checks
  ===================

  kubernetes-api
  --------------
  √ can initialize the client
  √ can query the Kubernetes API

  kubernetes-version
  ------------------
  √ is running the minimum Kubernetes API version
  √ is running the minimum kubectl version

  linkerd-existence
  -----------------
  √ 'linkerd-config' config map exists
  √ heartbeat ServiceAccount exist
  √ control plane replica sets are ready
  √ no unschedulable pods
  √ control plane pods are ready
  √ cluster networks contains all node podCIDRs

  linkerd-config
  --------------
  √ control plane Namespace exists
  √ control plane ClusterRoles exist
  √ control plane ClusterRoleBindings exist
  √ control plane ServiceAccounts exist
  √ control plane CustomResourceDefinitions exist
  √ control plane MutatingWebhookConfigurations exist
  √ control plane ValidatingWebhookConfigurations exist

  linkerd-identity
  ----------------
  √ certificate config is valid
  √ trust anchors are using supported crypto algorithm
  √ trust anchors are within their validity period
  √ trust anchors are valid for at least 60 days
  √ issuer cert is using supported crypto algorithm
  √ issuer cert is within its validity period
  √ issuer cert is valid for at least 60 days
  √ issuer cert is issued by the trust anchor

  linkerd-webhooks-and-apisvc-tls
  -------------------------------
  √ proxy-injector webhook has valid cert
  √ proxy-injector cert is valid for at least 60 days
  √ sp-validator webhook has valid cert
  √ sp-validator cert is valid for at least 60 days
  √ policy-validator webhook has valid cert
  √ policy-validator cert is valid for at least 60 days

  linkerd-version
  ---------------
  √ can determine the latest version
  √ cli is up-to-date

  control-plane-version
  ---------------------
  √ can retrieve the control plane version
  √ control plane is up-to-date
  √ control plane and cli versions match

  linkerd-control-plane-proxy
  ---------------------------
  √ control plane proxies are healthy
  √ control plane proxies are up-to-date
  √ control plane proxies and cli versions match

  Status check results are √

  ```