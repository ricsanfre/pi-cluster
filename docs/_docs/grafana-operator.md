---
title: Observability Visualization (Grafana Operator)
permalink: /docs/grafana-operator/
description: How Grafana is installed and configured in Pi Cluster using Grafana Operator.
last_modified_at: "05-04-2026"
---

[Grafana](https://grafana.com/oss/grafana/) is the visualization layer of the observability platform used in Pi Cluster. It connects to the telemetry backends deployed in the cluster: Prometheus for metrics, Loki for logs, and Tempo for traces.

This document describes the current Grafana deployment model used in this repository: Grafana is installed and managed through [Grafana Operator](https://grafana.github.io/grafana-operator/).


## Why Grafana Operator

Using Grafana Operator makes Grafana management more Kubernetes-native than the classic Helm-only approach.

Main benefits:

-   Grafana itself is managed as a Kubernetes custom resource (`Grafana`) instead of embedding most runtime configuration in a single Helm values file.
-   Datasources, folders, and dashboards are managed as first-class resources (`GrafanaDatasource`, `GrafanaFolder`, `GrafanaDashboard`).
-   Configuration is easier to decompose into reusable components for GitOps overlays.
-   The operator continuously reconciles Grafana resources, which fits better with FluxCD/Kustomize workflows.
-   Dashboards can be managed natively, imported from Grafana.com, or bridged from third-party Helm chart ConfigMaps without relying on Grafana sidecars.

In this repository, the operator-based deployment is split into two concerns:

-   `kubernetes/platform/grafana/operator`: installs the Grafana Operator Helm chart.
-   `kubernetes/platform/grafana/instance`: defines the Grafana instance and its related Kubernetes custom resources.

The older Helm-centric deployment is still documented in [Observability Visualization (Grafana)](/docs/grafana/). This page documents the operator-based model currently used in the cluster.


## Installation

The installation is split in two stages:

-   Install the Grafana Operator.
-   Create and configure the Grafana instance managed by the operator.


### Install the Operator

The operator is installed from the upstream Helm chart `oci://ghcr.io/grafana/helm-charts/grafana-operator`.

In this repository the operator is deployed using FluxCD with these base resources:

-   `OCIRepository` pointing to the chart.
-   `HelmRelease` installing the operator in namespace `grafana`.
-   Base Helm values enabling operator metrics and its dashboard.

Current base definition:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: grafana-operator
spec:
  interval: 1h
  url: oci://ghcr.io/grafana/helm-charts/grafana-operator
  ref:
    tag: 5.22.2
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: grafana-operator
spec:
  chartRef:
    kind: OCIRepository
    name: grafana-operator
  releaseName: grafana-operator
  targetNamespace: grafana
```

Base Helm values:

```yaml
serviceMonitor:
  enabled: true
  interval: 30s
dashboard:
  enabled: true
```

If you want to install the operator manually with Helm:

-   Step 1: Create namespace

    ```shell
    kubectl create namespace grafana
    ```

-   Step 2: Install the operator chart

    ```shell
    helm upgrade --install grafana-operator \
      oci://ghcr.io/grafana/helm-charts/grafana-operator \
      --namespace grafana \
      --version 5.22.2
    ```

-   Step 3: Confirm the deployment succeeded

    ```shell
    kubectl -n grafana get pods
    kubectl -n grafana get crd | grep grafana.integreatly.org
    ```


### Install the Grafana Instance

Once the operator is installed, Grafana is created through a `Grafana` custom resource.

Base instance manifest used in this repository:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: Grafana
metadata:
  name: grafana
  labels:
    dashboards: grafana
spec:
  version: 12.3.1
  disableDefaultAdminSecret: true
  config:
    analytics:
      check_for_updates: "false"
      check_for_plugin_updates: "false"
      feedback_links_enabled: "false"
      reporting_enabled: "false"
    log:
      mode: console
    metrics:
      enabled: "true"
  deployment:
    spec:
      template:
        spec:
          containers:
            - name: grafana
              env:
                - name: GF_SECURITY_ADMIN_USER
                  valueFrom:
                    secretKeyRef:
                      name: grafana
                      key: admin-user
                - name: GF_SECURITY_ADMIN_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: grafana
                      key: admin-password
```

Important aspects of this configuration:

-   `dashboards: grafana` label is used by `GrafanaDatasource`, `GrafanaFolder`, and `GrafanaDashboard` resources to select the Grafana instance.
-   `disableDefaultAdminSecret: true` disables the operator-generated admin secret, so credentials can be sourced from an existing Kubernetes Secret.
-   Grafana admin credentials are injected as container environment variables from secret `grafana`.


### GitOps Installation

In this repository the production deployment is assembled through Kustomize overlays and components.

Operator application:

```text
kubernetes/platform/grafana/operator/
  base/
  overlays/prod/
```

Grafana instance application:

```text
kubernetes/platform/grafana/instance/
  base/
  components/
    persistence/
    route/
    sso/
  overlays/prod/
```

The production overlay enables:

-   persistent storage
-   Gateway API route
-   SSO integration

Production overlay:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: grafana

resources:
  - ../../base

components:
  - ../../components/persistence
  - ../../components/route
  - ../../components/sso
```


### Secrets Management

For GitOps deployments, secrets should not be hardcoded in manifests.

In this repository Grafana admin credentials are synchronized from Vault using External Secrets:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: grafana-externalsecret
spec:
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: grafana
  data:
  - secretKey: admin-user
    remoteRef:
      key: grafana/admin
      property: username
  - secretKey: admin-password
    remoteRef:
      key: grafana/admin
      property: password
```

This creates the `grafana` Secret consumed by the `Grafana` resource.


## Configuration


### Gateway API Configuration

Grafana is exposed in Pi Cluster through Kubernetes Gateway API and Envoy Gateway using a dedicated hostname.


{{site.data.alerts.note}}

Before enabling Gateway API based routing for Grafana, Gateway API CRDs and Envoy Gateway must already be installed in the cluster.

For installing and configuring Envoy Gateway, follow the instructions in ["Envoy Gateway - Installation"](/docs/envoy-gateway/#installation).

For automatic DNS management, External-DNS must also be configured with Gateway API route sources so the `HTTPRoute` hostname can be published automatically. See [DNS (CoreDNS and External-DNS) - Gateway API support](/docs/kube-dns/#gateway-api-support).

{{site.data.alerts.end}}


#### Serving Grafana with Envoy Gateway

With Grafana Operator the route is configured directly in the `Grafana` resource using `spec.httpRoute`.

Route patch used in this repository:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: Grafana
metadata:
  name: grafana
spec:
  httpRoute:
    spec:
      hostnames:
        - grafana.${CLUSTER_DOMAIN}
      parentRefs:
        - name: public-gateway
          namespace: envoy-gateway-system
      rules:
        - backendRefs:
            - name: grafana-service
              port: 3000
          matches:
            - path:
                type: PathPrefix
                value: /
  config:
    server:
      domain: grafana.${CLUSTER_DOMAIN}
      root_url: https://%(domain)s/
```

With this configuration:

-   Grafana public URL is `https://grafana.${CLUSTER_DOMAIN}/`
-   Envoy Gateway routes traffic through `HTTPRoute`
-   Grafana keeps its own server configuration aligned with the public hostname


### Provisioning Data Sources

With Grafana Operator, datasources are provisioned using `GrafanaDatasource` custom resources instead of Helm provisioning files or Grafana sidecars.

Example used in this repository for Prometheus:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDatasource
metadata:
  name: prometheus
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  datasource:
    name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://kube-prometheus-stack-prometheus.kube-prom-stack.svc.cluster.local:9090
    isDefault: true
```

The repository defines the following datasources this way:

-   Prometheus
-   Alertmanager
-   Loki
-   Tempo

This approach has two main advantages over the Helm-sidecar model:

-   datasources are declarative Kubernetes resources
-   reconciliation is handled by the operator instead of by filesystem provisioning inside the Grafana pod


### Provisioning Dashboards

With Grafana Operator, dashboards can be managed in several different ways.

Supported patterns used in this repository are:

-   `grafanaCom`: import dashboards from Grafana.com
-   `configMapRef`: import dashboards from existing ConfigMaps generated by third-party Helm charts


#### Operator-managed dashboards from Grafana.com

The operator itself dashboard is imported directly from Grafana.com:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: grafana-operator
spec:
  folder: Grafana
  instanceSelector:
    matchLabels:
      dashboards: grafana
  grafanaCom:
    id: 22785
    revision: 2
```


#### Dashboards imported from ConfigMaps

Some third-party charts still generate dashboards as ConfigMaps. Those dashboards are bridged into Grafana using `GrafanaDashboard.spec.configMapRef`.

Example:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: fluent-bit
spec:
  allowCrossNamespaceImport: true
  instanceSelector:
    matchLabels:
      dashboards: grafana
  datasources:
    - datasourceName: prometheus
      inputName: DS_PROMETHEUS
  folder: Logging
  configMapRef:
    name: fluent-bit-dashboard-fluent-bit
    key: fluent-bit-fluent-bit.json
```

This pattern is used for applications whose Helm charts already publish dashboards as ConfigMaps, such as Fluent Bit, Fluentd, Cilium, Strimzi, and CloudNativePG.


#### Creating K3s-specific Grafana dashboards

For the K3s-specific monitoring stack, this repository also generates dashboards and Prometheus rules from the same monitoring mixins consumed by `kube-prometheus-stack`, as indicated in (/docs/monitoring/#k3s-duplicate-metrics-issue).

The main difference from the legacy Helm-sidecar approach is that dashboards are generated directly as `GrafanaDashboard` resources instead of `ConfigMap` objects labeled for Grafana discovery.

The build files live under `kubernetes/platform/kube-prometheus-stack/k3s-mixins/build` and produce two kinds of output:

-   `GrafanaDashboard` resources for Grafana Operator
-   Prometheus rule manifests generated from the same mixins

The Jsonnet entrypoint defines the mixins to render and converts each generated dashboard into a `GrafanaDashboard` custom resource:

```javascript
# We use helper functions from kube-prometheus to generate dashboards and alerts for Kubernetes.
local addMixin = (import 'kube-prometheus/lib/mixin.libsonnet');

local kubernetesMixin = addMixin({
  name: 'kubernetes',
  dashboardFolder: 'Kubernetes',
  mixin: (import 'kubernetes-mixin/mixin.libsonnet') + {
    _config+:: {
      cadvisorSelector: 'job="kubelet"',
      kubeletSelector: 'job="kubelet"',
      kubeSchedulerSelector: 'job="kubelet"',
      kubeControllerManagerSelector: 'job="kubelet"',
      kubeApiserverSelector: 'job="kubelet"',
      kubeProxySelector: 'job="kubelet"',
      showMultiCluster: false,
    },
  },
});

local nodeExporterMixin = addMixin({
  name: 'node-exporter',
  dashboardFolder: 'General',
  mixin: (import 'node-mixin/mixin.libsonnet') + {
    _config+:: {
      nodeExporterSelector: 'job="node-exporter"',
      showMultiCluster: false,
    },
  },
});

local corednsMixin = addMixin({
  name: 'coredns',
  dashboardFolder: 'DNS',
  mixin: (import 'coredns-mixin/mixin.libsonnet') + {
    _config+:: {
      corednsSelector: 'job="coredns"',
    },
  },
});

local etcdMixin = addMixin({
  name: 'etcd',
  dashboardFolder: 'Kubernetes',
  mixin: (import 'github.com/etcd-io/etcd/contrib/mixin/mixin.libsonnet') + {
    _config+:: {
      clusterLabel: 'cluster',
    },
  },
});

local grafanaMixin = addMixin({
  name: 'grafana',
  dashboardFolder: 'Grafana',
  mixin: (import 'grafana-mixin/mixin.libsonnet') + {
    _config+:: {},
  },
});

local prometheusMixin = addMixin({
  name: 'prometheus',
  dashboardFolder: 'Prometheus',
  mixin: (import 'prometheus/mixin.libsonnet') + {
    _config+:: {
      showMultiCluster: false,
    },
  },
});

local prometheusOperatorMixin = addMixin({
  name: 'prometheus-operator',
  dashboardFolder: 'Prometheus Operator',
  mixin: (import 'prometheus-operator-mixin/mixin.libsonnet') + {
    _config+:: {},
  },
});

local stripJsonExtension(name) =
  local extensionIndex = std.findSubstr('.json', name);
  local n = if std.length(extensionIndex) < 1 then name else std.substr(name, 0, extensionIndex[0]);
  n;

local grafanaDashboardResource(folder, name, json) = {
  apiVersion: 'grafana.integreatly.org/v1beta1',
  kind: 'GrafanaDashboard',
  metadata: {
    name: 'grafana-dashboard-%s' % stripJsonExtension(name),
  },
  spec: {
    allowCrossNamespaceImport: true,
    folder: folder,
    instanceSelector: {
      matchLabels: {
        dashboards: 'grafana',
      },
    },
    json: std.manifestJsonEx(json, '    '),
  },
};

local generateGrafanaDashboardResources(mixin) = if std.objectHas(mixin, 'grafanaDashboards') && mixin.grafanaDashboards != null then {
  ['grafana-dashboard-' + stripJsonExtension(name)]: grafanaDashboardResource(folder, name, mixin.grafanaDashboards[folder][name])
  for folder in std.objectFields(mixin.grafanaDashboards)
  for name in std.objectFields(mixin.grafanaDashboards[folder])
} else {};

local nodeExporterMixinHelmGrafanaDashboards = generateGrafanaDashboardResources(nodeExporterMixin);
local kubernetesMixinHelmGrafanaDashboards = generateGrafanaDashboardResources(kubernetesMixin);
local corednsMixinHelmGrafanaDashboards = generateGrafanaDashboardResources(corednsMixin);
local etcdMixinHelmGrafanaDashboards = generateGrafanaDashboardResources(etcdMixin);
local grafanaMixinHelmGrafanaDashboards = generateGrafanaDashboardResources(grafanaMixin);
local prometheusMixinHelmGrafanaDashboards = generateGrafanaDashboardResources(prometheusMixin);
local prometheusOperatorMixinHelmGrafanaDashboards = generateGrafanaDashboardResources(prometheusOperatorMixin);

local grafanaDashboards =
  kubernetesMixinHelmGrafanaDashboards +
  nodeExporterMixinHelmGrafanaDashboards +
  corednsMixinHelmGrafanaDashboards +
  etcdMixinHelmGrafanaDashboards +
  grafanaMixinHelmGrafanaDashboards +
  prometheusMixinHelmGrafanaDashboards +
  prometheusOperatorMixinHelmGrafanaDashboards;

local prometheusAlerts = {
  'kubernetes-mixin-rules': kubernetesMixin.prometheusRules,
  'node-exporter-mixin-rules': nodeExporterMixin.prometheusRules,
  'coredns-mixin-rules': corednsMixin.prometheusRules,
  'etcd-mixin-rules': etcdMixin.prometheusRules,
  'grafana-mixin-rules': grafanaMixin.prometheusRules,
  'prometheus-mixin-rules': prometheusMixin.prometheusRules,
  'prometheus-operator-mixin-rules': prometheusOperatorMixin.prometheusRules,
};

grafanaDashboards + prometheusAlerts
```

The generated dashboards are written as standalone YAML manifests, not embedded into ConfigMaps. The generation script is still responsible for converting Jsonnet output to YAML and escaping only the Prometheus rule files so Helm-style template markers remain valid where needed:

{% raw  %}
```shell
#!/bin/sh

set -e # Exit on any error
set -u # Treat unset variables as an error

# Define paths
MIXINS_DIR="./templates"

# Function to escape YAML content
escape_yaml() {
  local file_path="$1"
  echo "Escaping $file_path..."
  sed -i \
    -e 's/{{/{{`{{/g' \
    -e 's/}}/}}`}}/g' \
    -e 's/{{`{{/{{`{{`}}/g' \
    -e 's/}}`}}/{{`}}`}}/g' \
    "$file_path"
  echo "Escaped $file_path."
}

echo "Cleaning templates directory..."
rm -rf ${MIXINS_DIR}/*
echo "Templates directory cleaned."

echo "Converting Jsonnet to YAML..."
jsonnet main.jsonnet -J vendor -m ${MIXINS_DIR} | xargs -I{} sh -c 'cat {} | gojsontoyaml > {}.yaml' -- {}
echo "Jsonnet conversion completed."

echo "Removing non-YAML files..."
find ${MIXINS_DIR} -type f ! -name "*.yaml" -exec rm {} +
echo "Non-YAML files removed."

echo "Escaping YAML files..."
find ${MIXINS_DIR} -name '*-rules.yaml' | while read -r file; do
  escape_yaml "$file"
done
echo "YAML files escaped."

echo "Processing completed successfully!"
```
{% endraw %}

The Docker build environment and local target used in this repository are:

```dockerfile
FROM golang:1.26.1-alpine AS build
LABEL stage=builder

WORKDIR /k3s-mixins

COPY src/ .

RUN apk add git
RUN go install github.com/google/go-jsonnet/cmd/jsonnet@latest
RUN go install github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@latest
RUN go install github.com/brancz/gojsontoyaml@latest

RUN jb init
RUN jb install github.com/kubernetes-monitoring/kubernetes-mixin@master
RUN jb install github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus@main
RUN jb install github.com/povilasv/coredns-mixin@master

RUN mkdir templates
RUN chmod +x generate.sh
RUN ./generate.sh

FROM scratch AS mixins
COPY --from=build /k3s-mixins/templates /
```

```make
.PHONY: k3s-mixins

k3s-mixins:
	docker build --no-cache --target mixins --output out/ .
	mv out/*-rules.yaml ../base/rules/.
	mv out/*.yaml ../base/dashboards/.
```

Run the build from `kubernetes/platform/kube-prometheus-stack/k3s-mixins/build`:

```shell
make k3s-mixins
```

With this workflow:

-   dashboards generated from mixins land in `kubernetes/platform/kube-prometheus-stack/k3s-mixins/base/dashboards` as `GrafanaDashboard` manifests
-   Prometheus rules land in `kubernetes/platform/kube-prometheus-stack/k3s-mixins/base/rules`
-   the resulting dashboards are reconciled natively by Grafana Operator instead of being discovered by Grafana sidecars through labeled ConfigMaps


### Provisioning Folders

Grafana folders are also managed declaratively using `GrafanaFolder` resources.

Example:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaFolder
metadata:
  name: kubernetes-folder
spec:
  title: Kubernetes
  instanceSelector:
    matchLabels:
      dashboards: grafana
```

Folders currently defined in this repository include:

-   Grafana
-   Kubernetes
-   Infrastructure
-   Istio
-   Envoy-Gateway
-   Minio
-   Keycloak
-   Flux


### Single Sign-On - IAM Integration

Grafana can be integrated with the cluster IAM solution to delegate authentication and enable SSO. Grafana OSS supports OpenID Connect / OAuth 2.0.

In Pi Cluster, SSO is implemented with Keycloak.

See details about Keycloak installation in ["SSO with Keycloak"](/docs/sso/).


#### Keycloak Configuration: Configure Grafana Client

The same Keycloak client configuration principles described in [Observability Visualization (Grafana)](/docs/grafana/) apply here as well:

-   Create OIDC client `grafana`
-   Configure redirect URI `https://grafana.${CLUSTER_DOMAIN}/login/generic_oauth`
-   Create client roles `admin`, `editor`, and `viewer`
-   Make roles available in ID token / user info


#### Grafana SSO Configuration

With Grafana Operator, the SSO configuration is patched directly into the `Grafana` resource instead of being written to Helm values.

SSO patch used in this repository:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: Grafana
metadata:
  name: grafana
spec:
  config:
    auth.generic_oauth:
      enabled: "true"
      name: Keycloak-OAuth
      allow_sign_up: "true"
      client_id: $${GF_AUTH_GENERIC_OAUTH_CLIENT_ID}
      client_secret: $${GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET}
      scopes: openid email profile offline_access roles
      email_attribute_path: email
      login_attribute_path: username
      name_attribute_path: full_name
      auth_url: https://iam.${CLUSTER_DOMAIN}/realms/picluster/protocol/openid-connect/auth
      token_url: https://iam.${CLUSTER_DOMAIN}/realms/picluster/protocol/openid-connect/token
      api_url: https://iam.${CLUSTER_DOMAIN}/realms/picluster/protocol/openid-connect/userinfo
      role_attribute_path: contains(resource_access.grafana.roles[*], 'admin') && 'Admin' || contains(resource_access.grafana.roles[*], 'editor') && 'Editor' || (contains(resource_access.grafana.roles[*], 'viewer') && 'Viewer')
      signout_redirect_url: https://iam.${CLUSTER_DOMAIN}/realms/picluster/protocol/openid-connect/logout?client_id=grafana&post_logout_redirect_uri=https%3A%2F%2Fgrafana.${CLUSTER_DOMAIN}%2Flogin%2Fgeneric_oauth
```

Client credentials are loaded from a Secret through environment variables injected into the Grafana container:

```yaml
- name: GF_AUTH_GENERIC_OAUTH_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: grafana-env-secret
      key: GF_AUTH_GENERIC_OAUTH_CLIENT_ID
- name: GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: grafana-env-secret
      key: GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET
```

This keeps OAuth credentials out of the `Grafana` manifest while still allowing the operator to reconcile the full runtime configuration.


### Persistence

Persistent storage is configured through `spec.persistentVolumeClaim` on the `Grafana` resource.

Persistence component used in production:

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: Grafana
metadata:
  name: grafana
spec:
  persistentVolumeClaim:
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: ${STORAGE_CLASS:=longhorn}
      resources:
        requests:
          storage: 5Gi
```

The deployment strategy is also switched to `Recreate`, which is the safest choice for a single-writer PVC mounted by a single Grafana instance.


## Observability

### Metrics

Grafana metrics are enabled directly in the `Grafana` spec:

```yaml
spec:
  config:
    metrics:
      enabled: "true"
```

Prometheus scrapes Grafana through a `ServiceMonitor`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: grafana
spec:
  endpoints:
    - interval: 30s
      path: /metrics
      port: grafana
  selector:
    matchLabels:
      app.kubernetes.io/managed-by: grafana-operator
      dashboards: grafana
```

This `ServiceMonitor` matches the Service created by the operator for the Grafana instance.


## Summary

The current Grafana deployment in Pi Cluster follows this model:

-   Grafana Operator is installed with a Helm chart.
-   Grafana itself is managed through a `Grafana` custom resource.
-   Datasources, folders, and dashboards are managed through dedicated Grafana Operator CRs.
-   Routing, SSO, and persistence are added as reusable Kustomize components.
-   Secrets are sourced from Vault through External Secrets.

This provides a cleaner GitOps model than the legacy sidecar-heavy Helm deployment and matches the way the rest of the platform applications are managed in this repository.