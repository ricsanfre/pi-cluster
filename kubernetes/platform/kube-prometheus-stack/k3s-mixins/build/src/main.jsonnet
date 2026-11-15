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
  dashboardFolder: 'Node Exporter',
  mixin: (import 'node-mixin/mixin.libsonnet') + {
    _config+:: {
      nodeExporterSelector: 'job="node-exporter"',
      showMultiCluster: false,
    },
  },
});

local corednsMixin = addMixin({
  name: 'coredns',
  dashboardFolder: 'Kubernetes',
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
  dashboardFolder: 'Observability',
  mixin: (import 'grafana-mixin/mixin.libsonnet') + {
    _config+:: {},
  },
});

local prometheusMixin = addMixin({
  name: 'prometheus',
  dashboardFolder: 'Observability',
  mixin: (import 'prometheus/mixin.libsonnet') + {
    _config+:: {
      showMultiCluster: false,
      // kube-prometheus-stack names the ServiceMonitor after the release, so
      // the default `job="prometheus"` matches no target and every rule of
      // this mixin stays silent.
      prometheusSelector: 'job="kube-prometheus-stack-prometheus"',
    },
  },
});

local prometheusOperatorMixin = addMixin({
  name: 'prometheus-operator',
  dashboardFolder: 'Observability',
  mixin: (import 'prometheus-operator-mixin/mixin.libsonnet') + {
    _config+:: {
      // Same as above: the operator is scraped as job="kube-prometheus-stack-operator".
      prometheusOperatorSelector: 'job="kube-prometheus-stack-operator"',
    },
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


// The upstream KubeletDown rule compares two counts `on (cluster)`, but
// Prometheus does not attach external labels to the synthetic `up` series, so
// the right-hand side loses the `cluster` label, `unless on (cluster)` never
// matches and the alert fires forever. Restore the original kube-prometheus
// formulation, which is correct for a single cluster.
local fixKubeletDown(rule) =
  if std.objectHas(rule, 'alert') && rule.alert == 'KubeletDown'
  then rule { expr: 'absent(up{job="kubelet", metrics_path="/metrics"} == 1)' }
  else rule;

local fixKubeletDownRule(rules) =
  rules {
    spec+: {
      groups: [
        group { rules: [fixKubeletDown(rule) for rule in group.rules] }
        for group in rules.spec.groups
      ],
    },
  };

local prometheusAlerts = {
  'kubernetes-mixin-rules': fixKubeletDownRule(kubernetesMixin.prometheusRules),
  'node-exporter-mixin-rules': nodeExporterMixin.prometheusRules,
  'coredns-mixin-rules': corednsMixin.prometheusRules,
  'etcd-mixin-rules': etcdMixin.prometheusRules,
  'grafana-mixin-rules': grafanaMixin.prometheusRules,
  'prometheus-mixin-rules': prometheusMixin.prometheusRules,
  'prometheus-operator-mixin-rules': prometheusOperatorMixin.prometheusRules,
};

grafanaDashboards + prometheusAlerts
