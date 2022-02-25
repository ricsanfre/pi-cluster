---
title: Kubernetes commands
permalink: /docs/k8s-commands/
---


## List PODs running on an specific node

```shell
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=<node_name>
```

## List Taints of all nodes

```shell
kubectl describe nodes | grep Taint
```

## Restart pod

```shell
kubectl rollout restart daemonset/deployment/statefulset <daemonset/deployment/statefulset>
```