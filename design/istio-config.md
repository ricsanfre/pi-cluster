# Istio Ambient Mesh Configuration

## Overview

The Pi Cluster uses Istio ambient mesh for transparent mTLS and L4 observability
without sidecar injection. Namespaces labeled `istio.io/dataplane-mode: ambient`
have all TCP traffic intercepted by per-node ztunnel proxies via iptables
redirection.

Four namespaces participate in the ambient mesh: `keycloak`, `databases`,
`e-commerce`, `envoy-gateway-system`, and `kafka`. Each required specific
configuration to work correctly with ztunnel's HBONE tunneling.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Namespace           Mesh config                         │
│                                                         │
│  envoy-gateway-system  PERMISSIVE (ingress gateway)      │
│  keycloak              PERMISSIVE :8080 (tofu runner)    │
│                        NetworkPolicy for ztunnel ports   │
│                        cache-embedded-mtls-enabled=false  │
│  databases             STRICT + PERMISSIVE :9443 (CNPG   │
│                        webhook for kube-apiserver)       │
│  e-commerce            STRICT                            │
│  kafka                 STRICT + PERMISSIVE :8443, :8080  │
│                        (Strimzi webhook + metrics)       │
│                        PERMISSIVE :9404, :8081           │
│                        (broker + entity-operator metrics)│
└─────────────────────────────────────────────────────────┘
```

## Namespace: keycloak

### Challenges

1. **Double mTLS encryption** — Keycloak 26.x auto-generates TLS certificates
   for JGroups (Infinispan distributed cache) stored in the database. When
   ztunnel wraps this traffic in HBONE mTLS, the certificates clash, producing
   `JGRP000006: failed accepting connection from peer SSLSocket`.

2. **Operator NetworkPolicy blocks ztunnel** — The Keycloak Operator creates
   `keycloak-network-policy` restricting JGroups ingress (ports 7800, 57800) to
   only Keycloak-labeled pods. ztunnel pods in `istio-system` don't match this
   selector, so all HBONE-proxied JGroups traffic is blocked.

3. **Istio infrastructure ports blocked** — The operator's NetworkPolicy also
   blocks HBONE tunnel termination (15008), waypoint proxy (15006), and Istio
   health/metrics ports (15020, 15021), preventing ambient mesh from functioning.

4. **Non-mesh client connectivity** — The Terraform runner (tofu controller) in
   `flux-system` runs outside the mesh and cannot satisfy mTLS requirements when
   communicating with `keycloak-service:8080`.

### Configuration

**Keycloak CR** — disable embedded JGroups mTLS:
```yaml
additionalOptions:
  - name: cache-embedded-mtls-enabled
    value: "false"
```

**NetworkPolicy** — additive policy allowing ztunnel infrastructure traffic:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: keycloak-istio-mesh
spec:
  podSelector:
    matchLabels:
      app: keycloak
      app.kubernetes.io/managed-by: keycloak-operator
  ingress:
    # HBONE tunnel termination (ztunnel)
    - ports: [{port: 15008, protocol: TCP}]
    # Waypoint proxy
    - ports: [{port: 15006, protocol: TCP}]
    # Istio health / metrics
    - ports: [{port: 15020, protocol: TCP}, {port: 15021, protocol: TCP}]
    # JGroups (ztunnel-proxied)
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: istio-system}}
          podSelector: {matchLabels: {app: ztunnel}}
      ports:
        - {port: 7800, protocol: TCP}
        - {port: 57800, protocol: TCP}
```

**PeerAuthentication** — PERMISSIVE on HTTP API port (selector matches Keycloak pods):
```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: keycloak-permissive
spec:
  selector:
    matchLabels:
      app: keycloak
  portLevelMtls:
    "8080":
      mode: PERMISSIVE
```

**Component layout:**
```
keycloak/
├── operator/components/istio/       ← namespace ambient label
├── app/components/istio/            ← NetworkPolicy + Keycloak CR patch
└── config/components/istio/         ← PeerAuthentication
```

## Namespace: databases

### Challenges

1. **CNPG admission webhook** — `cnpg-webhook-service` serves TLS on container
   port 9443 (exposed via Service port 443). The kube-apiserver calls this
   webhook from outside the mesh without a SPIFFE identity. With STRICT mTLS,
   ztunnel rejects these calls, causing EOF/connection-reset errors.

2. **Multiple namespace definitions** — Three operators (cloudnative-pg,
   valkey-operator, mongodb-community-operator) each defined their own copy of
   the `databases` namespace. The last reconciliation to apply would strip the
   ambient mesh label if any operator's base lacked it.

### Configuration

**Single namespace owner** — `databases/common` is the sole owner of the
namespace resource. All three operators were moved under `databases/` and no
longer define `ns.yaml`. This prevents label-stripping races.

**PeerAuthentication** — STRICT with webhook exception:
```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: databases-strict
spec:
  selector: {matchLabels: {}}
  mtls:
    mode: STRICT
---
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: cnpg-webhook-permissive
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: cloudnative-pg
  portLevelMtls:
    "9443":
      mode: PERMISSIVE
```

The pod-specific `cnpg-webhook-permissive` has a more specific selector and
takes precedence over the namespace-wide `databases-strict`. Port 9443 is
PERMISSIVE only for the CNPG operator pod; all other workloads and ports
remain STRICT.

**Component layout:**
```
databases/
├── common/components/istio/        ← namespace ambient label
├── cloudnative-pg/components/istio/ ← cnpg-webhook-permissive PeerAuthentication
└── config/components/istio/        ← namespace-wide databases-strict PeerAuthentication
```

## Namespace: envoy-gateway-system

### Challenges

Envoy Gateway serves as the ingress point for external HTTP traffic. External
clients lack SPIFFE identities, so STRICT mTLS would block all ingress traffic.

### Configuration

**PeerAuthentication** — PERMISSIVE for all traffic:
```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: envoy-gateway-permissive
spec:
  selector: {matchLabels: {}}
  mtls:
    mode: PERMISSIVE
```

**Component layout:**
```
envoy-gateway/
├── app/components/istio/           ← namespace ambient label
└── config/components/istio/        ← PeerAuthentication
```

## Namespace: e-commerce

### Configuration

Standard ambient mesh with STRICT mTLS — no exceptions needed. All e-commerce
workloads communicate within the mesh or through the Envoy Gateway.

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: e-commerce-strict
spec:
  selector: {matchLabels: {}}
  mtls:
    mode: STRICT
```

**Component layout:**
```
e-commerce/
└── config/components/istio/        ← namespace ambient label + PeerAuthentication
```

## Namespace: kafka

### Challenges

1. **Strimzi admission webhooks** — The Strimzi operator deploys validating and
   mutating webhooks on port 8443. The kube-apiserver calls these from outside
   the mesh without a SPIFFE identity. With STRICT mTLS, ztunnel rejects these
   calls, preventing Kafka custom resources from being applied.

2. **Prometheus metrics scraping** — Prometheus runs in the `kube-prom-stack`
   namespace (outside the mesh) and scrapes Kafka broker and operator metrics
   via PodMonitors on ports 9404 (broker JMX), 8080 (operator), and 8081
   (entity-operator). STRICT mTLS blocks Prometheus since it lacks a SPIFFE
   identity.

### Configuration

**PeerAuthentication** — STRICT with webhook and metrics exceptions:

```yaml
# Namespace-wide default
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: kafka-strict
spec:
  selector: {matchLabels: {}}
  mtls:
    mode: STRICT
---
# Strimzi operator: PERMISSIVE on webhook and metrics ports
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: strimzi-operator-permissive
spec:
  selector:
    matchLabels:
      strimzi.io/kind: cluster-operator
  portLevelMtls:
    "8443":
      mode: PERMISSIVE
    "8080":
      mode: PERMISSIVE
---
# Kafka broker JMX metrics
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: kafka-broker-metrics-permissive
spec:
  selector:
    matchLabels:
      strimzi.io/kind: Kafka
  portLevelMtls:
    "9404":
      mode: PERMISSIVE
---
# Entity Operator health/metrics
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: entity-operator-metrics-permissive
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: entity-operator
  portLevelMtls:
    "8081":
      mode: PERMISSIVE
```

The pod-specific PeerAuthentications have more specific selectors and take
precedence over the namespace-wide `kafka-strict`. Webhook and metrics ports
are PERMISSIVE only for the targeted pods; all other workloads and ports
remain STRICT.

### Kafka listeners and ambient mesh

Kafka uses three listeners:
- **plain (9092)** — internal plaintext. ztunnel HBONE tunnels provide
  transparent transport encryption. No application-level TLS needed.
- **tls (9093)** — internal TLS. ztunnel wraps this in HBONE mTLS ("double
  encryption"). Functional but redundant; the plaintext listener is sufficient
  when ambient mesh provides transport encryption.
- **external (9094)** — TLS Passthrough via Envoy Gateway. External clients
  negotiate TLS end-to-end with Kafka brokers (Let's Encrypt certificate).
  ztunnel is transparent at L4 so the TLS session passes through unchanged.
  The Gateway pod (envoy-gateway-system, PERMISSIVE) and Kafka brokers (kafka,
  STRICT) are both meshed, so ztunnel-to-ztunnel mTLS works.

### No NetworkPolicy conflict

The Strimzi operator has `generateNetworkPolicy: false` — no operator-created
NetworkPolicies exist to conflict with ztunnel. Unlike the Keycloak namespace,
no additive NetworkPolicy is needed.

### Component layout

```
kafka/
└── strimzi-kafka-operator/components/istio/   ← namespace label + all PeerAuthentications
```

Since the kafka namespace is defined in `strimzi-kafka-operator/base/ns.yaml`,
the istio component lives in the same kustomization tree. This tree is the
single owner of both the namespace resource and the PeerAuthentication policies.

## Component pattern

All Istio configuration is managed through Kustomize components (`kind: Component`),
wired into the prod overlays only. Dev overlays remain untouched since the dev
cluster (k3d) does not use ambient mesh.

Each component lives in the kustomization tree that owns the resource it patches:

| Resource | Component location | Rationale |
|----------|-------------------|-----------|
| Namespace label | Same tree as `ns.yaml` | Kustomize patches only see resources in their own scope |
| PeerAuthentication | `config/components/istio/` | Istio policy resources belong to the config layer |
| NetworkPolicy | `app/components/istio/` | Complements the operator-created NetworkPolicy in the app namespace |
| Keycloak CR patch | `app/components/istio/` | Patches the Keycloak CR defined in the app base |

## Istio infrastructure ports

When operator-created NetworkPolicies restrict pod ingress, the following
ztunnel/ambient mesh ports must be explicitly allowed:

| Port  | Purpose                    |
|-------|----------------------------|
| 15006 | Waypoint proxy             |
| 15008 | HBONE tunnel termination   |
| 15020 | Istio health checks        |
| 15021 | Istio metrics              |

These are ztunnel's standard ports and are required for ambient mesh to function
when NetworkPolicies are present. Without them, ztunnel cannot deliver proxied
traffic to pods, producing `connection timed out, maybe a NetworkPolicy is
blocking HBONE port 15008`.

## Keycloak JGroups and HBONE

Keycloak's JGroups clustering protocol requires special configuration to work
through ztunnel:

1. **Disable embedded mTLS** (`cache-embedded-mtls-enabled: false`) — prevents
   double encryption (Keycloak's own TLS inside ztunnel's HBONE TLS).

2. **Use jdbc-ping discovery** (default in Keycloak 26.x) — database-based
   node discovery avoids the timing-sensitive DNS_PING protocol. The shared
   PostgreSQL database serves as the cluster registry.

3. **Additive NetworkPolicy** — the operator's NetworkPolicy is restrictive by
   design (only allowing JGroups between Keycloak-labeled pods). An additional
   policy must allow ztunnel infrastructure ports and JGroups from ztunnel
   pods.

## References

- [Istio ambient mesh traffic redirection](https://istio.io/latest/docs/ambient/architecture/traffic-redirection/)
- [Keycloak: Configuring distributed caches](https://www.keycloak.org/server/caching)
- [Keycloak: Running inside a service mesh](https://www.keycloak.org/server/caching#_running_inside_a_service_mesh)
- `design/adr/0003-ambient-mesh-exclusions.md` — original exclusion decision and resolution
