#!/bin/bash
#
# Create the k3d development cluster.
#
# Tunables (environment):
#   K3D_SERVERS        number of k3d servers (default: 1)
#   K3D_AGENTS         number of k3d agents (default: 0)
#   K3S_IMAGE          k3s image (default: rancher/k3s:v1.37.1-k3s1, matching prod)
#   K3D_SERVER_MEMORY  memory cap for each server (default: 5g)
#   K3D_AGENT_MEMORY   memory cap for each agent (default: 3g)
#   K3D_CLUSTER        k3d cluster name (default: picluster)
#
set -euo pipefail

SCRIPT="$(readlink -f "$0")"
WORK_DIR="$(dirname "$SCRIPT")"

K3D_DIR="$WORK_DIR/k3d-cluster"
TMPL_K3D_CONFIG_YAML="$K3D_DIR/k3d-cluster.yaml.tmpl"
K3D_CONFIG_YAML="$K3D_DIR/k3d-cluster.yaml"
DATA_JSON="$WORK_DIR/data.json"

K3D_CLUSTER="${K3D_CLUSTER:-picluster}"
K3D_SERVERS="${K3D_SERVERS:-1}"
K3D_AGENTS="${K3D_AGENTS:-0}"
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:v1.37.1-k3s1}"
K3D_SERVER_MEMORY="${K3D_SERVER_MEMORY:-5g}"
K3D_AGENT_MEMORY="${K3D_AGENT_MEMORY:-3g}"

# Cluster network configuration
CLUSTER_SUBNET="10.42.0.0/16"
SERVICE_SUBNET="10.43.0.0/16"

# Docker network configuration
NETWORK_NAME="picluster"
NETWORK_TYPE="bridge"
NET_PREFIX="172.30"
NETWORK_SUBNET="$NET_PREFIX.0.0/16"
NETWORK_GATEWAY="$NET_PREFIX.0.1"
NETWORK_IP_RANGE="$NET_PREFIX.0.0/17"
HOST_IP="127.$NET_PREFIX.1"

create_network() {
  local network_id
  network_id="$(
    docker network inspect "$NETWORK_NAME" --format "{{.Id}}" 2>/dev/null
  )" || true
  if [ "$network_id" ]; then
    echo "Using existing network '$NETWORK_NAME' with id '$network_id'"
  else
    echo "Creating network '$NETWORK_NAME' in docker"
    docker network create \
      --driver "$NETWORK_TYPE" \
      --subnet "$NETWORK_SUBNET" \
      --gateway "$NETWORK_GATEWAY" \
      --ip-range "$NETWORK_IP_RANGE" \
      "$NETWORK_NAME"
  fi
}

cluster_exists() {
  k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$K3D_CLUSTER"
}

create_cluster() {
  echo "Creating dev cluster '$K3D_CLUSTER' (servers=$K3D_SERVERS agents=$K3D_AGENTS image=$K3S_IMAGE)"

  cat >"$DATA_JSON" <<EOF
{"k3d_dir":"${K3D_DIR}", "host_ip":"${HOST_IP}", "cluster_subnet":"${CLUSTER_SUBNET}", "service_subnet":"${SERVICE_SUBNET}", "servers":${K3D_SERVERS}, "agents":${K3D_AGENTS}, "image":"${K3S_IMAGE}"}
EOF

  # `tmpl` renders to the output path without the `.tmpl` suffix.
  tmpl -data=@"$DATA_JSON" "$TMPL_K3D_CONFIG_YAML"

  local args=(
    cluster create
    --config "$K3D_CONFIG_YAML"
    --servers-memory "$K3D_SERVER_MEMORY"
  )
  if [ "$K3D_AGENTS" -gt 0 ]; then
    args+=(--agents-memory "$K3D_AGENT_MEMORY")
  fi

  K3D_FIX_MOUNTS=1 K3D_FIX_DNS=0 k3d "${args[@]}"
}

assert_context() {
  local expected="k3d-$K3D_CLUSTER"
  local current
  current="$(kubectl config current-context 2>/dev/null || true)"
  if [ "$current" != "$expected" ]; then
    echo "Switching kubectl context from '${current:-<none>}' to '$expected'"
    kubectl config use-context "$expected" >/dev/null
  fi
  current="$(kubectl config current-context)"
  if [ "$current" != "$expected" ]; then
    echo "ERROR: kubectl context is '$current', expected '$expected'" >&2
    exit 1
  fi
  echo "kubectl context: $current"
}

# MAIN
create_network

if cluster_exists; then
  echo "Cluster '$K3D_CLUSTER' already exists; skipping creation"
else
  create_cluster
fi

assert_context

# The node stays NotReady until a CNI is installed. Wait only for the API
# server here; dev/bootstrap.sh installs Cilium and then waits for the node.
echo "Waiting for the Kubernetes API"
for i in $(seq 1 60); do
  if kubectl get --raw /readyz >/dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "ERROR: Kubernetes API did not become ready" >&2
    exit 1
  fi
  sleep 2
done

echo "Cluster info"
kubectl cluster-info
