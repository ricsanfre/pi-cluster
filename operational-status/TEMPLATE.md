# <cluster> cluster status — last updated <YYYY-MM-DD HH:MMZ>

> Rolling status for `<cluster>` (`<kube-context>`). Refresh with `OPS-003` / the
> `cluster-healthcheck` skill. Untracked session context: never commit. Template:
> `operational-status/TEMPLATE.md`. Historical incidents: `operational-status/<cluster>/incidents/`.

---

## What each section is for

Read this once before filling the file. Every item lives in exactly **one** section, and moving it
between sections is how a handover records progress.

| Section | Holds | How the next session treats it |
| --- | --- | --- |
| **1. Snapshot** | Measurements taken **this run**, one row per layer | Refresh wholesale. Never carry a number forward — re-read every value, even if nothing changed. |
| **2. Timeline** | What happened between handovers | **Append only**, never rewrite. Anything longer than a table row moves to `incidents/`. Include the boot time and any restart cause, not just the symptom. |
| **3. Closed** | Items that were broken and now are not | **Do not re-test the diagnosis.** A recurrence is a *new* open item that links back here. Every row names the PR/commit/command and the live proof. |
| **4. Open** | Known-unhealthy, each with a reproducible proof | **Re-run the proof every sweep** and update the value: still true → keep it, gone → §3, worse → re-prioritise. Keep existing IDs stable (cross-reads depend on them); add new items at the end. |
| **4.x Housekeeping** | Known, decision pending, nothing broken | Actionable whenever someone has a window. |
| **4.x Watch** | Known, not actionable until it moves | Carries a trigger ("if it fires again", "on the next boot"), no owner until then. |
| **5. Verified healthy this sweep** | Checks that passed **this run** | **Re-check every sweep** — this is the end-to-end checklist, *not* an exemption list. If it still passes, don't re-open it as a finding or re-derive the conclusion. If it fails, it moves to §4. |
| **6. Commands worth keeping** | Commands that earned their place | Keep them copy-paste correct; delete ones that stopped being true. Prefer the query that distinguishes causes over the one that only shows the symptom. |
| **7. Gotchas** | Environment facts that cause misreads | Add one every time a wrong conclusion was reached. Never delete — a gotcha that "no longer applies" still explains an old entry. |
| **8. Reference** | Where to read next | Path or issue → why it matters. Include the runbook IDs that §4 hands off to. |
| **9. Suggested first moves** | The queue for the next session | Ordered, with the reason. Only as long as one session can plausibly start. |
| **10. Backlog plan** | A multi-session queue of dependency PRs: batches in merge order, the gate per batch, what is parked or blocked, and the invariants the order protects | Maintain the **Status** column as PRs land. It outlives §9 on purpose: §9 is what one session can start, §10 is the whole queue and the rules that order it. |

Two rules that follow from the table: **§5 is not "resolved"** — an item leaves §5 only by failing a
later sweep, and **§3 is not "re-checked"** — it is history, reopened only by a regression.

---

## 1. Snapshot — <YYYY-MM-DD HH:MMZ>

*State the measurement window (e.g. "20–40 min after the boot") and which rows are older than it.*

| Item | Value |
| --- | --- |
| Boot / uptime | <when the hosts booted, how it was verified — `node_boot_time_seconds`, not node age> |
| Nodes | <n/n Ready, version, pressure conditions, load vs requests> |
| Flux | <n/n Kustomizations, HelmReleases, Terraform CRs; revision> |
| Pods | <all Running/ready, or the exceptions, and any stale objects> |
| Firing alerts | <count and names> |
| Workloads | <key services and their state> |
| Storage | <PVCs Bound, volumes healthy, capacity> |
| Gateway/TLS/DNS | <gateways programmed, certs valid, ExternalSecrets synced> |
| Observability | <Loki targets, Tempo restarts, Prometheus targets> |
| External services | <Vault, RustFS, DNS> |

---

## 2. Timeline (recent)

| Time (UTC) | Event |
| --- | --- |
| <time> | <event> |

---

## 3. Closed since the last update

| Item | Fix | Evidence |
| --- | --- | --- |
| <item> | <PR/commit/command> | <live proof> |

---

## 4. Open — in priority order

### 4.1 <P1/P2 issue>

<Symptoms, evidence, next step. Include the command that proves it and the value from this run.>

### 4.x Housekeeping (P3)

| Item | State |
| --- | --- |
| <item> | <state> |

### 4.x Watch items (no action until they move)

| Item | Why |
| --- | --- |
| <item> | <why + the trigger that would make it actionable> |

---

## 5. Verified healthy this sweep — re-check, don't re-diagnose

<Each bullet is a check run in this sweep: what was measured, and the value that proves it.>

- <check> — <evidence>

---

## 6. Commands worth keeping

```bash
# <description>
<command>
```

---

## 7. Gotchas that will bite a new session

1. <gotcha>

---

## 8. Reference

- <runbook or doc path> — <why>

---

## 9. Suggested first moves

1. Run `OPS-003` / the `cluster-healthcheck` skill to refresh this file.
2. <next action>

---

## 10. Backlog plan — <YYYY-MM-DD> (<n> open PRs)

<The multi-session dependency queue: batches in merge order, the gate that must pass after each step,
the PRs deliberately parked or blocked, and the invariants the ordering protects. Keep the Status column
current — it is how a later session knows what is left without re-reading every PR.>

**Ordering rules** (state them once; they are why the batches look the way they do):

1. <rule — e.g. one CRD-bearing operator per reconcile>
2. <rule — e.g. leaves before core: DNS, CNI, gateway and the reconciler itself last>

**Gate for every merged step:** `flux reconcile` → all Kustomizations `True` → all pods ready → 0 firing
alerts → the component check in the batch table → next step. Stop and report on the first red gate;
rollback is a revert of that merge commit.

### A — <batch name> (<n> PRs)

| PR | Change | Gate | Status |
| --- | --- | --- | --- |
| <#id> | <what it changes> | <component-specific check> | open |

### B — parked (own window)

| PR | Why parked | Status |
| --- | --- | --- |
| <#id> | <the risk that keeps it out of a batch> | open, do not batch |

### C — blocked

| PR | Change | Blocker |
| --- | --- | --- |
| <#id> | <change> | <why it cannot move yet> |

### Invariants this plan protects

- <invariant — the thing that must stay true, and how it is enforced>

