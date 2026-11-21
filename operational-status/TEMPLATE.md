# <cluster> cluster status — last updated <YYYY-MM-DD HH:MMZ>

> Rolling status for `<cluster>` (`<kube-context>`). Refresh with `OPS-003` / the
> `cluster-handover` skill. Untracked session context: never commit. Template:
> `operational-status/TEMPLATE.md`. Historical incidents: `operational-status/<cluster>/incidents/`.

---

## 1. Snapshot — <YYYY-MM-DD HH:MMZ>

| Item | Value |
| --- | --- |
| Nodes | <n/n Ready, version, uptime> |
| Flux | <n/n Kustomizations True, revision> |
| Pods | <all Running/ready, or the exceptions> |
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

<Symptoms, evidence, next step.>

### 4.x Housekeeping (P3)

| Item | State |
| --- | --- |
| <item> | <state> |

### 4.x Watch items (no action until they move)

| Item | Why |
| --- | --- |
| <item> | <why> |

---

## 5. Verified healthy — do not re-litigate

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

1. Run `OPS-003` / the `cluster-handover` skill to refresh this file.
2. <next action>
