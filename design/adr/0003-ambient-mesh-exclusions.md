# ADR-0003: Istio Ambient Mesh Namespace Exclusions

| Field         | Value                                       |
|---------------|---------------------------------------------|
| **Status**    | Superseded (both keycloak and databases resolved) |
| **Date**      | 2026-06-07                                  |
| **Deciders**  | Ricardo Sanchez                             |
| **Supersedes**| —                                            |

## Context

Istio ambient mesh provides transparent mTLS and L4 observability without
sidecar injection. When a namespace is labeled
`istio.io/dataplane-mode: ambient`, the ztunnel proxies on each node capture
all TCP traffic to and from pods in that namespace via iptables redirection.

Two namespaces — `databases` and `keycloak` — were labelled for ambient mesh as
part of the e-commerce observability demo feature branch. After applying the
label, both experienced service-disrupting failures traced to ztunnel protocol
interference.

## Decision

**The `databases` and `keycloak` namespaces are permanently excluded from
Istio ambient mesh.**

### Rationale

#### `databases` namespace

The CloudNativePG operator webhook (`cnpg-webhook-service`) serves its own TLS
on port 9443. The kube-apiserver, which is outside the mesh, calls this webhook
without a mesh identity. When ztunnel intercepts this traffic, it breaks the
TLS handshake, causing EOF/connection-reset errors from the apiserver on
admission webhook calls.

PostgreSQL instances (managed by CNPG) also use their own TLS on port 8000 for
health checks and replication. ztunnel interception breaks these direct TCP
connections.

#### `keycloak` namespace

Keycloak uses **JGroups** (over Infinispan) for distributed cache clustering
between pod replicas. JGroups relies on:

- **Long-lived TCP connections** with custom binary framing
- **Timing-sensitive Failure Detection (FD)** protocols — heartbeats must
  arrive within tight, configurable windows
- **DNS_PING discovery** on port 7800 (headless service `keycloak-discovery`)

When ztunnel wraps JGroups traffic in HBONE (HTTP CONNECT) tunnels:

1. **Added latency** from encapsulation and extra network hops causes false
   failure detection — nodes believe peers are dead and refuse to form a
   cluster.
2. **Both Keycloak pods** reported `Keycloak cluster health check: DOWN`,
   preventing the second replica from ever becoming Ready.
3. **Terraform runner** pods in `flux-system` (not in the mesh) could not
   connect to `keycloak-service:8080` because the namespace enforced STRICT
   mTLS via PeerAuthentication, and non-mesh sources lack a SPIFFE identity.

## Alternatives Considered

| Alternative | Verdict |
|-------------|---------|
| **Selective port bypass** (exclude ports 7800/9443/8000 from ztunnel) | **Not possible.** The `traffic.istio.io/exclude-inbound-ports` annotation works only in sidecar mode. Ambient mode's `ambient.istio.io/bypass-inbound-capture` is all-or-nothing per pod. This is a known Istio limitation ([istio/istio#58546](https://github.com/istio/istio/issues/58546)). |
| **PERMISSIVE PeerAuthentication** instead of STRICT | Partially addresses the Terraform connectivity issue but does not solve the JGroups/ztunnel protocol incompatibility. Opportunistic mTLS provides weaker security guarantees. |
| **Add `flux-system` to ambient mesh** | Would give tf-runner pods a mesh identity (fixing the STRICT mTLS issue) but does not solve the JGroups/ztunnel protocol incompatibility. |
| **Run duplicate Keycloak deployments** (one in-mesh, one out) | Unacceptable operational complexity and resource waste for a homelab. |

## Consequences

- **No transparent mTLS** for inter-pod traffic or L4 observability in these
  namespaces. Traffic logs and metrics that ztunnel would normally emit are
  unavailable.
- **Security responsibility shifts** to application-layer TLS: CNPG
  PostgreSQL already enforces its own TLS; Keycloak relies on the edge
  (Envoy Gateway) terminating TLS and forwarding HTTP internally.
- **Consistency**: All stateful workloads that use non-HTTP protocols with
  custom framing or their own TLS are excluded from ambient mesh. Future
  candidates for exclusion include any service using:
  - Custom TCP binary protocols
  - Timing-sensitive heartbeats or failure detection
  - Their own TLS termination
  - Admission webhooks consumed by the kube-apiserver
- **No operational impact** on the rest of the mesh — workloads in other
  namespaces continue to use ambient mesh normally.

## Resolution: Keycloak re-enabled in ambient mesh

After further investigation into the Keycloak Operator's NetworkPolicy behavior
and upstream service mesh guidance, the `keycloak` namespace was successfully
re-enabled in ambient mesh (2026-06-08). The original exclusion addressed
symptoms that had root causes fixable through configuration:

### Root causes addressed

1. **Double mTLS encryption** — Keycloak's embedded JGroups mTLS (auto-generated
   certificates stored in the database) conflicted with Istio's HBONE mTLS,
   causing certificate mismatch errors (`JGRP000006: failed accepting connection
   from peer SSLSocket`). **Fix**: Set `cache-embedded-mtls-enabled: false` on the
   Keycloak CR, letting ambient mesh be the sole transport encryption layer. This
   is the approach recommended by [Keycloak's service mesh documentation](https://www.keycloak.org/server/caching#_running_inside_a_service_mesh).

2. **NetworkPolicy blocking ztunnel** — The Keycloak Operator creates
   `keycloak-network-policy` which restricts JGroups ingress (ports 7800, 57800)
   to only Keycloak-labeled pods. When ambient mesh is active, ztunnel proxies
   the TCP connections, and the source pod no longer matches the Keycloak label
   selector. **Fix**: Created an additive NetworkPolicy (`keycloak-istio-mesh`)
   that also allows JGroups ports from `ztunnel` pods in `istio-system`.

3. **STRICT mTLS blocking tofu controller** — The original STRICT Pekubernetes/platform/databases/config/components/istio/peer-authentication.yamlerAuthentication
   blocked non-mesh clients (`flux-system`) from reaching `keycloak-service:8080`.
   **Fix**: Replaced with a PERMISSIVE PeerAuthentication on port 8080, ensuring
   tofu controller connectivity while preserving mesh identity for other traffic.

### Discovery protocol

The default `jdbc-ping` stack (database-based discovery via `JDBC_PING2`) is used
instead of the deprecated `kubernetes` stack (DNS_PING). This avoids DNS
dependencies and works reliably through the mesh — the shared PostgreSQL database
serves as the cluster registry.

### Changes

- `kubernetes/platform/keycloak/operator/base/ns.yaml` — re-added `istio.io/dataplane-mode: ambient` label
- `kubernetes/platform/keycloak/app/base/keycloak.yaml` — added `cache-embedded-mtls-enabled: false`
- `kubernetes/platform/keycloak/app/base/network-policy.yaml` — new additive NetworkPolicy for ztunnel
- `kubernetes/platform/keycloak/config/base/peer-authentication.yaml` — PERMISSIVE PeerAuthentication on port 8080

### Databases re-enabled with PERMISSIVE PeerAuthentication

The `databases` namespace was re-enabled in ambient mesh (2026-06-08).
The original issue was that STRICT mTLS blocked the kube-apiserver (outside the
mesh) from calling the CNPG admission webhook on port 9443. This was not a
protocol-incompatibility problem like JGroups — it was purely an mTLS enforcement
issue. With **PERMISSIVE** PeerAuthentication, ztunnel accepts both mTLS and
plaintext traffic, allowing the kube-apiserver to reach the webhook without a
SPIFFE identity. CNPG PostgreSQL instances continue to use their own TLS on
port 8000 for health checks and replication — ztunnel tunnels the TCP stream
transparently without terminating application-layer TLS.

### Changes

- `kubernetes/platform/cloudnative-pg/app/components/istio/namespace-labels.yaml` — ambient mesh label for `databases` namespace
- `kubernetes/platform/databases/config/components/istio/peer-authentication.yaml` — PERMISSIVE mode
- `kubernetes/platform/keycloak/operator/components/istio/namespace-labels.yaml` — ambient mesh label for `keycloak` namespace
- `kubernetes/platform/keycloak/app/components/istio/keycloak-additionalOptions.yaml` — `cache-embedded-mtls-enabled: false`
- `kubernetes/platform/keycloak/app/components/istio/network-policy.yaml` — additive NetworkPolicy for ztunnel
- `kubernetes/platform/keycloak/config/components/istio/peer-authentication.yaml` — PERMISSIVE PeerAuthentication on port 8080

## References

- [Istio ambient mesh traffic redirection](https://istio.io/latest/docs/ambient/architecture/traffic-redirection/)
- [istio/istio#58546 — ambient.istio.io/bypass-inbound-capture breaks for mesh workloads](https://github.com/istio/istio/issues/58546)
- `kubernetes/platform/databases/cloudnative-pg/app/base/ns.yaml` — rationale comments for `databases`
- `kubernetes/platform/keycloak/operator/base/ns.yaml` — rationale comments for `keycloak`
