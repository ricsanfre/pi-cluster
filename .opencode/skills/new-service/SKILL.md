---
name: New Service Delivery
description: Use when adding a new cloud-native service to the cluster — platform capability or application — covering chart selection, scaffolding, overlays, secrets, SSO, observability, ingress, cluster wiring, documentation, and runbooks.
---

# New Service Delivery

End-to-end procedure for adding a service to the Pi cluster. The goal is a service that is pinned,
layered correctly, wired into Flux, observable, documented, and testable — not just a HelmRelease that
happens to render.

## 1. Decide the shape

Ask, and answer from the repository before writing anything:

| Question | Where the answer lives |
| --- | --- |
| Platform capability or user workload? | `kubernetes/platform/` vs `kubernetes/apps/<group>/` |
| Helm chart, OCI chart, plain manifests, or operator? | Compare with a similar service under `kubernetes/platform/` |
| Does it ship CRDs? Who owns them? | Chart docs + existing patterns (`cert-manager`, `keycloak`, `databases`) |
| Does it need persistence? | Existing use of Longhorn StorageClasses |
| Does it need secrets? | External Secrets + Vault |
| Does it need SSO? | Keycloak OIDC via the tofu-controller |
| Does it need ingress/TLS? | Envoy Gateway HTTPRoute + cert-manager |
| Does it need external DNS? | HTTPRoute hostname + ExternalDNS |

If the choice is genuinely ambiguous (chart vs operator, own CRDs vs shared), stop and ask the user
with a recommendation. Do not guess.

## 2. Pin the upstream facts

Record the exact source, version, and values you are building on:

```bash
helm repo add <repo> <url> && helm repo update
helm search repo <repo>/<chart> --versions | head
helm show values <repo>/<chart> --version <version> > /tmp/<chart>-values.yaml
helm show crds <repo>/<chart> --version <version> | head -40
```

Rules:
- Pin an exact chart version. Never `latest` and never a floating major.
- Use `OCIRepository` for `oci://` chart URLs and `HelmRepository` for HTTP repos (see
  `kubernetes/platform/envoy-gateway/app/base/helm.yaml` for the OCI form).
- Read the upstream values file before copying keys into `values.yaml`; do not invent keys.
- Check architecture support: the cluster is mixed ARM64 (Raspberry Pi) and AMD64 (mini PCs). An
  image without a matching architecture will crash-loop on part of the nodes.

## 3. Scaffold from the boilerplate

The template lives in `boilerplate/fluxcd-app-template/` and generates the platform layout:

```bash
cp boilerplate/fluxcd-app-template-vars.yaml.example boilerplate/fluxcd-app-template-vars.yaml
# edit app_name, app_namespace, chart_repo_url, chart_name, chart_version, chart_release_name
make -C boilerplate generate-fluxcd-app
```

The generated tree under `boilerplate/output/<app>/` is scratch. Move what you need into the real
location:

```
kubernetes/platform/<service>/
├── app/
│   ├── base/           helm.yaml, ns.yaml, values.yaml, kustomization.yaml, kustomizeconfig.yaml
│   ├── components/     reusable bundles: monitoring, route, auth, istio, ...
│   └── overlays/
│       ├── dev/        kustomization.yaml, helm-patch.yaml, values.yaml
│       └── prod/
└── config/
    ├── base/           non-Helm resources: ExternalSecrets, HTTPRoutes, monitors, Terraform CRs
    └── overlays/{dev,prod}/
```

For a user workload use `kubernetes/apps/<group>/<component>/base` with plain manifests (see
`kubernetes/apps/e-commerce/`), and wire it through `kubernetes/apps/<group>/{app,config}`.

Do **not** commit `boilerplate/output/` — it is a scratch directory.

## 4. Layering rules

- `base/values.yaml` holds chart-generic values; environment differences go in the overlay's
  `values.yaml`.
- `base/kustomization.yaml` generates `<app>-helm-values` from `values.yaml` with `valuesKey:
  base-values.yaml`, and lists `kustomizeconfig.yaml`.
- Overlays add `overlay-values.yaml` with `behavior: merge` and add it to `valuesFrom` via a JSON patch
  (copy the pattern from `kubernetes/platform/descheduler/app/overlays/prod/kustomization.yaml`).
- Components are `kind: Component` bundles selected per overlay; use them for monitoring, routes,
  authentication, or mesh config rather than forking the base.
- Never duplicate a base manifest into an overlay. If you need a different value, patch it.
- Set `install.remediation.retries` and `upgrade.remediation` (rollback) as the existing services do.

## 5. Secrets

Never put a secret in Git. The chain is Vault → External Secrets → Kubernetes Secret.

1. Add the secret definition to the data-driven Terraform inputs in `terraform/vault/resources/` (or
   the relevant module) and apply it through the existing tofu-controller path. Check
   `terraform/vault/` for the current resource file layout.
2. Add an `ExternalSecret` in the service's `config/base/` (or `app/base/` when it is part of the
   Helm values):

   ```yaml
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   metadata:
     name: <app>-externalsecret
     namespace: <ns>
   spec:
     secretStoreRef:
       name: vault-backend
       kind: ClusterSecretStore
     target:
       name: <k8s-secret-name>
     data:
       - secretKey: <key>
         remoteRef:
           key: <path>/<service>
           property: <property>
   ```

   `vault-backend` is the shared `ClusterSecretStore` in `kubernetes/platform/external-secrets/`.
3. If the service needs S3, define buckets/users/policies in `terraform/minio/resources/` (RustFS
   backend) and reference the generated credentials through Vault.
4. Verify the sync after deploy: `kubectl -n <ns> get externalsecret` must be `SecretSynced=True`.

## 6. SSO (Keycloak)

For a service that should authenticate through the platform IdP:

1. Add the client, groups, and scopes to the data-driven inputs in `terraform/keycloak/resources/`.
2. Wire it through a `Terraform` object following
   `kubernetes/platform/keycloak/config/base/terraform.yaml` (`approvePlan: auto`,
   `path: ./terraform/keycloak`, `writeOutputsToSecret`).
3. Store the client secret in Vault and consume it with an ExternalSecret.
4. Set redirect URIs from `${CLUSTER_DOMAIN}`; never hardcode the domain.
5. Validate the login flow in dev before enabling it in prod.

## 7. Observability

- **Metrics**: add a `ServiceMonitor` or `PodMonitor` under `config/components/monitoring/` (see
  `kubernetes/platform/envoy-gateway/config/components/monitoring/`) or enable the chart's own
  monitor. Verify the target appears in Prometheus.
- **Dashboards**: add a `GrafanaDashboard` or dashboard ConfigMap next to the monitor, following an
  existing service.
- **Logs**: the app must log to stdout/stderr. Fluent Bit ships cluster logs; do not add a sidecar
  unless the service requires file-based collection.
- **Traces**: if the service supports OTLP, point it at the `otel` collector and confirm spans in
  Tempo.
- **Alerts**: add rules only when the service has a clear failure signal; do not copy generic rules.

## 8. Ingress and TLS

- Add an `HTTPRoute` (Envoy Gateway) in a `route` component or `config/base/`.
- Use the cluster domain from `cluster-settings` (`${CLUSTER_DOMAIN}` substitution), not a literal.
- TLS comes from cert-manager; pick the existing issuer used by comparable services.
- ExternalDNS publishes the hostname from the HTTPRoute. Verify the record after reconciliation.

## 9. Wire it into Flux

Platform services go in `kubernetes/clusters/prod/infra/`; workloads in
`kubernetes/clusters/prod/apps/`.

1. Create `<service>-app.yaml` (and `<service>-config.yaml` when there is a config tree), modelled on
   `kubernetes/clusters/prod/infra/descheduler-app.yaml`.
2. Set `path` to the prod overlay, `prune: true`, `wait: true`, and `targetNamespace`.
3. Add `dependsOn` for real prerequisites only (for example `external-secrets-config`,
   `cert-manager-app`). Do not create a dependency on everything.
4. Add `postBuild.substituteFrom` with `cluster-settings` when the manifests use `${...}` variables.
5. Register both files in `kubernetes/clusters/prod/{infra,apps}/kustomization.yaml`.
6. Do the same for the dev cluster if the service is testable there.

## 10. Documentation and runbook

Use the `docs-authoring` skill:

- `docs/_docs/<service>.md` + registration in `docs/_data/docs.yml`.
- A design note in `design/` when the choice is non-obvious (ADR under `design/adr/` if it is a
  decision worth recording).
- A runbook in the matching `runbooks/components/*.md` (or a new domain file), plus a catalog link in
  `runbooks/README.md` and an entry in `.opencode/skills/cluster-triage/references/runbook-map.md`.

## 11. Validate before proposing a commit

```bash
kubectl kustomize kubernetes/platform/<service>/app/overlays/dev
kubectl kustomize kubernetes/platform/<service>/app/overlays/prod
kubectl kustomize kubernetes/clusters/prod/infra
```

Then run `change-preflight`, and test the service with `service-testing` in the dev cluster before
promoting it.

## Guardrails

- No unpinned chart, image, or tag.
- No secret, token, or password in a tracked file.
- No prod wiring before the service renders and passes a dev smoke test.
- No new CRD ownership without checking for an existing operator that already provides it.
- No resource requests/limits omitted on a workload that runs on the Pi nodes — size it explicitly.
- If the chart has no ARM64 image, say so before wiring it into a cluster with ARM nodes.
