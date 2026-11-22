---
name: cluster-healthcheck
description: Use to run a cluster healthcheck and refresh the operational status — run the layer sweep plus end-to-end checks (metrics, logs, traces, SSO, data services), reconcile every open issue against fresh evidence, review dependency PRs pending merge, and update `operational-status/<cluster>/cluster-status.md`. Load at the start of a session, after a batch of fixes, or for a periodic health review.
---

# Cluster Healthcheck

Run the cluster health sweep and refresh the operational status so it reflects reality.

The rolling status file is `operational-status/<cluster>/cluster-status.md`; `operational-status/README.md`
defines the convention and `operational-status/TEMPLATE.md` is the first-run template. The status file
and `incidents/` are **untracked session context**. Never commit them. The canonical procedure and
commands are `OPS-003`; this skill is the agent orchestration.

## Procedure

1. **Load the current status.** Read `operational-status/<cluster>/cluster-status.md`; on first run,
   copy `operational-status/TEMPLATE.md` to that path. List its open items and the command/value that
   proves each one.
2. **Sweep.** Follow the `cluster-triage` skill for the layer order and healthy signals. Do not
   restate it; record only abnormal results.
3. **End-to-end checks.** Use the commands in `OPS-003`:
   - metrics: firing alerts and scrape targets;
   - logs: Loki targets, fluentd queue/retry and `BufferOverflow`, per-host ingestion;
   - traces: Tempo ingester restarts and the `lastState.terminated.reason` (OOM vs liveness);
   - SSO: Keycloak OIDC discovery and the Grafana login form for `client_id=grafana`;
   - data services: CNPG, MongoDB, Valkey, Kafka;
   - storage/gateway/TLS/DNS: PVCs, Longhorn volumes, certificates, ExternalSecrets.
4. **Check dependency PRs pending merge.** `gh pr list --state open --json number,title,files` —
   nothing is merged, closed, rebased or reviewed here; the queue is only reported. For each PR record
   its blast radius (values-only, image-only, CRD-bearing operator, Ansible bootstrap pin, external
   services) and reconcile §10 of the status file:
   - merged since the last handover -> move the batch row to its new status and record what was verified;
   - new -> assign it to a batch;
   - closed/autoclosed -> drop it.
   Flag any PR that breaks an ordering rule: two CRD-bearing operators in one reconcile, a chart
   without its Ansible bootstrap pin, a format-breaking major (ES, MongoDB, schema-registry), or a
   parked major that has drifted into a batch.
5. **Reconcile the issue list.** For every open item, re-run its proof:
   - resolved -> move it to Closed with the evidence (PR/commit/command);
   - unchanged -> update the value and timestamp;
   - worse -> reprioritise and add the next step.
   Add new findings as open items with evidence and a proposed next step.
6. **Update the rolling status.** Snapshot, timeline, closed table, open items, watch list, gotchas,
   suggested first moves and the backlog plan. Update it in place; there is no dated file per day.
   Historical incident narratives go under `operational-status/<cluster>/incidents/`.
7. **Report the delta** — what changed since the previous handover, not the whole document.

## Rules

- Read-only. If a fix is needed, propose it and wait for approval; then follow the matching
  runbook and change Git, not live resources.
- Never claim a check you did not run. If a tool is unavailable, say so and mark the check as not
  run.
- Never commit the status file or `incidents/`, and never copy secret values into them.
- A healthcheck never merges, closes or rebases a pull request. It reports what is pending, which batch
  it belongs to, and why; merging is a separate, explicitly requested action.
- If the procedure changes, update `OPS-003` and this skill together.
