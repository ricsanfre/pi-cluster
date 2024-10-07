---
title: Metrics Server
permalink: /docs/metrics-server/
description: How to install Metric Server basic Kubernetes service
last_modified_at: "06-10-2024"
---

## What is Metrics-Server?

[Metrics-Server](https://github.com/kubernetes-sigs/metrics-server) is a scalable, efficient source of container resource metrics for Kubernetes built-in autoscaling pipelines.

Metrics Server collects resource metrics from Kubelets and exposes them in Kubernetes apiserver through [Metrics API](https://github.com/kubernetes/metrics) for use by [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) and [Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler/). Metrics API can also be accessed by `kubectl top`, making it easier to debug autoscaling pipelines.


## How does it works?


<pre class="mermaid">
flowchart RL
  subgraph cluster[Cluster]
    direction RL
    S[<br><br>]
    A[Metrics-<br>Server]
    subgraph B[Nodes]
      direction TB
      D[cAdvisor] --> C[kubelet]
      E[Container<br>runtime] --> D
      E1[Container<br>runtime] --> D
      P[pod data] -.- C
    end
    L[API<br>server]
    W[HPA]
    C ---->|node level<br>resource metrics| A -->|metrics<br>API| L --> W
  end
L ---> K[kubectl<br>top]
classDef box fill:#fff,stroke:#000,stroke-width:1px,color:#000;
class W,B,P,K,cluster,D,E,E1 box
classDef spacewhite fill:#ffffff,stroke:#fff,stroke-width:0px,color:#000
class S spacewhite
classDef k8s fill:#326ce5,stroke:#fff,stroke-width:1px,color:#fff;
class A,L,C k8s
</pre>
Image reference[^1].


metrics-server discovers all nodes on the cluster and queries each node's [kubelet](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/) for CPU and memory usage.

Kubelet acts as a bridge between the Kubernetes master and the nodes, managing the pods and containers running on a machine. The kubelet translates each pod into its constituent containers and fetches individual container usage statistics from the container runtime through the container runtime interface.

When using a container runtime that uses Linux cgroups and namespaces to implement containers, and the container runtime does not publish usage statistics, then the kubelet can look up those statistics directly (using code from [cAdvisor](https://github.com/google/cadvisor)).

Kubelet exposes the aggregated pod resource usage statistics through the metrics-server Resource Metrics API. This API is served at `/metrics/resource/v1beta1` on the kubelet's authenticated and read-only ports.

[^1]: https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/


## Metric-Server as K3s add-on

K3s install by default Metric-server using a set of manifest files, as add-on.

K3s Embedded Metric server installation. It can be disable, using k3s installation option `--disable metrics-server`, and instead, it manually installed it using Helm chart, so version installed and configuration options can be better controlled

## Installation

Using [Metrics-Server Helm Chart](https://github.com/kubernetes-sigs/metrics-server/tree/master/charts/metrics-server)

- Add Git repo

  ```shell
  helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
  ```

- Install helm chart in `kube-system` namespace
  ```shell
  helm upgrade --install metrics-server metrics-server/metrics-server
