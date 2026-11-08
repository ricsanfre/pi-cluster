# GitOps and Release Runbooks

## GITOPS-001 Flux Source Outage Triage

<a id="runbook-gitops-001"></a>
Runbook ID: `GITOPS-001`
Owner: Platform
Severity: `SEV-1` or `SEV-2`

Objective: Restore Git source synchronization when Flux cannot fetch repository artifacts.

Preconditions:

- Cluster admin access.
- `flux` and `kubectl` CLIs authenticated.

Procedure:

1. Check source status and failure reason.

```bash
flux get sources git -n flux-system
kubectl -n flux-system describe gitrepository flux-system
```

2. Validate controller pods and DNS/connectivity.

```bash
kubectl -n flux-system get pods
kubectl -n flux-system logs deploy/source-controller --tail=200
```

3. If credentials or repo ref changed, fix manifest/secret in Git.
4. Reconcile source and dependent kustomizations.

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization flux-system -n flux-system --with-source
```

Verify:

- `GitRepository/flux-system` shows `Ready=True`.
- Downstream Kustomizations start reconciling.

Rollback:

1. Revert the last Git change that modified source URL/ref/secret.
2. Reconcile source again.

## GITOPS-002 Kustomization Stuck or Not-Ready Triage

<a id="runbook-gitops-002"></a>
Runbook ID: `GITOPS-002`
Owner: Platform
Severity: `SEV-2`

Objective: Recover Kustomizations that are stuck or repeatedly failing.

Procedure:

1. Identify failing Kustomizations and error messages.

```bash
flux get kustomizations -n flux-system
kubectl -n flux-system describe kustomization <name>
```

2. Check dependencies and health-check expressions.
3. Inspect relevant controller logs.

```bash
kubectl -n flux-system logs deploy/kustomize-controller --tail=200
```

4. If needed, pause noisy reconciliations while fixing Git state.

```bash
flux suspend kustomization <name> -n flux-system
# apply fix in Git
flux resume kustomization <name> -n flux-system
flux reconcile kustomization <name> -n flux-system --with-source
```

Verify:

- Target Kustomization transitions to `Ready=True`.
- Dependency chain also healthy.

Rollback:

1. Revert offending commit.
2. Reconcile source and target Kustomization.

## GITOPS-003 HelmRelease Stuck or Not-Ready Triage

<a id="runbook-gitops-003"></a>
Runbook ID: `GITOPS-003`
Owner: Platform
Severity: `SEV-2`

Objective: Recover Helm releases managed by Flux when reconciliation is stuck or failing.

Preconditions:

- Cluster admin access.
- `flux`, `kubectl`, and optionally `helm` CLIs authenticated.

Procedure:

1. Identify failing HelmRelease and reason.

```bash
flux get helmreleases -A
kubectl -n <namespace> describe helmrelease <name>
```

2. Determine whether the failure is a stale-spec problem or a rollout/runtime problem.

```bash
kubectl -n <namespace> get helmrelease <name> -o jsonpath='{.metadata.generation}{"\n"}{.status.observedGeneration}{"\n"}'
kubectl -n <namespace> get helmrelease <name> -o yaml | grep -E 'chartRef:|sourceRef:|valuesFrom:|lastAttempted|message:'
```

Interpretation:

- If `metadata.generation` is ahead of `status.observedGeneration`, or the live HelmRelease spec still shows the old broken value, Flux has not synchronized the updated HelmRelease object yet.
- If `metadata.generation == status.observedGeneration`, the live HelmRelease spec is current and the failure is in the chart rollout, health checks, or Helm remediation path.

3. Check helm-controller logs for template, install, upgrade, rollback, or remediation errors.

```bash
kubectl -n flux-system logs deploy/helm-controller --tail=200
```

4. Validate chart source availability.

```bash
flux get sources helm -A
kubectl -n <namespace> get helmchart
```

5. If the HelmRelease spec is stale, inspect and reset the owning Kustomization.

```bash
kubectl -n flux-system get kustomization -o wide
kubectl -n flux-system describe kustomization <owning-kustomization>
flux suspend kustomization <owning-kustomization> -n flux-system
flux resume kustomization <owning-kustomization> -n flux-system
flux reconcile kustomization <owning-kustomization> -n flux-system --with-source
```

Expected outcome:

- The live HelmRelease spec updates to the fixed values from Git.
- `status.observedGeneration` advances to match `metadata.generation`.

6. If the HelmRelease spec is current but rollout is failing, inspect the managed workload directly.

```bash
kubectl -n <namespace> get deploy,pod,svc,ingress
kubectl -n <namespace> describe deployment <deployment-name>
kubectl -n <namespace> logs <pod-name> --all-containers --tail=200
```

Common signals:

- `Running 'upgrade' action with timeout ...` followed by `rollback` indicates Helm is applying the new spec but the workload is not becoming healthy fast enough.
- `context deadline exceeded`, readiness probe failures, or deployment `InProgress` messages indicate runtime rollout issues rather than stale Flux state.

7. Fix values, dependencies, workload readiness, or chart version in Git, then reconcile the source and HelmRelease.

```bash
flux reconcile source helm <source-name> -n <source-namespace>
flux reconcile helmrelease <name> -n <namespace> --with-source
```

For GitRepository-backed app-of-apps layouts, also reconcile the app Kustomization if needed.

```bash
flux reconcile source git <git-source-name> -n flux-system
flux reconcile kustomization <owning-kustomization> -n flux-system --with-source
```

Verify:

- HelmRelease transitions to `Ready=True`.
- `metadata.generation` and `status.observedGeneration` match.
- Target workload pods become Ready.

Rollback:

1. Revert to last known-good values/chart version in Git.
2. If the HelmRelease object is stuck on an older spec, reset and reconcile the owning Kustomization.
3. Reconcile source and HelmRelease again.

## GITOPS-004 Safe Suspend and Resume Strategy

<a id="runbook-gitops-004"></a>
Runbook ID: `GITOPS-004`
Owner: Platform
Severity: `Maintenance`

Objective: Pause and resume Flux reconciliation safely during maintenance or incident containment.

Procedure:

1. Identify the exact object set to suspend.
2. Suspend from the highest-impact leaf first to minimize churn.

```bash
flux suspend kustomization <name> -n flux-system
flux get kustomizations -n flux-system
```

3. Perform maintenance/fix while reconciliations are paused.
4. Resume in dependency order (foundations first, then dependents).

```bash
flux resume kustomization <foundation> -n flux-system
flux reconcile kustomization <foundation> -n flux-system --with-source
flux resume kustomization <dependent> -n flux-system
flux reconcile kustomization <dependent> -n flux-system --with-source
```

Verify:

- All resumed Kustomizations reach `Ready=True`.
- No repeated reconcile failures in controller logs.

Rollback:

1. Re-suspend problematic Kustomization.
2. Revert maintenance change and resume again.

## GITOPS-005 Flux Upgrade and Rollback

<a id="runbook-gitops-005"></a>
Runbook ID: `GITOPS-005`
Owner: Platform
Severity: `Maintenance` or `SEV-2`

Objective: Upgrade Flux controllers safely and recover quickly if regressions occur.

Preconditions:

- Current Flux versions recorded.
- Change window and rollback plan approved.

Procedure:

1. Capture pre-upgrade state.

```bash
flux check
flux get all -A
kubectl -n flux-system get deploy
```

2. Apply upgrade via Git-managed manifests (preferred).
3. Reconcile Flux root objects.

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization flux-system -n flux-system --with-source
```

4. Validate controllers and managed workloads.

Verify:

- Flux controllers healthy.
- Source and kustomization reconciliation continues normally.

Rollback:

1. Revert Flux manifest version bump in Git.
2. Reconcile source and flux-system Kustomization.
3. Confirm controller recovery.

## GITOPS-006 Branch-Based Live Validation Workflow

<a id="runbook-gitops-006"></a>
Runbook ID: `GITOPS-006`
Owner: Platform
Severity: `Maintenance`

Objective: Validate feature branch changes in live Flux-managed environments with controlled revert.

Procedure:

1. Create and push feature branch.
2. Point Flux instance sync ref to branch in Git.
3. Patch in-cluster `GitRepository` to branch.
4. Reconcile source and root Kustomization.

```bash
GR_NAME="$(kubectl -n flux-system get gitrepository -o jsonpath='{range .items[?(@.spec.url=="https://github.com/ricsanfre/pi-cluster")]}{.metadata.name}{"\n"}{end}' | head -n1)"
kubectl -n flux-system patch gitrepository "${GR_NAME}" --type merge -p '{"spec":{"ref":{"branch":"<feature-branch>"}}}'
flux reconcile source git "${GR_NAME}" -n flux-system
flux reconcile kustomization flux-system -n flux-system --with-source
```

5. Execute validation checklist for changed components.
6. After merge, restore branch refs to `master` and reconcile again.

Verify:

- Cluster is reconciling against intended branch.
- Expected changes are applied and healthy.

Rollback:

1. Patch `GitRepository` ref back to `master`.
2. Reconcile source and root Kustomization.

## GITOPS-007 Terraform State Lock Recovery

<a id="runbook-gitops-007"></a>
Runbook ID: `GITOPS-007`
Owner: Platform
Severity: `SEV-2`

Objective: Clear a Terraform state lock left behind by a dead tofu-controller runner, so the
`Terraform` CR, its Kustomization and the Kustomizations that depend on it can reconcile again.

Preconditions:

- `kubectl` context `picluster-prod` (`kubectl --context picluster-prod ...`).
- A `Terraform` CR reports `error acquiring the state lock`:

  ```bash
  kubectl --context picluster-prod -n flux-system get terraform
  kubectl --context picluster-prod -n flux-system get terraform <name> \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}'
  ```

- The lock is **stale**: its `Created` timestamp predates the incident and the runner pod in
  `Who` (`runner@<name>-tf-runner`) no longer exists. Do not unlock a live operation — a current
  run is visible as a running `<name>-tf-runner` pod and a `StateLocked=True LockHeld` condition.

Procedure:

1. Record the lock `ID`, `Who` and `Created` from the Ready condition message.
2. Confirm the owner is gone and read the lock object (the tofu-controller default backend is the
   Kubernetes backend, so locks are `coordination.k8s.io` Leases):

   ```bash
   kubectl --context picluster-prod -n flux-system get pods | grep <name>-tf-runner
   kubectl --context picluster-prod -n flux-system get lease lock-tfstate-default-<name>
   ```

3. Force unlock. `forceUnlock: yes` alone is **not** enough: the controller also needs
   `lockIdentifier` set to the `ID` from step 1.

   ```bash
   kubectl --context picluster-prod -n flux-system patch terraform <name> --type merge \
     -p '{"spec":{"tfstate":{"forceUnlock":"yes","lockIdentifier":"<lock-id>"}}}'
   ```

4. Trigger an immediate reconcile instead of waiting for the 30m interval:

   ```bash
   kubectl --context picluster-prod -n flux-system annotate terraform <name> \
     reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
   ```

5. Wait for the plan and, if there are pending changes, the apply:

   ```bash
   kubectl --context picluster-prod -n flux-system wait \
     --for=condition=Ready terraform/<name> --timeout=600s
   ```

6. Revert the two fields — they must not stay armed:

   ```bash
   kubectl --context picluster-prod -n flux-system patch terraform <name> --type merge \
     -p '{"spec":{"tfstate":{"forceUnlock":"no","lockIdentifier":null}}}'
   ```

   The generation change triggers one more plan; wait for `Ready=True` again.

Verify:

- `Terraform` CR: `Ready=True`, reason `TerraformPlannedNoChanges` or `TerraformAppliedSucceed`.
- The owning Kustomization is `READY=True` and its dependants stop reporting a dependency error.
- `kubectl get lease lock-tfstate-default-<name>` shows an empty `HOLDER` (the Lease object stays).

Rollback:

1. Re-apply step 6 in case the revert patch is interrupted; the default is `forceUnlock: no`.
2. If the plan fails for a different reason, work from the new message — the unlock is one-way but
   the state itself is untouched.
3. Never set `forceUnlock: yes` or `auto` in Git: it would disable locking for every reconcile.
   `auto` unlocks without an identifier and is only appropriate when no other system can be using
   the state.

References:

- `kubernetes/platform/elastic-stack/config/base/terraform.yaml`,
  `kubernetes/platform/keycloak/config/base/terraform.yaml`
- [tofu-controller documentation](https://flux-iac.github.io/tofu-controller/)
- [Terraform state locking and force-unlock](https://developer.hashicorp.com/terraform/language/state/locking)
