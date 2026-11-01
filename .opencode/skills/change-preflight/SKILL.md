---
name: Change Preflight
description: Use before committing or opening a PR to validate the touched area — YAML lint, Ansible syntax check, Terraform validate/fmt, Kustomize build, and the docs site build — without applying anything.
---

# Change Preflight

The gate between "I edited files" and "this is ready to commit". Every check here is read-only: no
`tofu apply`, no `kubectl apply`, no reconcile.

## 1. Scope the change

```bash
git status --short
git diff --stat
```

Map changed paths to checks. Run only what the diff touches, plus the YAML lint baseline.

| Changed path | Required check |
| --- | --- |
| Any `*.yml` / `*.yaml` | `make lint-ci` |
| `ansible/**` | `make lint-ci` + Ansible syntax check |
| `terraform/<module>/**` | `tofu init -backend=false && tofu validate && tofu fmt -check` |
| `kubernetes/**` | `kubectl kustomize` on each touched overlay |
| `docs/**` | `bundle exec jekyll build` |
| `runbooks/**` | Catalog link + anchor check |
| `AGENTS.md`, `.opencode/**` | No build check; verify paths and commands are real |

`make lint-ci` failing on files you did not touch is informational. Report it, do not fix it silently.

## 2. YAML lint

```bash
make lint-ci
```

CI runs `cd ansible && yamllint .`; this target is the parity check. If the runner is not built yet,
`make ansible-runner-setup` first, or use `make ansible-local-lint`.

## 3. Ansible syntax check

For each touched playbook:

```bash
./ansible-runner/ansible-runner.sh ansible-playbook --syntax-check <playbook>.yml
```

This catches undefined includes and malformed plays. It does not resolve variables or connect to
hosts — that is expected.

## 4. Terraform validation

Run inside the runner for each touched module (`elastic`, `keycloak`, `minio`, `vault`):

```bash
./ansible-runner/ansible-runner.sh bash -lc 'cd /terraform/<module> && tofu init -backend=false -input=false && tofu validate && tofu fmt -check'
```

`fmt -check` fails on unformatted files without modifying them. Do not run `init` without
`-backend=false` — it would try to reach the real state backend.

## 5. Kubernetes / Flux build

Render each touched overlay. This catches Kustomize patch and resource reference errors before Flux
does:

```bash
kubectl kustomize kubernetes/platform/<service>/app/overlays/<env>
kubectl kustomize kubernetes/clusters/<env>/infra
```

Check the output contains the expected namespace, HelmRelease, and changed keys. For a value change,
grep the rendered output for the new value rather than eyeballing the whole document.

If the change adds or removes a service, also confirm the cluster wiring in
`kubernetes/clusters/<env>/{infra,apps}/kustomization.yaml`.

## 6. Docs build

When `docs/` changed:

```bash
cd docs
bundle config set --local path 'vendor/bundle'
bundle install
bundle exec jekyll build
```

A Liquid error, a bad include, or a missing `_data` entry fails the build. Also confirm a new page is
registered in `docs/_data/docs.yml`, otherwise it will not appear in the sidebar.

## 7. Runbook links

When `runbooks/**` changed, verify every catalog link resolves to a file and an anchor:

```bash
grep -oE '\((cluster|components)/[^)#]+\.md#[^)]+\)' runbooks/README.md | tr -d '()' | while IFS='#' read -r file anchor; do
  [ -f "runbooks/$file" ] || echo "missing file: $file"
  grep -q "<a id=\"$anchor\"></a>" "runbooks/$file" || echo "missing anchor: $file#$anchor"
done
```

## 8. Report

Summarise, do not paste logs:

```
Checks
- make lint-ci                      PASS
- ansible syntax (k3s_bootstrap)    PASS
- tofu validate (vault)             PASS
- kubectl kustomize (cilium/prod)   PASS
- jekyll build                      NOT RUN (docs unchanged)

Notes
- yamllint pre-existing warnings in ansible/roles/... (untouched)
```

Then state whether the change is ready to commit or what must be fixed first.

## Guardrails

- Never "just apply it to check" — validation uses `kustomize`, `validate`, and `plan` only.
- Never run `tofu init` without `-backend=false` for validation.
- Do not silence a failing check by editing unrelated files.
- If a required tool is missing, say so and report the check as not run rather than guessing.
