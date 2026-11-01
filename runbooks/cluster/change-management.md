# Upgrades and Change Management Runbooks

## CHANGE-001 Pre-Change Go/No-Go Checklist

<a id="runbook-change-001"></a>
Runbook ID: `CHANGE-001`
Owner: Platform
Severity: `Maintenance`

Objective: Prevent risky production changes by validating prerequisites before execution.

Checklist:

1. Scope and rollback documented.
2. Maintenance window approved and communicated.
3. Backup and restore point validated for impacted stateful services.
4. Current cluster and Flux health green.

```bash
kubectl get nodes
flux get kustomizations -n flux-system
```

5. Required credentials and access tested.
6. Observability and alert routing confirmed.
7. Change owner and incident channel assigned.

Decision:

- `GO` only if all checks pass.
- `NO-GO` if rollback path or backup verification is missing.

## CHANGE-002 Post-Change Validation Checklist

<a id="runbook-change-002"></a>
Runbook ID: `CHANGE-002`
Owner: Platform
Severity: `Maintenance`

Objective: Confirm change success and detect regressions quickly.

Procedure:

1. Validate control plane and node health.

```bash
kubectl get nodes
kubectl get pods -A
```

2. Validate Flux reconciliation health.

```bash
flux get sources git -n flux-system
flux get kustomizations -n flux-system
```

3. Validate impacted component SLO/smoke tests.
4. Review warning/error logs for involved controllers for 15-30 minutes.
5. Close maintenance communication with status and findings.

Rollback trigger:

- If critical regressions appear and cannot be mitigated quickly, execute defined rollback immediately.
