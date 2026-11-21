# Operational status

One **rolling** status file per cluster, kept up to date by `OPS-003`
(`runbooks/cluster/operations-governance.md`) and the `cluster-handover` skill.

## Layout

```
operational-status/
├── README.md                 # this file (tracked)
├── TEMPLATE.md               # handover template (tracked)
├── prod/
│   ├── cluster-status.md     # rolling prod status (untracked)
│   └── incidents/            # incident narratives (untracked)
└── dev/
    └── cluster-status.md     # rolling dev status (untracked, when used)
```

## Rules

- **One status file per cluster**, not one per day. Update it in place.
- `cluster-status.md` and `incidents/` are **untracked session context** and are covered by
  `.gitignore`; never commit them.
- `README.md` and `TEMPLATE.md` are tracked: they define the convention and the procedure.
- On the first run for a cluster, copy `TEMPLATE.md` to `<cluster>/cluster-status.md` and fill it
  from live evidence. Use the cluster name matching the kube context: `prod` for
  `picluster-prod`, `dev` for `k3d-picluster`.
- Refresh with `OPS-003` or the `cluster-handover` skill: layer sweep, end-to-end checks, then
  reconcile every open item against fresh evidence.
- Historical incident narratives go under `<cluster>/incidents/`, not in the rolling status.
