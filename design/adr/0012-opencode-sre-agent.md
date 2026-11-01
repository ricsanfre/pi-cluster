# ADR 0012: Adopt a Project-Scoped OpenCode SRE Agent and Skills

Date: 2026-11-01

## Status

Proposed

## Context

### Problem

The work in this repository is repetitive and varied: triaging Flux and Kubernetes failures, validating
changes before a PR, evaluating new cloud-native services, wiring those services into the GitOps
layout, testing them, and keeping the runbooks and website accurate. Each task has a procedure, but
the procedure lives in different places — `AGENTS.md`, `runbooks/`, `docs/_docs/`, and the operator's
memory.

The repository previously carried `CLAUDE.md` for one tool. It was not read by OpenCode V2, and the
content had drifted from the repository (tool versions, Terraform modules, Make targets, inventory
groups). A second, untracked copy in `.github/copilot-instructions.md` made the drift worse.

### Requirements

- One agent-neutral source of repository guidance.
- Procedures available on demand, not all loaded into every prompt.
- Safety: read-only investigation should be frictionless; mutations should require approval;
  destructive operations should be impossible to trigger by accident.
- The setup must live in version control and be reviewable like code.
- Documentation must explain how to use and extend it.

## Decision

Adopt a project-scoped OpenCode agent with on-demand skills, versioned under `.opencode/`:

- `AGENTS.md` replaces `CLAUDE.md` as the shared repository contract. It is loaded by OpenCode
  automatically and is usable by other agents that read the same convention.
- `.opencode/agents/sre.md` defines the SRE / platform engineer agent (`mode: all`). It carries the
  persona, operating loop, escalation rules and output contract.
- `.opencode/skills/<id>/SKILL.md` carry the procedures: `cluster-triage`, `flux-change`,
  `change-preflight`, `tech-spike`, `new-service`, `service-testing`, `docs-authoring`. They are
  loaded only when the task matches their description.
- Permissions follow a guarded model: read-only commands allowed, edits and reconciles require
  approval, destructive commands denied. Rules are ordered so the last match wins and denials cannot
  be bypassed by rewording a command.
- Runbooks move to `runbooks/`, split by domain, and remain the canonical operational procedure that
  skills reference rather than duplicate.

## Options Considered

### Option 1: Single large agent prompt (selected alternative rejected)

Put every procedure into the agent's system prompt.

- **Pros:**
  - One file to edit.
  - No discovery or loading step.
- **Cons:**
  - Every session pays the context cost of procedures it does not use.
  - Long prompts are harder to review and drift faster.
  - No natural boundary between "how the agent behaves" and "how to triage a component".

### Option 2: Project-scoped agent plus on-demand skills (selected)

Keep the agent prompt focused on conduct and route to skills for procedure.

- **Pros:**
  - Procedures load only when relevant.
  - Each skill has one audience and one purpose, and can reference support files.
  - Matches how the repository already separates runbooks, design and documentation.
  - Extensible without touching the agent prompt.
- **Cons:**
  - Two layers to keep in sync (agent routing plus skill files).
  - Skill descriptions must be precise or the wrong procedure loads.

### Option 3: Duplicated instructions per tool

Keep `CLAUDE.md`, `copilot-instructions.md` and an OpenCode file, all maintained separately.

- **Pros:**
  - Each tool reads its native file with no indirection.
- **Cons:**
  - Immediate drift, as already observed: the copies disagreed with `.mise.toml`, the Terraform
    modules and the Makefile.
  - Every repository change must be applied N times.

### Option 4: External automation platform

Move the procedures into a workflow engine or hosted agent.

- **Pros:**
  - Central scheduling and audit.
- **Cons:**
  - Adds an external dependency and a second source of truth for a single-operator homelab.
  - Credentials and cluster access would live outside the repository.
  - Disproportionate for the scale of the project.

## Consequences

### Positive

- One guidance source (`AGENTS.md`) for every agent that understands the convention.
- Procedures are versioned, reviewable and discoverable next to the code they operate on.
- Read-only triage is fast; risky actions are gated; destructive actions are blocked.
- Adding a capability is additive: a new skill plus one routing line.
- The documentation explains the model, so the setup is maintainable by future contributors.

### Negative

- The agent files are another thing to keep current when commands or paths change.
- Behaviour depends on the configured model and provider; results vary between models.
- Permission rules are configuration, not a security boundary against a determined operator.
- Skills can drift from runbooks if a change updates one and not the other.

### Neutral

- Nothing here is enforced in CI; validation is `opencode debug agents` plus review.
- The agent is not required to operate the cluster; runbooks and Make targets remain sufficient on
  their own.
- Documentation of the agent is published on the project site alongside the rest of the platform
  documentation.

## References

- [OpenCode AI Agents](https://picluster.ricsanfre.com/docs/opencode-agents/) — usage, capability map,
  extension guide.
- [`AGENTS.md`](../../AGENTS.md)
- [`.opencode/agents/sre.md`](../../.opencode/agents/sre.md)
- [`runbooks/README.md`](../../runbooks/README.md)
- [OpenCode V2 documentation](https://opencode.ai/v2/docs/)
