---
name: cluster-handover
description: Use to refresh the live cluster handover — run the layer sweep plus end-to-end checks (metrics, logs, traces, SSO, data services), reconcile every open issue against fresh evidence, and update `handover-*-cluster-status.md`. Load at the start of a session, after a batch of fixes, or for a periodic health review.
---

# Cluster Handover

Refresh the cluster health snapshot and the live-issue handover so it reflects reality.

The handover file (`handover-*-cluster-status.md` at the repository root) is **untracked session
context**. Never commit it. The canonical procedure and commands are `OPS-003`; this skill is the
agent orchestration.

## Procedure

1. **Load the current handover.** `ls -t handover-*-cluster-status.md | head -1`. List its open
   items and the command/value that proves each one.
2. **Sweep.** Follow the `cluster-triage` skill for the layer order and healthy signals. Do not
   restate it; record only abnormal results.
3. **End-to-end checks.** Use the commands in `OPS-003`:
   - metrics: firing alerts and scrape targets;
   - logs: Loki targets, fluentd queue/retry and `BufferOverflow`, per-host ingestion;
   - traces: Tempo ingester restarts and the `lastState.terminated.reason` (OOM vs liveness);
   - SSO: Keycloak OIDC discovery and the Grafana login form for `client_id=grafana`;
   - data services: CNPG, MongoDB, Valkey, Kafka;
   - storage/gateway/TLS/DNS: PVCs, Longhorn volumes, certificates, ExternalSecrets.
4. **Reconcile the issue list.** For every open item, re-run its proof:
   - resolved -> move it to Closed with the evidence (PR/commit/command);
   - unchanged -> update the value and timestamp;
   - worse -> reprioritise and add the next step.
   Add new findings as open items with evidence and a proposed next step.
5. **Update the handover.** Snapshot, timeline, closed table, open items, watch list, gotchas and
   suggested first moves. Keep exactly one current file; on a new day create the dated successor,
   carry the open items over, and delete the superseded file once quoted.
6. **Report the delta** — what changed since the previous handover, not the whole document.

## Rules

- Read-only. If a fix is needed, propose it and wait for approval; then follow the matching
  runbook and change Git, not live resources.
- Never claim a check you did not run. If a tool is unavailable, say so and mark the check as not
  run.
- Never commit the handover and never copy secret values into it.
- If the procedure changes, update `OPS-003` and this skill together.
