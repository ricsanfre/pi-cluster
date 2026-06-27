#!/usr/bin/env bash
# recover-valkey-stale-ip.sh
#
# Detect and recover from stale node IPs in a Valkey cluster managed by
# the valkey-operator. Caused by pod restarts that change IPs while
# nodes.conf on PVC retains the old addresses.
#
# Checks BOTH:
#   - Self-IPs:  each pod's own IP in nodes.conf vs its actual pod IP
#   - Peer-IPs:  IPs each pod has for its peers in nodes.conf vs their actual IPs
#
# Even with operator ≥v0.2.0 (which injects --cluster-announce-ip),
# nodes.conf on pre-existing PVCs can retain stale peer addresses.
#
# Safe to run repeatedly — exits cleanly if the cluster is already healthy.
#
# Usage:
#   bash scripts/recover-valkey-stale-ip.sh [--namespace <ns>] [--cluster <name>]
#
# Requires: kubectl, jq

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
NAMESPACE="${NAMESPACE:-databases}"
CLUSTER="${CLUSTER:-valkey}"
CONTAINER="server"

# ── Help ────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# //'
    echo ""
    echo "Environment variables:"
    echo "  NAMESPACE   Kubernetes namespace (default: databases)"
    echo "  CLUSTER     ValkeyCluster name   (default: valkey)"
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --namespace|-n) NAMESPACE="$2"; shift 2 ;;
        --cluster|-c)   CLUSTER="$2";   shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Prerequisites ───────────────────────────────────────────────────────────
if ! command -v kubectl &>/dev/null; then
    log_error "kubectl not found in PATH"
    exit 1
fi

if ! kubectl get ns "$NAMESPACE" &>/dev/null; then
    log_error "Namespace '$NAMESPACE' not found or not accessible"
    exit 1
fi

# ── Check if the ValkeyCluster exists ───────────────────────────────────────
if ! kubectl get valkeycluster "$CLUSTER" -n "$NAMESPACE" &>/dev/null; then
    log_error "ValkeyCluster '$CLUSTER' not found in namespace '$NAMESPACE'"
    exit 1
fi

# ── Quick health check — skip if already ready ──────────────────────────────
STATE=$(kubectl get valkeycluster "$CLUSTER" -n "$NAMESPACE" \
    -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")

if [[ "$STATE" == "Ready" ]]; then
    READY_SHARDS=$(kubectl get valkeycluster "$CLUSTER" -n "$NAMESPACE" \
        -o jsonpath='{.status.readyShards}')
    log_info "Cluster is already Ready ($READY_SHARDS shards healthy). Nothing to do."
    exit 0
fi

log_info "Cluster state: $STATE — checking for stale IP condition..."

# ── Discover pods ───────────────────────────────────────────────────────────
PODS=$(kubectl get pods -n "$NAMESPACE" \
    -l "valkey.io/cluster=$CLUSTER" \
    -o json 2>/dev/null)

if [[ -z "$PODS" || "$PODS" == "null" ]]; then
    log_error "No pods found for cluster '$CLUSTER'"
    exit 1
fi

POD_NAMES=($(echo "$PODS" | jq -r '.items[].metadata.name'))
POD_IPS=($(echo "$PODS" | jq -r '.items[].status.podIP'))

if [[ ${#POD_NAMES[@]} -eq 0 ]]; then
    log_error "No pods found with valkey.io/cluster=$CLUSTER label"
    exit 1
fi

log_info "Found ${#POD_NAMES[@]} pod(s): ${POD_NAMES[*]}"

# ── Build pod name → actual IP map ─────────────────────────────────────────
declare -A POD_IP_MAP
for i in "${!POD_NAMES[@]}"; do
    POD_IP_MAP["${POD_NAMES[$i]}"]="${POD_IPS[$i]}"
done

# ── Read nodes.conf from each pod and build node-ID → actual IP map ────────
# Each pod's 'myself' line gives us the 40-char node ID that both Valkey and
# the operator use. We need this to cross-reference peer entries.
declare -A NODE_ID_TO_POD
declare -A NODE_ID_TO_ACTUAL_IP
declare -A POD_TO_NODE_ID

for POD in "${POD_NAMES[@]}"; do
    NODES_CONF=$(kubectl exec -n "$NAMESPACE" "$POD" -c "$CONTAINER" \
        -- cat /data/nodes.conf 2>/dev/null || echo "")

    if [[ -z "$NODES_CONF" ]]; then
        log_warn "$POD: cannot read nodes.conf (no persistence?); skipping"
        continue
    fi

    NODE_ID=$(echo "$NODES_CONF" | awk '/myself/ {print $1}')
    if [[ -z "$NODE_ID" ]]; then
        log_warn "$POD: could not parse node ID from nodes.conf; skipping"
        continue
    fi

    NODE_ID_TO_POD["$NODE_ID"]="$POD"
    NODE_ID_TO_ACTUAL_IP["$NODE_ID"]="${POD_IP_MAP[$POD]}"
    POD_TO_NODE_ID["$POD"]="$NODE_ID"
done

# ── Check each pod for stale IPs (self + peer) ─────────────────────────────
STALE_SELF=0
STALE_PEER=0
declare -A STALE_SELF_PODS
declare -A STALE_PEER_DETAILS  # key="pod→peer_node_id" value="configured_ip"

for POD in "${POD_NAMES[@]}"; do
    NODES_CONF=$(kubectl exec -n "$NAMESPACE" "$POD" -c "$CONTAINER" \
        -- cat /data/nodes.conf 2>/dev/null || echo "")

    if [[ -z "$NODES_CONF" ]]; then
        continue
    fi

    ACTUAL_IP="${POD_IP_MAP[$POD]}"

    # ── Check self-IP ──────────────────────────────────────────────────
    SELF_IP=$(echo "$NODES_CONF" | awk '/myself/ {print $2}' | cut -d: -f1)
    if [[ -n "$SELF_IP" && "$SELF_IP" != "$ACTUAL_IP" ]]; then
        STALE_SELF=$((STALE_SELF + 1))
        STALE_SELF_PODS["$POD"]=1
        log_warn "$POD: stale self-IP — nodes.conf=$SELF_IP, actual=$ACTUAL_IP"
    else
        log_info "$POD: self-IP ok ($ACTUAL_IP)"
    fi

    # ── Check peer-IPs ─────────────────────────────────────────────────
    # Parse all non-myself, non-comment lines from nodes.conf.
    # Format: <node-id> <ip>:<port>@<bus-port> [flags...]
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^vars ]] && continue

        PEER_NODE_ID=$(echo "$line" | awk '{print $1}')
        PEER_CONFIGURED_IP=$(echo "$line" | awk '{print $2}' | cut -d: -f1)

        # Skip if this peer is ourselves (caught above)
        [[ "$line" =~ myself ]] && continue

        # Look up this peer's actual IP by node ID
        PEER_ACTUAL_IP="${NODE_ID_TO_ACTUAL_IP[$PEER_NODE_ID]:-}"

        if [[ -z "$PEER_ACTUAL_IP" ]]; then
            # Node ID unknown — could be a stale reference to a deleted pod
            if [[ -n "$PEER_NODE_ID" && -n "$PEER_CONFIGURED_IP" ]]; then
                STALE_PEER=$((STALE_PEER + 1))
                STALE_PEER_DETAILS["$POD→$PEER_NODE_ID"]="$PEER_CONFIGURED_IP (node unknown)"
                log_warn "$POD: stale peer entry — node $PEER_NODE_ID at $PEER_CONFIGURED_IP (node ID not found in cluster)"
            fi
            continue
        fi

        if [[ "$PEER_CONFIGURED_IP" != "$PEER_ACTUAL_IP" ]]; then
            STALE_PEER=$((STALE_PEER + 1))
            STALE_PEER_DETAILS["$POD→$PEER_NODE_ID"]="$PEER_CONFIGURED_IP → $PEER_ACTUAL_IP"
            PEER_POD="${NODE_ID_TO_POD[$PEER_NODE_ID]:-$PEER_NODE_ID}"
            log_warn "$POD: stale peer IP for $PEER_POD — nodes.conf=$PEER_CONFIGURED_IP, actual=$PEER_ACTUAL_IP"
        fi
    done <<< "$(echo "$NODES_CONF" | grep -v '^myself' | grep -E '^[a-f0-9]{40} ' || true)"
done

TOTAL_STALE=$((STALE_SELF + STALE_PEER))

if [[ $TOTAL_STALE -eq 0 ]]; then
    log_info "All pods have correct self and peer IPs in nodes.conf."
    log_info "Cluster state is '$STATE' but not caused by stale IPs. Check operator logs:"
    echo "  kubectl logs -n $NAMESPACE deployment/valkey-operator --tail 30"
    exit 0
fi

log_info "Found $TOTAL_STALE stale IP(s): $STALE_SELF self, $STALE_PEER peer. Applying fix..."

# ── Discover primary and replica roles ─────────────────────────────────────
PRIMARY_POD=""
REPLICA_PODS=()

for POD in "${POD_NAMES[@]}"; do
    ROLE=$(kubectl exec -n "$NAMESPACE" "$POD" -c "$CONTAINER" \
        -- valkey-cli INFO replication 2>/dev/null | grep '^role:' | cut -d: -f2 || echo "")

    case "$ROLE" in
        master)  PRIMARY_POD="$POD" ;;
        slave)   REPLICA_PODS+=("$POD") ;;
        *)       log_warn "$POD: unknown role '$ROLE'";;
    esac
done

# ── Step 1: Set cluster-announce-ip on all pods ───────────────────────────
for POD in "${POD_NAMES[@]}"; do
    IP="${POD_IP_MAP[$POD]}"
    log_info "Setting cluster-announce-ip=$IP on $POD..."
    kubectl exec -n "$NAMESPACE" "$POD" -c "$CONTAINER" \
        -- valkey-cli CONFIG SET cluster-announce-ip "$IP" 2>&1 \
        | grep -v '^OK$' || true
done

# ── Step 2: CLUSTER FORGET stale entries (when node ID is unknown) ────────
for DETAIL in "${!STALE_PEER_DETAILS[@]}"; do
    POD="${DETAIL%%→*}"
    STALE_NODE_ID="${DETAIL##*→}"
    DESC="${STALE_PEER_DETAILS[$DETAIL]}"

    # Only FORGET if the node ID is unknown (orphaned entry from deleted pod)
    if [[ "$DESC" == *"(node unknown)"* ]]; then
        log_info "CLUSTER FORGET stale node $STALE_NODE_ID on $POD..."
        kubectl exec -n "$NAMESPACE" "$POD" -c "$CONTAINER" \
            -- valkey-cli CLUSTER FORGET "$STALE_NODE_ID" 2>&1 \
            | grep -v '^OK$' || true
    fi
done

# ── Step 3: CLUSTER MEET to re-establish topology ─────────────────────────
if [[ -n "$PRIMARY_POD" ]]; then
    for REPLICA_POD in "${REPLICA_PODS[@]}"; do
        REPLICA_IP="${POD_IP_MAP[$REPLICA_POD]}"
        log_info "CLUSTER MEET from $PRIMARY_POD → $REPLICA_POD ($REPLICA_IP:6379)..."
        kubectl exec -n "$NAMESPACE" "$PRIMARY_POD" -c "$CONTAINER" \
            -- valkey-cli CLUSTER MEET "$REPLICA_IP" 6379 2>&1 \
            | grep -v '^OK$' || true
    done
elif [[ ${#POD_NAMES[@]} -ge 2 ]]; then
    # No clear primary found; try CLUSTER MEET from first pod to all others
    FIRST_POD="${POD_NAMES[0]}"
    for POD in "${POD_NAMES[@]:1}"; do
        IP="${POD_IP_MAP[$POD]}"
        log_info "CLUSTER MEET from $FIRST_POD → $POD ($IP:6379)..."
        kubectl exec -n "$NAMESPACE" "$FIRST_POD" -c "$CONTAINER" \
            -- valkey-cli CLUSTER MEET "$IP" 6379 2>&1 \
            | grep -v '^OK$' || true
    done
fi

# ── Wait for cluster to stabilize ──────────────────────────────────────────
log_info "Waiting for cluster to reach Ready state..."
MAX_WAIT=120
INTERVAL=5
ELAPSED=0

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    STATE=$(kubectl get valkeycluster "$CLUSTER" -n "$NAMESPACE" \
        -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")

    if [[ "$STATE" == "Ready" ]]; then
        READY_SHARDS=$(kubectl get valkeycluster "$CLUSTER" -n "$NAMESPACE" \
            -o jsonpath='{.status.readyShards}')
        TOTAL_SHARDS=$(kubectl get valkeycluster "$CLUSTER" -n "$NAMESPACE" \
            -o jsonpath='{.status.shards}')
        echo ""
        log_info "Cluster is Ready! ($READY_SHARDS/$TOTAL_SHARDS shards healthy)"
        break
    fi

    printf "  [%3ds] state=%s...\n" "$ELAPSED" "$STATE"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ "$STATE" != "Ready" ]]; then
    echo ""
    log_error "Cluster did not reach Ready state after ${MAX_WAIT}s"
    log_error "Check operator logs: kubectl logs -n $NAMESPACE deployment/valkey-operator --tail 50"
    exit 1
fi

# ── Final verification ──────────────────────────────────────────────────────
echo ""
log_info "━━━ Final replication status ━━━"

for i in "${!POD_NAMES[@]}"; do
    POD="${POD_NAMES[$i]}"
    echo ""
    echo "  $POD:"
    kubectl exec -n "$NAMESPACE" "$POD" -c "$CONTAINER" \
        -- valkey-cli INFO replication 2>/dev/null \
        | grep -E '^role:|^master_host:|^master_link_status:|^connected_slaves:|^slave[0-9]:' \
        | while read -r line; do echo "    $line"; done
done

echo ""
log_info "Recovery complete."
