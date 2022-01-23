---
title: Kubernetes commands
permalink: /docs/k8s_commands/
redirect_from: /docs/k8s_commands.md
---


# Kubernetes commads


## List PODs running on an specific node
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=<node_name>

## List Taints of all nodes

kubectl describe nodes | grep Taint


## Restart pod

kubectl rollout restart daemonset/deployment/statefulset <daemonset/deployment/statefulset>