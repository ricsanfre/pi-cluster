---
name: Flux Change Validation
description: Use when validating repository changes against the live Flux-managed cluster from a feature or issue branch, and when reverting the Flux sync ref back to master afterwards.
---

# Flux Change Validation

Validate a branch in the live cluster without merging it, then restore the cluster to `master`.

## Preconditions

- The branch is pushed to `origin`.
- The working tree is clean (`git status`), or the remaining changes are intentional.
- Kubeconfig points at the production cluster (`kubectl config current-context`).
- The change has already passed `change-preflight`.

Destructive operations are out of scope here: this skill only changes the Flux sync ref and
reconciles.

## Procedure

### 1. Create and push the branch

```bash
git switch master
git pull --ff-only origin master
git switch -c feature/<short-description>
```

Make the change, commit, and push:

```bash
git push -u origin HEAD
```

### 2. Point the Flux instance at the branch

File: `kubernetes/platform/flux-operator/instance/overlays/prod/values.yaml`

```yaml
instance:
  sync:
    ref: refs/heads/feature/<short-description>
```

```bash
git add kubernetes/platform/flux-operator/instance/overlays/prod/values.yaml
git commit -m "chore(flux): point prod flux-instance to feature/<short-description>"
git push
```

### 3. Patch the in-cluster GitRepository and reconcile

```bash
GR_NAME="$(kubectl -n flux-system get gitrepository -o jsonpath='{range .items[?(@.spec.url=="https://github.com/ricsanfre/pi-cluster")]}{.metadata.name}{"\n"}{end}' | head -n1)"
kubectl -n flux-system patch gitrepository "${GR_NAME}" --type merge -p '{"spec":{"ref":{"branch":"feature/<short-description>"}}}'
flux reconcile source git "${GR_NAME}" -n flux-system
flux reconcile kustomization flux-system -n flux-system --with-source
```

### 4. Verify

```bash
flux get sources git -n flux-system
flux get kustomizations
flux get helmreleases -A
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -20
```

Confirm:
- the GitRepository revision matches the branch HEAD;
- `flux-system` and the changed Kustomizations are `READY=True`;
- the changed HelmReleases reached the expected revision;
- no new warning events in the affected namespaces.

Report the branch SHA that Flux is actually running.

## Revert after merge

Do this even if validation failed — leaving the cluster on a branch is never the end state.

1. Merge the PR (or close it).
2. Back on `master`, restore the ref:

   ```bash
   git switch master
   git pull --ff-only origin master
   ```

   Set `instance.sync.ref: refs/heads/master` in the same values file, commit, push.

3. Patch the in-cluster GitRepository back:

   ```bash
   kubectl -n flux-system patch gitrepository "${GR_NAME}" --type merge -p '{"spec":{"ref":{"branch":"master","name":null}}}'
   flux reconcile source git "${GR_NAME}" -n flux-system
   flux reconcile kustomization flux-system -n flux-system --with-source
   ```

4. Verify the GitRepository revision is `master` and `flux-system` is `READY=True`.

## Failure recovery

| Symptom | Check | Action |
| --- | --- | --- |
| Source `READY=False` | `flux get sources git -n flux-system`, GitRepository `status.conditions` | Branch name typo, auth, or push missing — fix the ref or push the branch |
| Root Kustomization stuck | `flux get kustomizations`, describe `flux-system` | Manifest/patch error on the branch — fix in Git, push, reconcile |
| Changed app not updating | `flux get helmreleases -A`, describe the release | Chart/values error; check the dependency Kustomization is ready |
| Reconciliation loops | `flux logs --level=error --since=10m` | Revert the ref to `master` first, then debug on the branch |

If in doubt, revert to `master` immediately and re-apply the branch after the root cause is fixed.
A cluster left tracking a stale branch will silently stop receiving changes.

## Guardrails

- Never patch the GitRepository to a branch that is not pushed.
- Never leave `instance.sync.ref` on a branch after the work is done.
- Do not use this flow to deploy a change that has not passed `change-preflight`.
- Do not force-push `master`, and do not rewrite the branch Flux is tracking while validation is
  running.
