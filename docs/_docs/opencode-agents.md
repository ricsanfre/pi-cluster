---
title: OpenCode AI Agents
permalink: /docs/opencode-agents/
description: Project-scoped OpenCode agent and skills for operating, extending and documenting the Pi cluster.
last_modified_at: "01-11-2026"
---

This repository ships a project-scoped [OpenCode](https://opencode.ai) agent and a set of skills that
cover the work done on the cluster day to day: triage, technology spikes, service delivery, testing,
and documentation.

They live in version control next to the code they operate on:

```
AGENTS.md                       shared repository instructions (all agents)
.opencode/agents/sre.md         the SRE / platform engineer agent
.opencode/skills/<id>/SKILL.md  on-demand procedures
```

{{site.data.alerts.note}}
`AGENTS.md` is the single source of repository guidance. OpenCode V2 loads it automatically and does
not read tool-specific files such as the former `CLAUDE.md`. Other agents that understand `AGENTS.md`
receive the same context.
{{site.data.alerts.end}}

## What the agent does

The `sre` agent acts as a Senior SRE / DevOps and platform engineer for this homelab. It is not a
code generator that happens to know Kubernetes: it diagnoses before changing, keeps changes
reversible, and treats Git and Flux as the source of truth.

| Area | Covered by |
| --- | --- |
| Cluster triage and incident runbooks | `cluster-triage` |
| Validating a branch in the live cluster | `flux-change` |
| Pre-commit / pre-PR validation | `change-preflight` |
| Evaluating technology alternatives | `tech-spike` |
| Adding a new service | `new-service` |
| Proving a service works | `service-testing` |
| Website pages, runbooks, release notes | `docs-authoring` |

## Prerequisites

- OpenCode V2 with a configured provider and model (`opencode models`).
- For cluster work: a valid kubeconfig and the CLI versions pinned in `.mise.toml`
  (`mise install`).
- For docs work: Ruby and the Jekyll bundle (`cd docs && bundle install`).

## Using the agent

Select `sre` from the agent picker in the TUI, or invoke it directly:

```bash
opencode run --agent sre "Do a read-only health sweep and report only anomalies"
opencode run --agent sre "Triage why the keycloak Kustomization is not ready"
opencode run --agent sre "Spike: Longhorn vs OpenEBS for the Pi nodes — recommend one"
opencode run --agent sre "Add <service> as a platform service and propose the file layout"
opencode run --agent sre "Update the Vault docs page for the new auth backend"
```

The agent routes to the matching skill automatically. You can also name a skill explicitly with
`@skill-id`, for example `@tech-spike`.

## Capability map

| Skill | Triggers when | Produces |
| --- | --- | --- |
| [`cluster-triage`](https://github.com/ricsanfre/pi-cluster/tree/master/.opencode/skills/cluster-triage) | The cluster is unhealthy | Layer-ordered evidence and a runbook handoff |
| [`flux-change`](https://github.com/ricsanfre/pi-cluster/tree/master/.opencode/skills/flux-change) | Validating a branch in the live cluster | Branch validation plus a clean revert to `master` |
| [`change-preflight`](https://github.com/ricsanfre/pi-cluster/tree/master/.opencode/skills/change-preflight) | Before committing or opening a PR | Lint, syntax, Terraform, kustomize and docs checks |
| [`tech-spike`](https://github.com/ricsanfre/pi-cluster/tree/master/.opencode/skills/tech-spike) | Choosing between technologies | Scored comparison, optional PoC, ADR or spike note |
| [`new-service`](https://github.com/ricsanfre/pi-cluster/tree/master/.opencode/skills/new-service) | Adding a platform service or workload | Pinned chart, overlays, secrets, SSO, observability, wiring |
| [`service-testing`](https://github.com/ricsanfre/pi-cluster/tree/master/.opencode/skills/service-testing) | Proving a service works | Dev deploy, smoke/integration checks, promotion checklist |
| [`docs-authoring`](https://github.com/ricsanfre/pi-cluster/tree/master/.opencode/skills/docs-authoring) | Writing docs, runbooks or release notes | Page/runbook with navigation and build verification |

Skills are loaded on demand, so only the relevant procedure enters the context. The skill files are
the source of truth for each procedure; this page does not duplicate them.

## Permission model

The agent inherits the global OpenCode permission baseline and refines it:

- **Read-only triage is allowed** — `kubectl get/describe/logs/events`, `flux get`, `helm list/diff`,
  `git status/diff/log`, `kubectl kustomize`, `tofu validate/fmt/plan`, `jekyll build`.
- **Mutations ask for approval** — edits, `kubectl apply`, `flux reconcile`, `helm upgrade`,
  `git commit/push`, dev-cluster changes.
- **Destructive actions are denied** — `make clean`, `k3s-reset`, `external-services-reset`,
  `shutdown-*`, `tofu/terraform apply|destroy`, `kubectl delete|drain`, `rm -rf`, `reboot`.

Permission rules are an ordered list where the **last matching rule wins**. Broad allows come first,
exceptions and denials last. This is why the agent cannot bypass a denial by rewording a command.

## Guardrails

- No production mutation without an explicit request.
- No secret in a tracked file; secrets come from Vault through External Secrets.
- No unpinned chart, image, or tag.
- Proofs of concept run in the dev cluster only and are torn down afterwards.
- Documentation is part of done: a behaviour change updates the page or runbook in the same change.

## Extending the agent

### Add a skill

Create `.opencode/skills/<id>/SKILL.md`. The directory name is the skill ID; the frontmatter
`name` is only a display label:

```markdown
---
name: Human Readable Name
description: When the model should load this skill.
---

Procedure, commands, thresholds and stop conditions.
```

Keep supporting material next to it (`references/`, `scripts/`) and reference those paths relative
to the skill directory. Then:

1. Add a row to the capability map above.
2. Add the skill to the routing list in `.opencode/agents/sre.md`.
3. Add it to the skills list in `AGENTS.md`.

### Add an agent

Create `.opencode/agents/<id>.md` with V2 frontmatter:

```yaml
---
description: What it does and when to use it.
mode: all          # primary | subagent | all
permissions:
  - action: read
    resource: "*"
    effect: allow
---
```

The Markdown body is the system prompt. Avoid legacy V1 fields such as `permission`, `tools`,
`temperature`, or `maxSteps`.

### Verify

```bash
opencode debug agents     # lists agents and the merged permission rules
```

Check that agents and skills appear and that the permission order is what you expect. Configuration
reloads without restarting OpenCode.

## Maintenance

- Treat agent and skill files like code: review changes, keep paths and commands real.
- Re-check commands after repository changes (Makefile targets, paths, namespaces).
- Cite runbooks and documentation instead of copying them; duplicated procedure drifts.
- Keep `AGENTS.md`, this page, and the skill routing list in sync when adding or renaming a skill.
- Never put credentials, tokens, or personal data in an agent or skill file.

## Limits

- The agent is model-dependent; its output is only as good as the model and the context it is given.
- It complements the runbooks, it does not replace them. For an active incident, follow
  [`runbooks/`](https://github.com/ricsanfre/pi-cluster/tree/master/runbooks) directly.
- It will not make production changes autonomously: mutations require approval and destructive
  commands are blocked.
- It cannot verify an upstream chart's defaults without reading them; expect it to inspect the
  chart rather than assume.

See the design decision in
[ADR 0012](https://github.com/ricsanfre/pi-cluster/blob/master/design/adr/0012-opencode-sre-agent.md).
