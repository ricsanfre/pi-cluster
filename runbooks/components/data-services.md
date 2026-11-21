# Kafka and Data Services Runbooks

Operational procedures for the data services running in the cluster.

## VALKEY-001 Valkey Cluster Stuck in Reconciling (Stale Node IPs)

<a id="runbook-valkey-001"></a>
Runbook ID: `VALKEY-001`
Owner: Platform
Severity: `SEV-2`

Objective: Recover a `ValkeyCluster` that stays in `Reconciling` after its pods restart
with new IPs, because `nodes.conf` on the PVC still holds stale addresses.

Preconditions:
- `kubectl` access to the `databases` namespace.
- Ability to `exec` into the `server` container of the Valkey pods.
- `jq` for the automated recovery script.

Symptoms:

```shell
$ kubectl get valkeycluster -n databases
NAME     STATE          REASON         SHARDS   READY SHARDS   AGE
valkey   Reconciling    Reconciling    1        0              2d
```

- `Ready` condition `False`, message `"Waiting for replicas to sync with primary"`.
- Operator logs repeat `"replica not yet in sync, requeue.."`.
- Replica logs show connection failures to a stale primary IP.

Root cause: on restart, each pod gets a new CNI IP, but `nodes.conf` is persisted on the
PVC with the previous addresses. The operator detects the mismatch but, especially on
clusters created with older operator versions (v0.1.0), does not issue corrective
`CLUSTER MEET` / `CLUSTER FORGET` commands. Operator v0.2.0 and later inject
`--cluster-announce-ip $(POD_IP)` and fix self-IP staleness; **peer** IPs on pre-existing
PVCs can still be stale.

Procedure:

1. Verify the stale IP condition.

```shell
kubectl get pods -n databases -l valkey.io/cluster=valkey -o wide

kubectl exec -n databases valkey-valkey-0-0-0 -c server -- valkey-cli INFO replication
kubectl exec -n databases valkey-valkey-0-1-0 -c server -- valkey-cli INFO replication

kubectl exec -n databases valkey-valkey-0-0-0 -c server -- cat /data/nodes.conf
kubectl exec -n databases valkey-valkey-0-1-0 -c server -- cat /data/nodes.conf
```

2. Fix the topology at runtime.

```shell
PRIMARY_IP=$(kubectl get pod -n databases valkey-valkey-0-0-0 -o jsonpath='{.status.podIP}')
REPLICA_IP=$(kubectl get pod -n databases valkey-valkey-0-1-0 -o jsonpath='{.status.podIP}')

kubectl exec -n databases valkey-valkey-0-0-0 -c server -- valkey-cli CONFIG SET cluster-announce-ip "$PRIMARY_IP"
kubectl exec -n databases valkey-valkey-0-1-0 -c server -- valkey-cli CONFIG SET cluster-announce-ip "$REPLICA_IP"

kubectl exec -n databases valkey-valkey-0-0-0 -c server -- valkey-cli CLUSTER MEET "$REPLICA_IP" 6379
```

3. Or use the automated, idempotent recovery script (checks both self-IPs and peer-IPs):

```shell
bash scripts/recover-valkey-stale-ip.sh --namespace databases --cluster valkey
```

4. Apply the permanent fix when the cluster is healthy: recreate the `ValkeyCluster`
   (or its PVCs) after upgrading the operator, so `nodes.conf` starts with correct
   addresses.

Verify:
- `kubectl get valkeycluster -n databases valkey` shows `STATE=Ready`,
  `READY SHARDS=1`.
- `INFO replication` shows `connected_slaves:1` on the primary and
  `master_link_status:up` on the replica.
- `scripts/recover-valkey-stale-ip.sh` exits with a no-op on a healthy cluster.

Rollback:
1. The `CONFIG SET` and `CLUSTER MEET` changes are runtime-only; a pod restart returns
   the cluster to its previous (broken) topology.
2. No data is deleted by this procedure. The permanent fix recreates the PVCs, so take
   a backup first if the data matters.

References:
- `scripts/recover-valkey-stale-ip.sh` - automated detection and recovery.
- `docs/_docs/databases.md` - Valkey operator configuration and generic troubleshooting.
- Upstream: <https://github.com/valkey-io/valkey-operator>
