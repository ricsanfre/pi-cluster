#!/usr/bin/env bash

echo "Getting Elastic admin password:" >&2
export KUBECONFIG=./ansible-runner/runner/.kube/config
kubectl get secret efk-es-elastic-user -o jsonpath='{.data.elastic}' -n logging | base64 -d;echo