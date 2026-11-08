---
name: Documentation Authoring
description: Use when writing or updating project documentation — Jekyll pages under docs/, operational runbooks under runbooks/, or release-note posts — including navigation wiring and build verification.
---

# Documentation Authoring

Documentation is part of done. A change that alters behaviour, commands, architecture, or a
procedure is not finished until the matching page or runbook is updated.

**Ground every statement in the repository.** Read the manifest, playbook, values file, or script
before describing it. Never write a command, path, flag, or default that you have not verified.

## Choose the target

| Content | Location |
| --- | --- |
| How to build/operate the platform (public) | `docs/_docs/<name>.md` |
| Step-by-step incident or maintenance procedure | `runbooks/cluster/` or `runbooks/components/` |
| Why a design decision was made | `design/` or `design/adr/` |
| Release announcement | `docs/_posts/YYYY-MM-DD-announcing-release-X.Y.md` |
| Repository conventions | `AGENTS.md` |

Do not put runbooks in `docs/_docs/` (that tree is published publicly) and do not put design
rationale in runbooks.

## Jekyll pages

### Front matter

```yaml
---
title: Human Readable Title
permalink: /docs/<slug>/
description: One sentence used for SEO and search results.
last_modified_at: "DD-MM-YYYY"
---
```

- `permalink` slug is what the sidebar and cross-links use; it does not have to match the filename
  (`docs/_docs/index.md` → `/docs/home/`).
- Bump `last_modified_at` when you make a substantive change.
- Keep `description` a single sentence; it appears in search results.

### Navigation

Register the slug under the right section in `docs/_data/docs.yml`:

```yaml
- title: Storage
  docs:
  - longhorn
  - minio
```

A page that is not listed there is reachable by URL but invisible in the sidebar. When adding a new
section, place it in a sensible position — the file order is the sidebar order.

### Writing conventions

- Use `##` for main sections and `###` for subsections; the on-page TOC is generated from headings,
  so a clean hierarchy matters.
- Fence code blocks with a language (`bash`, `yaml`, `text`).
- Use tables for option/parameter matrices.
- Close every table with a block IAL; without it kramdown emits a bare `<table>` and the Bootstrap
  theme styling is lost:

  ```markdown
  | Column | Column |
  | --- | --- |
  | value | value |
  {: .table .border-dark }
  ```

  Use `{: .table .border-dark }` (the default) or `{: .table .table-white .border-dark }` when the
  table needs a white background. The IAL goes on the line immediately after the last table row.
- Callouts come from `docs/_data/alerts.yml`:

  ```markdown
  {{site.data.alerts.note}} Text of the note. {{site.data.alerts.end}}
  ```

  Available keys: `tip`, `note`, `important`, `warning`.
- Images live in `docs/assets/img/` and are referenced as `/assets/img/<file>`.
- Cross-link related pages with `/docs/<slug>/`, and design documents with
  `{{ site.github.repository_url }}/blob/master/design/<file>.md`.
- Match the existing voice: direct, second person, present tense, no marketing language.

### Build

```bash
cd docs
bundle config set --local path 'vendor/bundle'
bundle install
bundle exec jekyll build
```

`bundle exec jekyll serve` (port 4000) is for local preview only — do not leave it running.

## Runbooks

### Where

Add to the matching domain file:

- `runbooks/cluster/` — `bootstrap-recovery`, `nodes-capacity`, `gitops-release`, `security-access`,
  `change-management`, `backup-compliance`, `operations-governance`.
- `runbooks/components/` — `keycloak`, `vault`, `s3-storage`, `elastic-logging`, `observability`,
  `networking-ingress`.

If the domain does not exist, create the file, add it to the Domains table in `runbooks/README.md`,
and follow the same structure.

### Structure

Use the template in `runbooks/README.md`:

```markdown
## <ID> <Title>

<a id="runbook-<lowercase-id>"></a>
Runbook ID: `<DOMAIN-###>`
Owner: <team>
Severity: `<SEV-1|SEV-2|SEV-3|Maintenance>`

Objective: <what this solves>

Preconditions:
- <required state/tools>

Procedure:
1. <step with a real command>

Verify:
- <health signal>

Rollback:
1. <rollback step>
```

Rules:

- Keep the `<a id="runbook-<id>"></a>` anchor immediately after the heading — the catalog links to it.
- Allocate the next free ID in the domain. **Never renumber or reuse an ID**; retire by marking
  superseded.
- Every command must be one you have verified exists in this repo (a Make target, a runner path, a
  real namespace).
- Include a rollback even for low-risk procedures.
- If the runbook is derived from an incident, state what actually failed and what fixed it.

### Register in the catalog

Move the entry in `runbooks/README.md` from a plain backlog line to a link:

```markdown
- [`GITOPS-002` Kustomization Stuck or Not-Ready Triage](cluster/gitops-release.md#runbook-gitops-002)
```

Update the Domains table if you added a new file.

### Verify

```bash
grep -oE '\((cluster|components)/[^)#]+\.md#[^)]+\)' runbooks/README.md | tr -d '()' | while IFS='#' read -r file anchor; do
  [ -f "runbooks/$file" ] || echo "missing file: $file"
  grep -q "<a id=\"$anchor\"></a>" "runbooks/$file" || echo "missing anchor: $file#$anchor"
done
```

## Release notes

Create `docs/_posts/YYYY-MM-DD-announcing-release-X.Y.md`:

```yaml
---
layout: post
title: Kubernetes Pi Cluster release vX.Y
date: YYYY-MM-DD
author: ricsanfre
description: PiCluster News - announcing release vX.Y
---
```

Base the content on the actual commits since the previous release (`git log --oneline <prev>..HEAD`)
and on the design documents. Group by theme, link to the published docs page and the design
document, and do not announce work that is not merged.

## Drift check

When asked whether the docs are current, compare the implementation against the published pages and
runbooks. A rough starting point:

```bash
ls kubernetes/platform
ls docs/_docs
grep -E '^\s+- ' docs/_data/docs.yml
```

Then judge the mapping manually — service directory names do not always match page slugs
(`kube-prometheus-stack` documents under `observability`, `prometheus`, and `grafana`). Report:

- platform services with no documentation page;
- pages not registered in `docs/_data/docs.yml`;
- runbook IDs in the catalog with no detailed section;
- documented commands or paths that no longer exist.

Do not "fix" drift by deleting pages or entries without asking; propose the change first.

## Guardrails

- Never document a feature, flag, or file you have not found in the repository.
- Never duplicate a table or procedure that already has a canonical home — link to it instead.
- Do not edit `docs/vendor/`, `docs/_site/`, or `docs/.bundle/`.
- Do not publish runbooks or internal operational details to `docs/_docs/` without explicit approval.
