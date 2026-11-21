# Operations and Governance Runbooks

## OPS-001 Incident Command Workflow

<a id="runbook-ops-001"></a>
Runbook ID: `OPS-001`
Owner: Platform
Severity: `SEV-1` or `SEV-2`

Objective: Standardize major incident handling, communication, and recovery tracking.

Procedure:

1. Declare incident and assign roles:
  - Incident Commander
  - Operations Lead
  - Communications Lead
  - Scribe
2. Open incident channel and start timeline log.
3. Define scope, impact, and immediate containment actions.
4. Execute technical runbooks relevant to the affected domain.
5. Provide periodic status updates until mitigation and recovery complete.

Communication checkpoints:

- T0: Incident declared.
- T+15m: Initial impact assessment.
- T+30m and recurring: Progress updates.
- Resolution: Recovery summary and next steps.

Verify:

- Services restored to agreed operational state.
- Stakeholders notified of closure.
- Follow-up actions captured.

Rollback:

1. If mitigation change worsens impact, revert to last known-good state immediately.
2. Reassess with smaller blast-radius action plan.

## OPS-002 Postmortem Template and Action Tracking

<a id="runbook-ops-002"></a>
Runbook ID: `OPS-002`
Owner: Platform
Severity: `Maintenance`

Objective: Standardize incident learning and ensure corrective actions are tracked to closure.

Procedure:

1. Within 24-72h of incident closure, schedule postmortem review.
2. Collect timeline, impact metrics, root cause, and contributing factors.
3. Define corrective and preventive actions with owners and due dates.
4. Classify actions by priority (`P0`, `P1`, `P2`).
5. Publish report and track action completion in project board.

Postmortem sections:

- Incident summary
- Detection and response timeline
- Impact assessment
- Root cause analysis
- What worked and what failed
- Action items and deadlines

Verify:

- Report is published.
- All actions have owners and target dates.
- Follow-up review date is scheduled.
- Vault returns to operational state.

## OPS-003 Platform Healthcheck and Status Refresh

<a id="runbook-ops-003"></a>
Runbook ID: `OPS-003`
Owner: Platform
Severity: `Maintenance`

Objective: Produce a repeatable, evidence-based cluster health snapshot, run the end-to-end
checks, and reconcile the live-issue handover so it reflects reality.

Preconditions:
- `kubectl` with the `picluster-prod` context and `flux` installed.
- Access to Prometheus, Loki, Tempo and Grafana through the Kubernetes API proxy.
- The rolling status file `operational-status/<cluster>/cluster-status.md` and the template
  `operational-status/TEMPLATE.md`. The status file and `incidents/` are untracked session context
  and must never be committed.

Procedure:

1. Load `operational-status/<cluster>/cluster-status.md` (on first run, copy
   `operational-status/TEMPLATE.md` to that path). List every open item with the command or value
   that proves it.
2. Run the layer sweep described in the `cluster-triage` skill: nodes, `kube-system`, Flux
   sources/Kustomizations, HelmReleases, workloads, storage, gateway/TLS/DNS, observability and
   external services. Record only abnormal results.
3. Run the end-to-end checks below.
4. Reconcile each open item:
   - Evidence no longer reproduces -> move it to Closed with the proof.
   - Evidence still reproduces -> update the value and timestamp.
   - Evidence is worse -> re-prioritise and add the next step.
5. Add new findings from the sweep as open items with evidence and a proposed next step.
6. Update the rolling status in place: snapshot, timeline, closed table, open items, watch list and
   suggested moves. There is no dated file per day; historical incident narratives go under
   `operational-status/<cluster>/incidents/`.
7. Report only the deltas since the previous handover.

Commands:

```bash
CTX="--context picluster-prod"

# Layer sweep
flux get kustomizations -A $CTX | awk 'NR==1 || $5!="True"'
flux get helmreleases -A $CTX | awk 'NR==1 || $5!="True"'
kubectl $CTX get pods -A --no-headers | awk '{split($3,a,"/"); if (a[1]!=a[2] || $4!="Running") print}'
kubectl $CTX get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -20

# Metrics and alerts
PROM='kubectl --context picluster-prod get --raw /api/v1/namespaces/kube-prom-stack/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query'
$PROM?query=ALERTS%7Balertstate%3D%22firing%22%7D
$PROM?query=count(up%7Bjob%3D~%22loki.*%22%7D)%20by%20(job)

# Logs
kubectl $CTX -n loki get servicemonitors,grafanadashboards
kubectl $CTX -n fluent logs deploy/fluentd --since=15m | grep -E 'BufferOverflow|skip invalid event|overflow_action'
$PROM?query=fluentd_output_status_buffer_queue_length
$PROM?query=fluentd_output_status_retry_count

# Traces (restart reason distinguishes OOM from a liveness loop)
kubectl $CTX -n tempo get pod tempo-ingester-0 \
  -o jsonpath='{.status.containerStatuses[0].restartCount}{" "}{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'

# SSO: OIDC discovery and the Grafana login form for client_id=grafana
kubectl $CTX -n keycloak get pods
curl -s -o /dev/null -w '%{http_code}\n' https://iam.homelab.ricsanfre.com/realms/homelab/.well-known/openid-configuration

# Data services
kubectl $CTX -n databases get clusters.postgresql.cnpg.io,mongodbcommunity,valkeyclusters
kubectl $CTX -n kafka get kafka

# Node filesystem and storage
kubectl $CTX get --raw "/api/v1/nodes/<node>/proxy/stats/summary"
kubectl $CTX -n longhorn-system get volumes.longhorn.io
kubectl $CTX get pvc -A | grep -v Bound

# Status file
cat operational-status/prod/cluster-status.md
```

Verify:
- Every open item has a reproducible command and a value from this run.
- Every closed item names the PR/commit or command that proves it.
- No "firing" claim without a current `ALERTS` query.
- The snapshot values are from this run, not copied.

Rollback:
1. The handover is untracked; restore the previous copy from editor history or a backup.
2. Nothing in the cluster is changed by this runbook. If a fix is needed, follow the matching
   runbook and open a PR; do not edit live resources.

References:
- `.opencode/skills/cluster-triage/SKILL.md` - sweep order and healthy signals.
- `.opencode/skills/cluster-healthcheck/SKILL.md` - agent orchestration of this runbook.
- `runbooks/components/observability.md` - `OBS-001`, `OBS-004`.
- `operational-status/README.md` - layout and rules for the rolling status files.
- `operational-status/<cluster>/cluster-status.md` - current state and work queue.
