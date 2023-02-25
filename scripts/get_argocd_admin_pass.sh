#!/usr/bin/env bash

echo "Getting ArgoCD admin password:" >&2
export KUBECONFIG=./ansible-runner/runner/.kube/config
kubectl get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' -n argocd | base64 -d;echo