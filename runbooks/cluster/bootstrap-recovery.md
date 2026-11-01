# Bootstrap and Recovery Runbooks

## CLUSTER-001 Full Cluster Bootstrap from Zero

<a id="runbook-cluster-001"></a>
Runbook ID: `CLUSTER-001`
Owner: Platform
Severity: `Maintenance`

Objective: Build a fresh cluster from bare hosts using repository automation.

Preconditions:

- Inventory and host access validated.
- Required local secrets and credentials available.
- Maintenance window approved.

Procedure:

1. Bootstrap Ansible runner.

```bash
make ansible-runner-setup
./ansible-runner/ansible-runner.sh ansible-playbook --version
```

2. Deploy external services baseline.

```bash
make external-services
```

3. Install and bootstrap K3s.

```bash
make k3s-install
make k3s-bootstrap
```

4. Reconcile Flux root Kustomization.

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization flux-system -n flux-system --with-source
```

5. Verify infra and app reconciliation.

```bash
flux get kustomizations -A
kubectl get nodes
kubectl get pods -A
```

Verify:

- All nodes Ready.
- Core platform Kustomizations Ready.
- No critical pod crashloops in platform namespaces.

Rollback:

1. If bootstrap fails before production data import, re-run from clean hosts.
2. If partial failures, repair stage-by-stage (external services, k3s, flux).

## CLUSTER-002 Disaster Recovery from Git and Backups

<a id="runbook-cluster-002"></a>
Runbook ID: `CLUSTER-002`
Owner: Platform
Severity: `SEV-1`

Objective: Recover cluster functionality after catastrophic failure using Git state and backup systems.

Preconditions:

- Access to Git repository and backup stores (Velero, CNPG, MinIO/Vault backups).
- New or repaired host infrastructure available.

Procedure:

1. Rebuild external services first (Vault, MinIO, DNS if needed).
2. Restore critical secrets/config state (Vault restore or re-seed).
3. Reinstall K3s and bootstrap Flux.
4. Reconcile platform in dependency order.
5. Restore stateful namespaces from backups where needed.

Suggested command checkpoints:

```bash
make external-services
make k3s-install
make k3s-bootstrap
flux get kustomizations -A
velero backup get
```

Verify:

- Control plane stable.
- Flux source and root Kustomizations Ready.
- Restored stateful apps pass smoke tests.

Rollback:

1. If a restore set is corrupt, recover from previous backup point.
2. If secret restore is inconsistent, suspend dependent apps and re-seed secrets first.
