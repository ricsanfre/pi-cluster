---
title: GitOps (ArgoCD)
permalink: /docs/argocd/
description: How to apply GitOps to Pi cluster configuration using ArgoCD.
last_modified_at: "16-01-2023"
---


[Argo CD](https://argo-cd.readthedocs.io/) is a declarative, GitOps continuous delivery tool for Kubernetes.

It can be integrated with Git repositories, and used jointly with CI tools, like [Jenkins](https://www.jenkins.io/) or [Github-actions](https://docs.github.com/en/actions) to define end-to-end CI/CD pipeline to automatically build and deploy applications in Kubernetes.

![picluster-cicd-gitops-architecture](/assets/img/cicd-gitops-architecture.png)

Argo CD follows the GitOps pattern of using Git repositories as the source of truth for defining the desired application state, through a set of kubernetes manifests. Kubernetes manifests can be specified in several ways:

- kustomize applications
- helm charts
- Plain directory of YAML/json manifests

Argo CD automates the deployment of the desired application states in the specified target environments (git repository). Application deployments can track updates to branches, tags, or pinned to a specific version of manifests at a Git commit.

ArgoCD will be used in Pi Cluster to automatically deploy the different applications in Kuberenets cluster.

## ArgoCD installation

ArgoCD can be installed through helm chart

-  Step 1: Add ArgoCD helm repository:
  ```shell
  helm repo add argo https://argoproj.github.io/argo-helm
  ```
- Step 2: Fetch the latest charts from the repository:
  ```shell
  helm repo update
  ```
- Step 3: Create namespace
  ```shell
  kubectl create namespace argocd
  ```
- Step 4: Create argocd-values.yml

  ```yml
  configs:
    cm:
      statusbadge.enabled: 'true'
      resource.customizations.health.argoproj.io_Application: |
        hs = {}
        hs.status = "Progressing"
        hs.message = ""
        if obj.status ~= nil then
          if obj.status.health ~= nil then
            hs.status = obj.status.health.status
            if obj.status.health.message ~= nil then
              hs.message = obj.status.health.message
            end
          end
        end
        return hs
  ```

  With this config, Application resource health check is included so App of Apps pattern can be used. See below.

- Step 5: Install helm chart
  ```shell
  helm install argocd argo/argo-cd  --namespace argocd -f argocd-values.yml
  ```

- Step 6: Check Argo CD admin password

  ```
  kubectl get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' -n argocd | base64 -d
  ```

- Step 7: Configure Port Forward

  ```
  kubectl port-forward svc/argocd-server -n argocd 8080:80 --address 0.0.0.0
  ```

- Step 8: Access Argo CD UI, using `admin` user and password obtained from step 6.

  ```
  http://<server-port-forwarding>:8080
  ```

## ArgoCD Applications


ArgoCD applications to be deployed can be configured using ArgoCD UI or using ArgoCD specific CRDs (Application/ApplicationSet).

Different types of applications will be needed for the Pi Cluster

- Directory Applications

  A [directory-type application](https://argo-cd.readthedocs.io/en/stable/user-guide/directory/) loads plain manifest files from .yml, .yaml, and .json files from a specific directory in a git repository.

  Using declarative Application CRD a directory application can be created applying the following manifest file

  ```yml
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: test-app
  spec:
    destination:
      namespace: <target-namespace>
      server: https://kubernetes.default.svc
    project: default
    source:
      # Enabling Recursive Resource Detection
      directory:
        recurse: true
      # Repo path
      path: test-app
      # Repo URL
      repoURL: https://github.com/<user>/<repo>.git
      # Branch, tag tracking
      targetRevision: HEAD
  ```

  Where:
  - `destination.namespace`: namespace to deploy the application
  - `destination.server`: cluster to deploy the application (`https://kuberentes.default.svc` indicates local cluster)
  - `source.repoURL` is the URL of the Git Repository
  - `sourcepath` is the path within the Git repository where the application is located
  - `source.targetRevision` is the Git tag, branch or commit to track

- Helm Chart Applications in ArgoCD 

  [Helm chart applications](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/) can be installed in a declarative GitOps way using ArgoCD's Application CRD.

  ```yml
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: cert-manager
    namespace: argocd
  spec:
    project: default
    source:
      chart: cert-manager
      repoURL: https://charts.jetstack.io
      targetRevision: v1.10.0
      helm:
        releaseName: cert-manager
        parameters:
          - name: installCRDs
            value: "true"
        # valueFiles:
        #  - values.yaml
    destination:
      server: "https://kubernetes.default.svc"
      namespace: cert-manager
  ```

  Where:
  - `chart` is the name of the chart to deploy from the Helm Repository.
  - `repoURL` is the URL of the Helm Repository.
  - `releaseName` is the version of the chart to deploy
  - `parameters` - Helm chart parameters (overrriding values in values.yaml file)

  Alternatively, to provide individual parameters, a values file can be specified (`.spec.source.helm.valueFiles`).

- Kustomize Application
  
  [Kustomize](https://kustomize.io/) traverses a Kubernetes manifest to add, remove or update configuration options without forking. It is available both as a standalone binary and as a native feature of kubectl
  Kustomize can be used to over a set of plain yaml manifest files or a Chart.

  Argo CD has native support for Kustomize and has the ability to read a kustomization.yaml file to enable deployment with Kustomize and allow ArgoCD to manage the state of the YAML files.
  
  A directory type application can be configured to apply kustomize to a set of directories just deploying in the directory a kustomize yaml file.

### Helm Umbrella Charts 

ArgoCD Helm application has the limitation that helm Values file must be in the same git repository as the Helm chart.

Since all charts we want to deploy in the cluster belongs to third party repositories we could not use the values file option (values file will be in our repository and not in the 3rd party repository), and the parameters option will be not manageable since some of the charts contain lots of parameters.

As conclusion, this type of ArgoCD application is useless when deploying charts from third party repositories.

As an alternative a Helm Umbrella Chart pattern can be used. Helm Umbrella chart is sort of a "meta" (empty) Helm Chart that lists other Helm Charts as a dependency ([subcharts](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/)). 
It consists of a empty helm chart in a repo directory containing only chart definition file (`Chart.yaml`), listing all subcharts, and its corresponding `values.yaml` file.

- `<repo-path>/Chart.yaml`

  ```yml
  apiVersion: v2
  name: certmanager
  version: 0.0.0
  dependencies:
    - name: cert-manager
      version: v1.10.0
      repository: https://charts.jetstack.io
  ```
- `<repo-path>/values.yaml`

  ```yml
  cert-manager:
    installCRDs: true
  ```

Using this pattern, ArgoCD directory-type application can be declarative deployed.

```yml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: umbrella-chart-app
spec:
  destination:
    namespace: <target-namespace>
    server: https://kubernetes.default.svc
  project: default
  source:
    path: <repo-path>
    repoURL: https://github.com/<user>/<repo>.git
    targetRevision: HEAD
```

Argo CD looks for a Chart.yaml file under <repo-path>. If present, it will check the apiVersion inside it and for v2 it uses Helm 3 to render the chart. Actually, ArgoCD will not use `helm install` to install charts. It will render the chart with `helm template` command and then apply the output with kubectl.

```shell
helm template \
        --dependency-update \
        --namespace <target-namespace> \
        <app-name> <repo-path> \
        | kubectl apply -n <target-namespace> -f -
```
{{site.data.alerts.note}}

Umbrella helm charts will be created for most of the Pi cluster applications, including any additional manifest required to configure the application in its `template` directory.

{{site.data.alerts.end}}

## Bootstrapig the cluster using App of Apps pattern

For bootstraping the cluster [app of apps pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/) can be used. The App-of-Apps design is basically an Argo CD Application made up of other Argo CD Applications.

Basically it will consist of a ArgoCD application, (root application) containing a set of Application manifest files.

Syncwaves can be used to specify the order in which each application need to be deployed.

[Syncwaves and Synchooks](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) are a way to order how Argo CD applies individual manifests within an Argo CD Application. The order is specified by annotating the object (`argocd.argoproj.io/sync-wave` annotation) with the desired order to apply the manifest. Sync-wave is a integer number (negative numbers are allowed) indicating the order. Manifest files containing lower numbers of synch-waves are applied first.

All resources belonging to same sync-wave have to report healthy status before ArgoCD decices to apply next sync-wave.

Argo CD has health checks for several standard Kubernetes objects built-in. These checks then are bubbled up to the overall Application health status as one unit. For example, an Application that has a Service and a Deployment will be marked “healthy” only if both objects are considered healthy.

There are built-in health checks for Deployment, ReplicaSet, StatefulSet DaemonSet, Service, Ingress, PersistentVolumeClaim, etc. Custom health checks can be defined. See [ArgoCD documentation - Resource Health](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/)

[As described in the documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/#argocd-app), ArgoCD removed Application CRD health check from release 1.8. If App of Apps pattern is used Application health status check need to be added to ArgoCD configuration.

```
resource.customizations.health.argoproj.io_Application: |
  hs = {}
  hs.status = "Progressing"
  hs.message = ""
  if obj.status ~= nil then
    if obj.status.health ~= nil then
      hs.status = obj.status.health.status
      if obj.status.health.message ~= nil then
        hs.message = obj.status.health.message
      end
    end
  end
  return hs
```

### Root App

Root application will be specified as a helm chart, so Helm templating can be leveraged to automatically create and configure Application resources and initial resources needed.

Within git repo the following directory structure can be created

```shell
root
├── Chart.yaml
├── templates
│   ├── app-set.yaml
│   └── namespaces.yaml
└── values.yaml
```

- Chart.yaml
  ```yml
  apiVersion: v2
  name: bootstrap
  version: 0.0.0
  ```
- values.yaml

  ```yml
  # Repo details
  gitops:
    repo: https://github.com/ricsanfre/pi-cluster
    revision: HEAD

  # Ordered list of application corresponding to different sync waves
  apps:
    - name: argocd
      namespace: argocd
      path: argocd/bootstrap/argocd
    - name: root
      namespace: argocd
      path: argocd/bootstrap/root
    - name: external-secrets
      namespace: external-secrets
      path: argocd/system/external-secrets
    - name: metallb
      namespace: metallb
      path: argocd/system/metallb
  ```

- templates/app-set.yaml

  This will create a ArgoCD application for each item in the values file under `apps` dictionary. Each of the item defined contains information about the name of the application (`name`), the namespace to be used during deployment (`namespace`) and the path under `gitops.repo` where the application is located (`path`).

  The index of the dictionary will be used as `argocd.argoproj.io/sync-wave`, so each application belongs to a different wave and are deployed in order.
  {% raw %}
  ```yml
  {{- range $index, $app := .Values.apps }}
  ---
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: {{ $app.name }}
    namespace: {{ $.Release.Namespace }}
    annotations:
      argocd.argoproj.io/sync-wave: '{{ $index }}'
  spec:
    destination:
      namespace: {{ $app.namespace }}
      server: https://kubernetes.default.svc
    project: default
    source:
      path: {{ $app.path }}
      repoURL: {{ $.Values.gitops.repo }}
      targetRevision: {{ $.Values.gitops.revision }}
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      retry:
        limit: 10
        backoff:
          duration: 1m
          maxDuration: 16m
          factor: 2
      syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
  {{- end }}
  ```
  {% endraw %}
- templates/namespaces.yml
  
  Create namespaces with linkerd annotation


- templates/other-manifests.yaml

  Other manifest files can be provided to bootstrap the cluster. 

## References


- [Argo CD Working With Helm](https://kubebyexample.com/learning-paths/argo-cd/argo-cd-working-helm)

- [ArgoCD App of Apps pattern to bootstrap de cluster](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)

- [ArgoCD SyncWaves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)

- [How to set Argo CD Application Dependencies](https://codefresh.io/blog/argo-cd-application-dependencies/)

- [How to avoid  CRD tool long error](https://www.arthurkoziel.com/fixing-argocd-crd-too-long-error/)