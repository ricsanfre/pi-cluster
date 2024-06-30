#!/bin/bash

set -e

# Compute WORK_DIR
SCRIPT="$(readlink -f "$0")"
WORK_DIR="$(dirname "$SCRIPT")"
# WORK_DIR_RELPATH=".."
# WORK_DIR="$(readlink -f "$SCRIPT_DIR/$WORK_DIR_RELPATH")"
TMPL_DIR="$WORK_DIR/tmpl"
YAML_DIR="$WORK_DIR/yaml"

# Go templates
TMPL_K3D_CONFIG_YAML="$TMPL_DIR/k3d-cluster.yaml.tmpl"
K3D_CONFIG_YAML="$TMPL_DIR/k3d-cluster.yaml"

# Cluster network configuraiton
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
#HOST_IP="127.0.0.1"

# LoadBalancer CIDR
LB_POOL_CDIR="$NET_PREFIX.200.0/24"
LB_POOL_RANGE="$NET_PREFIX.200.1-$NET_PREFIX.200.254"


create_network() {
  NETWORK_ID="$(
    docker network inspect "$NETWORK_NAME" --format "{{.Id}}" 2>/dev/null
  )" || true
  if [ "$NETWORK_ID" ]; then
    echo "Using existing network '$NETWORK_NAME' with id '$NETWORK_ID'"
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

create_cluster() {
  echo "Creating dev cluster"
  
  echo '{"work_dir":"'${WORK_DIR}'", "host_ip":"'${HOST_IP}'", "cluster_subnet":"'${CLUSTER_SUBNET}'", "service_subnet":"'${SERVICE_SUBNET}'"}' > data.json
  
  tmpl -data=@data.json "$TMPL_K3D_CONFIG_YAML"

  K3D_FIX_MOUNTS=1 k3d cluster create -c "$K3D_CONFIG_YAML"
  
  echo "Cluster info"
  kubectl cluster-info
}

master_node_ip() {
  # If we are not running kube-proxy the cilium Pods can't reach the api server
  # because the in-cluster service can't be reached, to fix the issue we use an
  # internal IP that the pods can reach, in this case we get the internal IP of
  # the master node container
  MASTER_NODE="node/k3d-$NETWORK_NAME-server-0";
  kubectl get "$MASTER_NODE" -o wide --no-headers |
    awk '{ print $6 }'
}

# MAIN
create_network
create_cluster

MASTER_NODE_IP="$(master_node_ip)"
echo "Master node IP: $MASTER_NODE_IP"



