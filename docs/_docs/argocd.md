---
title: GitOps (ArgoCD)
permalink: /docs/argocd/
description: How to apply GitOps to Pi cluster configuration using ArgoCD.
last_modified_at: "03-06-2024"
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

### Helm Chart installation
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
    params:
      # Run server without TLS
      # Ingress NGINX finishes TLS connections
      server.insecure: true
    cm:
      statusbadge.enabled: true
      # Adding Applications health check
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
      # Kustomize build options
      # --enable-helm: Enabling Helm chart rendering with Kustomize
      # --load-restrictor LoadRestrictionsNone: Local kustomizations may load files from outside their root
      kustomize.buildOptions: --enable-helm --load-restrictor LoadRestrictionsNone

  server:
    # Ingress Resource.
    ingress:
      ## Enable creation of ingress resource
      enabled: true
      ## Add ingressClassName to the Ingress
      ingressClassName: nginx
      # ingress host
      hostname: argocd.picluster.ricsanfre.com
      ## Default ingress path
      path: /
      pathType: Prefix
      # Enable tls. argocd-server-tls secret is created automatically for hostname
      tls: true

      ## Ingress annotations
      annotations:
        # Linkerd configuration. Configure Service as Upstream
        nginx.ingress.kubernetes.io/service-upstream: "true"
        # Enable cert-manager to create automatically the SSL certificate and store in Secret
        # Possible Cluster-Issuer values: 
        #   * 'letsencrypt-issuer' (valid TLS certificate using IONOS API) 
        #   * 'ca-issuer' (CA-signed certificate, not valid)
        cert-manager.io/cluster-issuer: letsencrypt-issuer
        cert-manager.io/common-name: argocd.picluster.ricsanfre.com
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

### Ingress Configuration

Igress NGINX will be used as ingress controller, terminating TLS traffic, so ArgoCD does not need to expose its API using HTTPS.

- Configure ArgoCD to run its API server with TLS disabled
   
  The following helm chart values need to be provided:
  ```yml
  configs:
    params:
      # Run server without TLS
      # Nginx finishes TLS connections
      server.insecure: true
  ```

- For creating Ingress resource, add following lines to helm chart values:

  ```yml
  # Ingress Resource.
  ingress:
    ## Enable creation of ingress resource
    enabled: true
    ## Add ingressClassName to the Ingress
    ingressClassName: nginx
    # ingress host
    hosts:
      - argocd.picluster.ricsanfre.com
    ## TLS Secret Name
    tls:
      - secretName: argocd-tls
        hosts:
          - argocd.picluster.ricsanfre.com
    ## Default ingress path
    paths:
      - /

    ## Ingress annotations
    annotations:
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      # Possible Cluster-Issuer values: 
      #   * 'letsencrypt-issuer' (valid TLS certificate using IONOS API) 
      #   * 'ca-issuer' (CA-signed certificate, not valid)
      cert-manager.io/cluster-issuer: letsencrypt-issuer
      cert-manager.io/common-name: argocd.picluster.ricsanfre.com
  ```

See more details in [Argo-CD Ingress configuration doc](https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/)


### Exclude synchronization of resources

Using automatic synchornization and pruning of resources might cause side effects with some of the kubernetes resources that are not created by ArgoCD.

See an example of this wrong behavior in [issue #273](https://github.com/ricsanfre/pi-cluster/issues/273). ArgoCD auto-synch policy is pruning VolumeSnapshot and VolumeSnapshotContent resources that are created automatically by backup process, making backup process to fail.

The way to solve this issue is to make ArgoCD to ignore the VolumeSnapshot and VolumeSnapshotContent resources during the synchronization process.

For doing that, ArgoCD need to be configured to exclude those resources from synchronization. See [ArgoCD resource Exclusion](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#resource-exclusioninclusion) for more details.

The following lines need to be added to helm chart:


  ```yml
  configs:
    cm:
      ## Ignore resources
      # https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#resource-exclusioninclusion
      # Ignore VolumeSnapshot and VolumeSnapshotContent: Created by backup processes.
      resource.exclusions: |
        - apiGroups:
          - snapshot.storage.k8s.io
          kinds:
          - VolumeSnapshot
          - VolumeSnapshotContent
          clusters:
          - "*"
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
    syncPolicy:
      # Automatic sync options
      automated:
        prune: true
        selfHeal: true
  ```

  Where:
  - `destination.namespace`: namespace to deploy the application
  - `destination.server`: cluster to deploy the application (`https://kuberentes.default.svc` indicates local cluster)
  - `source.repoURL` is the URL of the Git Repository
  - `sourcepath` is the path within the Git repository where the application is located
  - `source.targetRevision` is the Git tag, branch or commit to track
  - `syncPolicy.automated` are [ArgoCD auto-sync policies](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/), to automatically keep in synch application manifest files in the cluster, delete old resources (`prune` option) and launch sych when changes are made to the cluster (`selfHeal` option)

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

  A directory type application can be configured to apply kustomize to a set of directories just deploying in the directory (`source.path`) a `kustomize yaml` file.

  ```yaml
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: test-app
    namespace: argocd
  spec:
    destination:
      namespace: argocd
      name: in-cluster
    source:
      path: <path-to-kustomization.yaml-file>
      repoURL: https://github.com/<user>/<repo>.git
      targetRevision: master
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
  ```

  To provide build options to kustomize, `kustomize.buildOptions` field of argocd-cm ConfigMap need to be configured.

  The following kustomize build options have been added through helm chart values.yaml

  - Using kustomize with helm chart inflation

    Kustomize has support for helm chart inflation using `helm template` command.

    {{site.data.alerts.note}}
    Currently, not all `helm template` options are supported but there is a commitment to support it all.
    See [kustomization helmChart documentation](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/helmcharts/).
    {{site.data.alerts.end}}

    kustomize `--enable-helm` build option need to be added to support helm chart inflation.
  
  - Enable local kustomizations to load files from outside their root folder.

    Kustomize `--load-restrictor=LoadRestrictionsNone` build option need to be added to support it.

    This build option is needed, when using helm chart inflation capability, to overwrite `values.yaml` file defined in `base` directory with contents of `value.yaml` file defined in the `overlays` folder.

    Kustomize's `HelmChart.additionalFiles` field  can be used jointly with `HelmChart.valuesFile` for this purpose.
  
    See [kustomize's issue 4658 comment](https://github.com/kubernetes-sigs/kustomize/issues/4658#issuecomment-1815675157)

  
  Chek out further details in [Argo CD Kustomize applications documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/kustomize/).

### Helm Umbrella Charts 

ArgoCD Helm application has the limitation that helm Values file must be in the same git repository as the Helm chart.

Since all charts we want to deploy in the cluster belongs to third party repositories, we could not use the values file option (values file will be in our repository and not in the 3rd party repository) and specifying all chart parameters within the Application definition is not manageable since some of the charts contain lots of parameters.

{{site.data.alerts.note}}
There is a new ArgoCd functionality, currently (release v2.11.2) in beta status, to support multiple source repos per Application, that will remove that limitation.
See details in ["ArgoCD documentation: Multiple Sources for an Application"](
https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/)
{{site.data.alerts.end}}


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
  helm:
    <additional helm options>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Argo CD looks for a Chart.yaml file under <repo-path>. If present, it will check the apiVersion inside it and for v2 it uses Helm 3 to render the chart. Actually, ArgoCD will not use `helm install` to install charts. It will render the chart with `helm template` command and then apply the output with kubectl.

```shell
helm template \
        --dependency-update \
        --namespace <target-namespace> \
        <app-name> <repo-path> \
        | kubectl apply -n <target-namespace> -f -
```

Additional options can be passed to helm command using `.spec.helm` parametes in Application resource.

- `helm.valueFiles`: To specify the name of the values file (default values.yaml)
- `helm.skipCRDs`: To skip installation of CDRs defined in the helm chart


### Kustomized Application using Helm Chart Inflator

As alternative to the use of Helm Umbrella charts, applications packaged with kustomized can be defined, using kustomized's Helm inflator functionality. Kustomized uses `helm template` command to generate manifest files from a helm chart.

For using that functionality, helm chart details, can be specified within [`helmChart` field in `kustomized.yaml` file](https://github.com/kubernetes-sigs/kustomize/blob/master/examples/chart.md).


Using Argo-cd's kustomized applications with helm chart support has advantages over Argo-cd's helm chart applications like ability to apply kustomized's patches on the manifest files generated by the helm chart inflation process (execution of `helm template` command).

Kustomize application can have the following structure, including `base` configuration and different `overlays` (i.e patches), so helm chart values.yaml defined in the base can be patched (overwritten) by values.yaml in the overlays.


```shell
└── app-test
    ├── base
    │   ├── kustomization.yaml
    │   ├── ns.yaml
    │   ├── values.yaml
    └── overlays
        ├── dev
        │   ├── kustomization.yaml
        │   ├── values.yaml
        └── prod
            ├── kustomization.yaml
            └── values.yaml
```

`base/kustomize.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ns.yaml # Name service definition manifest file or any other
```

`overlays/dev/kustomize.yaml` and `overlays/prod/kustomize`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

helmCharts:
  - name: <helm-chart-name>
    repo: <helm-chart-repo>
    version: <helm-chart-version>
    releaseName: <release-name>
    namespace: <namespace>
    valuesFile: ../../base/values.yaml
    includeCRDs: true
    additionalValuesFiles:
      - values.yaml
```

base helm values.yaml file (`base/values.yaml`) is used as main values file (helmCharts.valueFile). This values.yaml file is merged with values.yaml defined in the overlay directory (`overlay/x/values.yaml`) using (helmCharts.additionalValuesFiles)

This helm chart could be installed executing the following command:

```shell
kubectl kustomize --enable-helm --load-restrictor=LoadRestrictionsNone app/overlay/dev | kubectl apply -f -
```
The previous command will apply the dev overlay to inflate helm chart, using `overlay` values.yaml to overwrite default values provided in `base` and patch them after the inflation.

{{site.data.alerts.warning}}
Using kustomize, manifest files are generated via `helm template` command. This is the same procedure used by ArgoCD when installing a HelmChart application, so the output should be the same.

Applying kustomize manifest files directly could provoke undesired results, in case that inflated helm chart contains [helm hooks](https://helm.sh/docs/topics/charts_hooks/), only processed by `helm install` or `helm upgrade` commands but not by `kubectl kustomize <options> <path> | kubectl apply -f -` command.

ArgoCD, is processing helm hooks annotated resources, and translate them into ArgoCD hooks, so the functionality provided by the helm hooks is not lost. See [ArgoCD helm hooks support](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/#helm-hooks).
{{site.data.alerts.end}}


{{site.data.alerts.note}}
Packaged helm applications will be deployed using kustomize applications following the previous defined pattern. This pattern is the preferred solution over defining umbrella helm charts, because it is simpler and it can leverage all patching capabilities provided by kustomized.
{{site.data.alerts.end}}


## Bootstraping the cluster using App of Apps pattern

For bootstraping the cluster [app of apps pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/) can be used. The App-of-Apps design is basically an Argo CD Application made up of other Argo CD Applications.

It consist of a ArgoCD application, (root application) containing a set of Application manifest files.

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

In ArgoCD, the following App of Apps will be defined

```shell
root-app
├── infra
│   ├── cert-manager
│   └── external-secrets
└── app
    ├── app1
    └── app2
```

- root-app: Root application: containing two other apps-of-apps:
  - infra: Infrastructure related applications (i.e.: cert-manager, longhorn, minio, kube-prometheus-stack, etc.)
  - apps: Microservice architecture support services (i.e.: kafka, databases, etc.) and self-develop applications.

`root-app` application will be specified as a kustomized application containing manifest resources files corresponding to ArgoCD Application.

Within git repo the following directory structure can be created

```shell
└── root-app
    ├── base
    │   ├── kustomization.yaml
    │   ├── application.yaml
    │   ├── infrastructure.yaml
    └── overlays
        ├── dev
        │   ├── kustomization.yaml
        │   ├── patches.yaml
        └── prod
            ├── kustomization.yaml
            └── patches.yaml
```

- base/kustomization.yaml

  ```yaml
  apiVersion: kustomize.config.k8s.io/v1beta1
  kind: Kustomization

  resources:
  - infrastructure.yaml
  - application.yaml
  ```

- base/infrastructure.yaml

  ```yaml
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: infrastructure
    namespace: argocd
    finalizers:
      - resources-finalizer.argocd.argoproj.io
    annotations:
      argocd.argoproj.io/sync-wave: "-2"
  spec:
    project: picluster
    source:
      path: kubernetes/bootstrap/infra/overlays/prod
      repoURL: https://github.com/ricsanfre/pi-cluster
      targetRevision: master
    destination:
      namespace: argocd
      name: in-cluster
    syncPolicy:
      automated:
        selfHeal: true
        prune: true
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
  ```

- base/application.yaml

  ```yaml
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: apps
    namespace: argocd
    finalizers:
      - resources-finalizer.argocd.argoproj.io
    annotations:
      argocd.argoproj.io/sync-wave: "-1"
  spec:
    project: picluster
    source:
      path: kubernetes/bootstrap/apps/overlays/prod
      repoURL: https://github.com/ricsanfre/pi-cluster
      targetRevision: master
    destination:
      namespace: argocd
      name: in-cluster
    syncPolicy:
      automated:
        selfHeal: true
        prune: true
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
  ```

  Both applications are configured to be synchronized using different waves. So `infrastucture` app of apps will be deployed before `apps` app of apps.

  `infrastructure` and `apps` applications point to a different repository path, containing another kustomized application following the app of apps pattern (manifest files are argoCD Application) and its folder structure is similar to the one used by `root-app`


{{site.data.alerts.note}}

Root application created for Pi-Cluster can be found in [/kubernets/bootstrap/root-app]({{ site.git_address }}/tree/master/kubernetes/bootstrap/root-app).

Infrastructure app of apps can be found in [/kubernets/bootstrap/infra]({{ site.git_address }}/tree/master/kubernetes/bootstrap/infra).

Applications app of apps can be found in [/kubernets/bootstrap/apps]({{ site.git_address }}/tree/master/kubernetes/bootstrap/apps).

{{site.data.alerts.end}}

#### Deploying Root application

Root application can be deployed declarative applying the following manifest file:

```yml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: picluster
  source:
    path: kubernetes/bootstrap/root-app/overlays/prod
    repoURL: https://github.com/ricsanfre/pi-cluster
    targetRevision: master
  destination:
    namespace: argocd
    name: in-cluster
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    retry:
      limit: 10
      backoff:
        duration: 1m
        maxDuration: 16m
        factor: 2
    syncOptions:
      - CreateNamespace=true
```

This can be done executing the following command from repo home directory

```shell
kubectl kustomize --enable-helm --load-restrictor=LoadRestrictionsNone \
      kubernetes/bootstrap/argocd/overlays/prod | kubectl apply -f -
```

### CRDs Application

Application containing all CRDs could be created and deployed in the first sync-wave. So all other applications making use of CRDs can be deployed with success even when the corresponding Controller services are not yet deployed. For example: Deploying Prometheus Operator CRDs as part of a CRDs Application, allows to deploy prometheus monitoring objects (ServiceMonitor, PodMonitor, etc) for applications that are deployed before kube-prometheus-stack application.

For an example of such CRDs application, check repository [/kubernetes/infraestructure/crds]({{ site.git_address }}/tree/master/kubernetes/infrastructure/crds).


## Repo Structure

The Git repo structure containing all application manifest files is the following

```shell
kubernetes
├── apps # end user applications
├── bootstrap # cluster bootstraping
│   ├── apps # argo-cd end-user applications (end-user Application resources)
│   ├── argocd #  argoc-cd bootstraping (root-app app of apps definition)
│   ├── infra # argo-cd infraestructure apps (infrastructure Application resources).
│   ├── root-app # argo-cd root application (infra and apps manifest files)
│   └── vault # vault bootstraping manifest files
└── infrastructure # infrastructure applications
```


## References

- [Argo CD Working With Helm](https://kubebyexample.com/learning-paths/argo-cd/argo-cd-working-helm)

- [ArgoCD App of Apps pattern to bootstrap de cluster](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)

- [ArgoCD SyncWaves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)

- [How to set Argo CD Application Dependencies](https://codefresh.io/blog/argo-cd-application-dependencies/)

- [How to avoid  CRD tool long error](https://www.arthurkoziel.com/fixing-argocd-crd-too-long-error/)