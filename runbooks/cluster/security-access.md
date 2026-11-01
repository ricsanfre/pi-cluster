# Security and Access Runbooks

## SEC-001 Credential Leak Response and Rotation

<a id="runbook-sec-001"></a>
Runbook ID: `SEC-001`
Owner: Security and Platform
Severity: `SEV-1`

Objective: Contain and rotate compromised credentials quickly and safely.

Procedure:

1. Contain:
  - Revoke exposed token/credential at issuer.
  - Suspend affected Flux Kustomization if continuous failures/noise occur.
2. Scope blast radius:
  - Identify all consumers of the leaked secret path.
3. Rotate secret in Vault and dependent systems.
4. Reconcile dependent Kustomizations/Terraform CRs.

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization <affected-kustomization> -n flux-system --with-source
```

5. Invalidate user sessions if OIDC/client secrets were rotated.

Verify:

- Old credential no longer authenticates.
- New credential works in all dependent services.
- No authentication failures in controller/app logs.

Rollback:

1. Restore previous known-good secret only if production impact is critical and risk accepted.
2. Re-attempt controlled rotation in maintenance window.

## SEC-002 Compromised Node Isolation and Rebuild

<a id="runbook-sec-002"></a>
Runbook ID: `SEC-002`
Owner: Security and Platform
Severity: `SEV-1`

Objective: Isolate potentially compromised node and restore service with clean rebuild.

Procedure:

1. Immediately isolate node from scheduling and traffic.

```bash
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --grace-period=30 --timeout=10m
```

2. Capture forensic metadata (node events, pod list, key logs).
3. Remove node from cluster if compromise is confirmed.

```bash
kubectl delete node <node-name>
```

4. Reinstall host OS and rejoin node through standard automation.
5. Rotate credentials/secrets that may have been exposed.

Verify:

- Replacement node joins and becomes Ready.
- No suspicious workloads or processes return.

Rollback:

1. Keep node out of cluster if rebuild validation fails.
2. Shift workloads to healthy nodes until replacement succeeds.

## SEC-003 TLS Private Key Compromise Response

<a id="runbook-sec-003"></a>
Runbook ID: `SEC-003`
Owner: Security and Platform
Severity: `SEV-1`

Objective: Contain and remediate suspected TLS private key compromise.

Procedure:

1. Identify impacted certificate(s), secret(s), and endpoints.
2. Revoke compromised certificate(s) at issuing CA when supported.
3. Rotate key material by reissuing certificates.
4. Force rollout/restart affected ingress/controllers/workloads.
5. Validate that old certificate fingerprint is no longer served.

Suggested checks:

```bash
kubectl get certificate -A
kubectl get secret -A | grep -E 'tls|cert'
```

Verify:

- New certificate is active on all impacted endpoints.
- Old serial/fingerprint is not presented.
- No TLS handshake failures in logs.

Rollback:

1. If reissue fails, apply emergency fallback cert only for continuity.
2. Keep affected endpoint internal-only until valid cert is restored.
