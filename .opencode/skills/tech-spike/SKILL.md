---
name: Technology Spike
description: Use when evaluating technology alternatives before adopting one — framing the decision, researching candidates, scoring them against this cluster's constraints, running a timeboxed proof of concept, and producing an ADR or spike note with a recommendation.
---

# Technology Spike

Discovery work that ends in a decision, not a deployment. A spike may conclude "adopt", "adopt with
conditions", "defer", or "reject" — all four are valid outcomes.

The output is an evidence-backed recommendation, never a demo that happened to work once.

## 1. Frame the decision

Write these down before searching:

```
Question:        <the decision to make, in one sentence>
Trigger:         <why now: cost, capability gap, EOL, incident, curiosity>
Decision owner:  <who accepts the ADR>
Timebox:         <e.g. 2 sessions / 1 day>
Non-goals:       <what this spike will not decide>
Success:         <what evidence would make a recommendation defensible>
```

If the question is "which of these tools is best", rewrite it as a decision: "replace X with Y for
purpose Z under constraints C".

## 2. Cluster constraints (always apply)

Every candidate is judged against this environment, not against a generic production cluster:

| Constraint | Implication |
| --- | --- |
| Hybrid ARM64 (Pi) + AMD64 (mini PCs) | Multi-arch images are mandatory; no x86-only binaries |
| 8 GB / 16 GB nodes | Idle footprint matters; measure it, do not trust the README |
| Longhorn block storage | Needs a StorageClass that works with Longhorn; no hostPath assumptions |
| FluxCD GitOps | Must deploy from manifests/charts; imperative bootstrap is a cost |
| Vault + External Secrets | Secrets must come from Vault, not chart-generated plaintext |
| Keycloak SSO | OIDC integration is a plus; local auth is acceptable but must be stated |
| Envoy Gateway + cert-manager + ExternalDNS | Ingress must fit HTTPRoute/Gateway API, not legacy Ingress |
| Prometheus / Loki / Tempo / Grafana | Metrics, logs, traces expected; no proprietary-only telemetry |
| RustFS S3 + Velero | Stateful services need an S3 backup path |
| Homelab budget and power | Prefer low idle cost; managed cloud services are out of scope |
| Public GitHub repo | No secrets in values; licenses must be compatible with publishing |

State explicitly when a candidate violates a constraint. That is often the deciding evidence.

## 3. Longlist, then shortlist

Sources, in order of usefulness:

1. Official documentation and the project's own architecture/limitations pages.
2. GitHub: releases, commit cadence, open issues, contributor count, license, multi-arch images.
3. CNCF landscape / project maturity (sandbox, incubating, graduated).
4. Helm chart quality: maintained chart repo, values schema, CRDs, upgrade notes.
5. Community reports: blog posts and issues from small/edge clusters, not vendor benchmarks.
6. Security: CVE history, image signing, dependency posture.

Shortlist 2–4 candidates. A single candidate is not an evaluation.

For each shortlisted candidate, record the exact versions you inspected — `latest` is not evidence.

## 4. Score against criteria

Use a table. Weights are for this cluster; adjust and say why.

| Criterion | Weight | What counts as evidence |
| --- | --- | --- |
| Requirement fit | 25% | The specific capability needed, not adjacent features |
| Maturity and activity | 15% | Releases in the last 12 months, maintainers, adoption, CNCF status |
| ARM64 support | 10% | Multi-arch image manifest or native build; verified, not assumed |
| Operational complexity | 10% | CRDs, HA, upgrade procedure, failure modes, on-call burden |
| Resource footprint | 10% | Measured idle CPU/memory in the PoC |
| GitOps friendliness | 10% | Chart/manifests, no imperative bootstrap, CRD lifecycle |
| Security posture | 10% | CVEs, signing, secret handling, RBAC scope |
| Integration fit | 5% | Vault/ESO, Keycloak, observability, backup |
| Exit path | 5% | Data format, migration effort, lock-in |

Score 1–5 with a one-line justification per cell. Do not average away a hard constraint: a candidate
that fails ARM64 or licensing is out regardless of its total.

## 5. Run a timeboxed proof of concept

Only if desk research cannot answer the question. Never in prod.

- Use the dev cluster (`dev/`, k3d) or a throwaway namespace on a non-production cluster.
- Define the smallest experiment that tests the risky assumption, not a full installation.
- Record: exact version, commands, config, result, resource usage, failure modes.
- Test the awkward parts: upgrade, restart, ARM scheduling, secret injection, backup/restore.
- Measure, do not estimate: `kubectl top`, PVC usage, startup time, idle memory.
- Tear down everything afterwards.

```bash
# example PoC loop
cd dev && make create-k3d
kubectl create namespace spike-<name>
# install candidate, run the experiment, capture output
kubectl -n spike-<name> top pods
cd dev && make delete-k3d
```

If the PoC needs a cluster mutation, ask first. If it cannot run (no dev cluster, missing credentials),
say so and keep the conclusion at "unverified".

## 6. Produce the decision record

### If adopting

Write an ADR in `design/adr/`, following the existing format. Find the next number:

```bash
ls design/adr | sort | tail -5
```

Structure (match `design/adr/0010-*`):

```markdown
# ADR NNNN: <Decision Title>

Date: YYYY-MM-DD

## Status

Proposed

## Context

### Problem
<the gap, with evidence>

### Decision
<what will be adopted and the key choices>

## Options Considered

### Option 1: <name> (selected)
- **Pros:**
- **Cons:**

### Option 2: <name>
- **Pros:**
- **Cons:**

## Consequences

### Positive
### Negative
### Neutral

## References
- <project docs, release notes, chart repo, PoC notes>
```

### If not adopting yet

Write a spike note in `design/<slug>.md`:

```markdown
# <Topic> Spike

Date: YYYY-MM-DD
Question: <what was evaluated>
Verdict: adopt | adopt with conditions | defer | reject
Revisit when: <trigger that would change the answer>

## Candidates
| Candidate | Version | Verdict | Why |

## Findings
<evidence, measurements, PoC results>

## Recommendation
<what to do next, risks, effort>

## References
```

## 7. Report to the user

Deliver:

```
Question:        <decision>
Verdict:         <adopt / adopt with conditions / defer / reject>
Shortlist:       <candidates + versions>
Decisive factor: <the one thing that separated them>
Risks:           <top 2-3, with mitigations>
PoC:             <what was actually run, or "desk research only">
Next step:       <ADR path, or what to investigate next>
```

Never present a single-option recommendation without saying why the alternatives lost.

## Guardrails

- Do not deploy a candidate to prod as part of a spike.
- Do not treat "it installed" as "it is production-ready".
- Do not score on popularity alone; stars are not evidence of fit.
- Do not skip the ARM64 and licensing checks — they are disqualifying.
- Do not write an ADR with `Status: Accepted`; the human owner accepts it.
- Do not leave spike workloads, namespaces, or clusters behind.
