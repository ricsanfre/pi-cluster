# Kube Prometheus Stacks Mixins for K3s

The kube-prometheus-stack Helm chart, which deploys the kubernetes-mixin, targets standard Kubernetes setups, often pre-configured for specific cloud environments. However, these configurations aren’t directly compatible with k3s, a lightweight Kubernetes distribution. Since k3s lacks many of the default cloud integrations, issues arise, such as missing metrics, broken graphs, and unavailable endpoints.

This blog post guides you through adapting the kube-prometheus-stack Helm chart and the kubernetes-mixin to work seamlessly in k3s environments, ensuring functional dashboards and alerts tailored to k3s

## kubernetes-mixin Configuration

The kube-prometheus-stack Helm chart uses the kube-prometheus project as a baseline for the Helm chart. The kube-prometheus project is a collection of Kubernetes manifests, Grafana dashboards and Prometheus rules combined with Jsonnet libraries to generate them. The kube-prometheus project uses monitoring mixins to generate alerts and dashboards. Monitoring mixins are a collection of Jsonnet libraries that generate dashboards and alerts for Kubernetes. 

-  The kubernetes-mixin is a mixin that generates dashboards and alerts for Kubernetes.
-  The node-exporter, coredns, grafana, prometheus and prometheus-operator mixins are also used to generate dashboards and alerts for the Kubernetes cluster.

## Credits

Procedure is an adapted version of the procedure described in https://hodovi.cc/blog/configuring-kube-prometheus-stack-dashboards-and-alerts-for-k3s-compatibility/
Big shout out to Adin Hodovic for describing the procedure in detail.

Original version from Adin's post has be updated to

- Include etcd mixin. Etcd metrics are exposed by k3s in the same way of the rest. So they can alsob be obtained from kubelet endpoint
- Adding showMultiCluster config option to several of the mixins, so "cluster" variable in Dashboards is not displayed. This obtain same outcomes as kube-prom-stack helm chart hacking scripts generating manifest files from mixins:
  https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/hack/sync_grafana_dashboards.py#L171
- Fixing issue with `generate.sh` script: dashboard yaml files not to be escaped.
- Selecting the Prometheus and Prometheus Operator targets by their real job names (`kube-prometheus-stack-prometheus` and `kube-prometheus-stack-operator`). The mixins default to `job="prometheus"` and `job="prometheus-operator"`, which match nothing in this cluster, so every rule of those two mixes stayed silent.
- Rewriting the upstream `KubeletDown` expression. It compares two counts `on (cluster)`, but Prometheus does not attach external labels to the synthetic `up` series, so the right-hand side has no `cluster` label, `unless on (cluster)` never matches and the alert fires permanently. `main.jsonnet` replaces it with `absent(up{job="kubelet", metrics_path="/metrics"} == 1)`.

Because of these last two, **the generated files are not byte-identical to a plain upstream build**. Re-run `make k3s-mixins` rather than copying output from upstream, and check `src/main.jsonnet` when reviewing the diff.

## Build k3s mixins

Execute command:

```shell
make k3s-mixins
```

## Dependency pinning

`src/jsonnetfile.json` declares the mixins, so the Dockerfile no longer installs `@master` and a build is
reproducible:

| Dependency | Pin | Why |
| --- | --- | --- |
| `kube-prometheus` | tag `v0.19.0` | publishes semver tags; Renovate bumps them |
| `kubernetes-mixin` | commit `bacbfe09…` | tags lag master by months (the newest, `version-1.5.6`, was four months behind). Renovate tracks the `master` digest with a `git-refs` custom manager, not the tags |
| `coredns-mixin` | commit `eb356cfb…` | publishes no tags and has not moved since 2023 |

`kube-prometheus` pulls node-exporter, prometheus, prometheus-operator, etcd and alertmanager mixins
transitively, so their versions follow the `kube-prometheus` pin. `jsonnetfile.lock.json` therefore lists
`kubernetes-mixin` twice — once transitive (`13235f75` via kube-prometheus) and once direct (`bacbfe09`);
the direct entry wins in `vendor/`.

After changing a pin, run `make k3s-mixins` and commit the regenerated files.