---
title: GitOps (ArgoCD)
permalink: /docs/argocd/
description: How to apply GitOps to Pi cluster configuration using ArgoCD.
last_modified_at: "18-12-2022"
---


## Installing ArgoCD

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


## Creating Applications


TO-DO


How to avoid  CRD tool long error: https://www.arthurkoziel.com/fixing-argocd-crd-too-long-error/


### App of Apps pattern

For bootstraping the cluster [app of apps pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/) can be used. The App-of-Apps design is basically an Argo CD Application made up of other Argo CD Applications.

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


## References

- [ArgoCD App of Apps pattern to bootstrap de cluster](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)

- [ArgoCD SyncWaves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)

- [How to set Argo CD Application Dependencies](https://codefresh.io/blog/argo-cd-application-dependencies/)