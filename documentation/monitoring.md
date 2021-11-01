# Centralized Monitoring with Prometheus

Prometheus stack installation for kubernetes using Prometheus Operator can be streamlined using [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus) project maintaned by the community.

This project collects Kubernetes manifests, Grafana dashboards, and Prometheus rules combined with documentation and scripts to provide easy to operate end-to-end Kubernetes cluster monitoring with Prometheus using the Prometheus Operator.

Components included in this package:

- The Prometheus Operator
- Highly available Prometheus
- Highly available Alertmanager
- Prometheus node-exporter
- Prometheus Adapter for Kubernetes Metrics APIs
- kube-state-metrics
- Grafana

This stack is meant for cluster monitoring, so it is pre-configured to collect metrics from all Kubernetes components.

## Kube-Prometheus Stack installation

Kube-prometheus stack can be installed using helm [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) maintaind by the community

- Step 1: Add the Elastic repository:
    ```
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    ```
- Step2: Fetch the latest charts from the repository:
    ```
    helm repo update
    ```
- Step 3: Create namespace
    ```
    kubectl create namespace monitoring
    ```
- Step 3: Install kube-Prometheus-stack in the monitoring namespace
    ```
    helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring
    ```
