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
