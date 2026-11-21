# Operational status

One **rolling** status file per cluster, kept up to date by `OPS-003`
(`runbooks/cluster/operations-governance.md`) and the `cluster-healthcheck` skill.

## How to ask for a healthcheck

Ask the SRE agent to run the healthcheck and refresh the status file. Any of these work:

- `@cluster-healthcheck`
- "Run a cluster healthcheck for prod and update `operational-status/prod/cluster-status.md`."
- "Is the cluster healthy? Refresh the prod status."
- "What changed since the last status?"

The agent loads `OPS-003`, runs the layer sweep and the end-to-end checks, reconciles every open
item against fresh evidence, and reports only the delta. It is read-only unless you approve a fix.
On the first run for a cluster (no `cluster-status.md`), it copies `TEMPLATE.md` and fills it.

Use `@cluster-triage` instead when something is broken and you want a reactive investigation; use
`@cluster-healthcheck` for the periodic sweep and status refresh.

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
- Refresh with `OPS-003` or the `cluster-healthcheck` skill: layer sweep, end-to-end checks, then
  reconcile every open item against fresh evidence.
- Historical incident narratives go under `<cluster>/incidents/`, not in the rolling status.
