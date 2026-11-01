# Nodes and Capacity Runbooks

## CLUSTER-010 Node Replacement Workflow

<a id="runbook-cluster-010"></a>
Runbook ID: `CLUSTER-010`
Owner: Platform
Severity: `SEV-2` or `Maintenance`

Objective: Replace failed/degraded node with minimal disruption.

Procedure:

1. Cordon and drain old node if still reachable.

```bash
kubectl cordon <old-node>
kubectl drain <old-node> --ignore-daemonsets --delete-emptydir-data --grace-period=60 --timeout=15m
```

2. Remove old node object if permanently retired.

```bash
kubectl delete node <old-node>
```

3. Provision replacement host (networking, OS baseline).
4. Join replacement node using standard cluster automation.
5. Validate workload redistribution and storage attachment behavior.

Verify:

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
```

Rollback:

1. Keep workloads on remaining nodes if replacement join fails.
2. Re-attempt join after host/network fix.

## CLUSTER-011 Planned Node Drain and Maintenance

<a id="runbook-cluster-011"></a>
Runbook ID: `CLUSTER-011`
Owner: Platform
Severity: `Maintenance`

Objective: Safely perform node maintenance with minimal disruption.

Preconditions:

- Maintenance window approved.
- Workloads with PDB constraints reviewed.

Procedure:

1. Cordon node.

```bash
kubectl cordon <node-name>
```

2. Drain node.

```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --grace-period=60 --timeout=10m
```

3. Perform host maintenance (kernel patch, reboot, disk ops, etc.).
4. Bring node back and uncordon.

```bash
kubectl uncordon <node-name>
```

Verify:

```bash
kubectl get nodes
kubectl get pods -A -o wide | grep <node-name>
```

Rollback:

1. If drain is blocked by PDB, abort drain and re-open scheduling (`uncordon`).
2. If node unhealthy after maintenance, keep cordoned and migrate workloads.

## CLUSTER-012 Node Disk Pressure Response

<a id="runbook-cluster-012"></a>
Runbook ID: `CLUSTER-012`
Owner: Platform
Severity: `SEV-2`

Objective: Recover scheduling and workload health when nodes are tainted with disk pressure.

Procedure:

1. Identify impacted nodes and pods.

```bash
kubectl get nodes
kubectl describe node <node-name> | grep -i -E 'DiskPressure|taint'
kubectl get events -A | grep -i disk-pressure
```

2. Free disk space on affected nodes (logs, images, orphaned artifacts).
3. Verify kubelet and container runtime reclaim behavior.
4. If needed, drain and reboot node for cleanup.
5. Confirm taint removal and pod rescheduling.

Verify:

- Node condition `DiskPressure=False`.
- Pending pods are scheduled.
- Storage-related alerts clear.

Rollback:

1. If cleanup fails, cordon node and evacuate workloads.
2. Replace node using `CLUSTER-010` workflow.
