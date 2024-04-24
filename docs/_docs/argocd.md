---
title: GitOps (ArgoCD)
permalink: /docs/argocd/
description: How to apply GitOps to Pi cluster configuration using ArgoCD.
last_modified_at: "08-02-2024"
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
      # Enabling Helm chart rendering with Kustomize
      kustomize.buildOptions: --enable-helm

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
  
  A directory type application can be configured to apply kustomize to a set of directories just deploying in the directory a kustomize yaml file.

### Helm Umbrella Charts 

ArgoCD Helm application has the limitation that helm Values file must be in the same git repository as the Helm chart.

Since all charts we want to deploy in the cluster belongs to third party repositories, we could not use the values file option (values file will be in our repository and not in the 3rd party repository) and specifying all chart parameters within the Application definition is not manageable since some of the charts contain lots of parameters.

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

{{site.data.alerts.note}}

Packaged helm applications, using umbrella helm chart pattern, and kustomize applications have been created to deploy all Kuberentes services in the Pi Cluster.

When using umbrella helm charts, empty chart pattern has not always been used. `template` directory, containing additional manifest files required to configure the application, has been added whenever neccesary.

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
  gitops:
    repo: https://github.com/ricsanfre/pi-cluster
    revision: master

  # List of application corresponding to different sync waves
  apps:
      # CDRs App
    - name: crds
      namespace: default
      path: argocd/bootstrap/crds
      syncWave: 0
      # External Secrets Operator
    - name: external-secrets
      namespace: external-secrets
      path: argocd/system/external-secrets
      syncWave: 1
      # Metal LB
    - name: metallb
      namespace: metallb
      path: argocd/system/metallb
      syncWave: 1
  ```

- templates/app-set.yaml

  This will create a ArgoCD application for each item in the values file under `apps` dictionary. Each of the item defined contains information about the name of the application (`name`), the namespace to be used during deployment (`namespace`), the sync-wave to be used (`syncWave`), and the path under `gitops.repo` where the application is located (`path`).
 
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
      argocd.argoproj.io/sync-wave: '{{ default 0 $app.syncWave }}'
  spec:
    destination:
      namespace: {{ $app.namespace }}
      server: https://kubernetes.default.svc
    project: default
    source:
      path: {{ $app.path }}
      repoURL: {{ $.Values.gitops.repo }}
      targetRevision: {{ $.Values.gitops.revision }}
  {{- if $app.helm }}
      helm:
  {{ toYaml $app.helm | indent 6  }}
  {{- end }}
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

{{site.data.alerts.note}}

Root application created for Pi-Cluster can be found in [/argocd/bootstrap/root]({{ site.git_address }}/tree/master/argocd/bootstrap/root)

{{site.data.alerts.end}}

#### Deploying Root application

Root application can be deployed declarative applying the following manifest file:

```yml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  destination:
    namespace: argocd
    server: https://kubernetes.default.svc
  project: default
  source:
    path: argocd/bootstrap/root
    repoURL: https://github.com/ricsanfre/pi-cluster
    targetRevision: master
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
```

### CRDs Application

Application containing all CRDs could be created and deployed in the first sync-wave. So all other applications making use of CRDs can be deployed with success even when the corresponding Controller services are not yet deployed. For example: Deploying Prometheus Operator CRDs as part of a CRDs Application, allows to deploy prometheus monitoring objects (ServiceMonitor, PodMonitor, etc) for applications that are deployed before kube-prometheus-stack application.

For an example of such CRDs application, check repository [/argocd/bootstrap/crds]({{ site.git_address }}/tree/master/argocd/bootstrap/crds).

## References

- [Argo CD Working With Helm](https://kubebyexample.com/learning-paths/argo-cd/argo-cd-working-helm)

- [ArgoCD App of Apps pattern to bootstrap de cluster](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)

- [ArgoCD SyncWaves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)

- [How to set Argo CD Application Dependencies](https://codefresh.io/blog/argo-cd-application-dependencies/)

- [How to avoid  CRD tool long error](https://www.arthurkoziel.com/fixing-argocd-crd-too-long-error/)