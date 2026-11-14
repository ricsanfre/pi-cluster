---
title: Kubernetes development environment
permalink: /docs/dev/
description: How to configure a development environment for the Pi Cluster using K3D, with a manual walkthrough and an automated base + profiles workflow.
last_modified_at: "09-11-2026"

---

The development setup is the following:

- A dedicated docker network is configured for the cluster
- k3d cluster installed disabling flannel CNI, kube-proxy and load balancer.
- Cilium is installed as CNI which also takes care of the routing which was handled by kube-proxy. 
- Cilium L2-LB awareness is enabled, and a set of IP’s are configured for Loadbalancers services and advertised via L2 announcements. 
- Docker cluster nodes and Load balancer Kubernetes services are reachable from local host through docker network
- A local BIND9 resolver on the laptop is authoritative for `local.test` and its
  `picluster.local.test` child zone, so `<svc>.picluster.local.test`,
  `rustfs.picluster.local.test` and `vault.picluster.local.test` resolve to the
  dev addresses without `kubectl port-forward` (see [BIND9](#bind9))

{{site.data.alerts.note}}
The recommended path is the automated workflow (`make -C dev dev-up`). The
manual walkthrough below is kept so each step can be understood and debugged.
Both use the same k3d network, Cilium, CoreDNS and Flux components, and the dev
cluster now runs the same k3s minor as production (`v1.37.1+k3s1`).
{{site.data.alerts.end}}

## Automated workflow (recommended)

The automated workflow is implemented in `dev/` and `kubernetes/clusters/dev/`.
It creates the Docker network, the k3d cluster, the external RustFS/Vault
services, and bootstraps Cilium, CoreDNS and Flux.

### Quick start

```bash
cd dev
make dev-preflight   # tools + MemAvailable check (>= 8 GiB)
make dev-up          # network + cluster + external services + Flux + smoke
make dev-status      # context guard, Flux, HelmReleases, pods, warnings
make dev-smoke       # nodes, DNS, metrics, local-path PVC, base pods
make dev-usage       # host memory, docker stats, kubectl top
make dev-down        # stop external services and delete the cluster (data kept)
make dev-recreate    # down + up + smoke
make dev-destroy     # cluster + services data + certs + credentials (asks first)
```

`dev-preflight` refuses to continue if the host has less than 8 GiB available or
a required tool is missing (`docker`, `docker compose`, `k3d`, `kubectl`,
`helm`, `flux`, `openssl`, `curl`, `tmpl`), and checks that
`dev/external-services/certs` is writable by the invoking user. Every Make
target that touches the cluster asserts the `k3d-picluster` kubectl context.

### Lifecycle and ordering

`dev-up` is ordered so that no step waits on a later one:

1. `create_cluster.sh` — Docker network, k3d cluster, kubectl context, API ready.
2. `dev-prepare` → `prepare.sh` — `gen-env.sh` and `gen-certs.sh` (host-only).
3. `dev-seed-ca` → `seed-ca.sh` — publish the CA into the cluster.
4. `dev-services-up` → `up.sh` — Compose, buckets, dev Vault token.
5. `bootstrap.sh` — Cilium, CoreDNS, flux-operator, flux-instance, root
   Kustomization.
6. `smoke.sh` — nodes, DNS, storage, metrics, RustFS.

External services come **before** Flux so that the profiles consuming RustFS and
Vault (`secrets`, `velero`, `loki`, `tempo`, `keycloak`) reconcile against
healthy endpoints on their first attempt. They only need the Docker network and
the API server, both of which exist after step 1.

The CA seed is deliberately **before** Flux and independent of any profile:
`seed-ca.sh` creates the `cert-manager` and `external-secrets` namespaces
itself and writes `Secret/cert-manager/dev-root-ca` while the API server is the
only thing running. `ClusterIssuer/ca-issuer` therefore always finds its secret,
and enabling `cert-manager` or `ingress` later needs nothing but a Flux
reconcile — there is no window where `cert-manager-config` waits on a missing
secret and holds back `envoy-gateway-config`. `dev-up` runs the seed exactly
once; re-running `seed-ca.sh` afterwards only picks up consumer namespaces that
the profiles created (`velero`, `loki`, `tempo`).

Three teardown levels exist, from least to most destructive:

| Command | Deletes |
| --- | --- |
| `make dev-down` | k3d cluster; services stopped, `data/` and `certs/` kept |
| `make dev-recreate` | the cluster, then `dev-up` again; data/certs kept |
| `make dev-destroy` | cluster, `data/`, `certs/`, `.env`, and the unused `picluster` network |
{: .table .border-dark }

### Base components

| Component | Dev setting |
| --- | --- |
| k3d | 1 server, 0 agents, 5 GiB cap; `K3D_AGENTS`/`K3S_IMAGE` overrides |
| Cilium | 1 operator, kube-proxy replacement, Hubble disabled |
| CoreDNS | 1 replica |
| Flux | source + kustomize + helm controllers; notification disabled |
| metrics-server | for `kubectl top` |
| local-path | k3s bundled provisioner, default StorageClass |
| CoreDNS | answers the dev zone in-cluster: `rustfs`/`vault` + the gateway wildcard |
{: .table .border-dark }

The k3s image defaults to `rancher/k3s:v1.37.1-k3s1` to match prod. Override it
with `K3S_IMAGE=rancher/k3s:<tag>` or add agents with `K3D_AGENTS=1` for
multi-node scheduling tests.

### Profiles

Profiles are opt-in. Add one file per profile to
`kubernetes/clusters/dev/profiles/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - cert-manager.yaml
  - cnpg.yaml
```

| Profile | Contents | Requires |
| --- | --- | --- |
| `cert-manager` | cert-manager + self-signed CA issuers | — |
| `ingress` | Envoy Gateway + dev CA wildcard certificate | `cert-manager` |
| `cnpg` | CloudNativePG operator | — |
| `secrets` | External Secrets Operator | Vault (`VAULT=1`) |
| `observability` | tuned kube-prometheus-stack + Grafana + k3s mixins + external scrape configs | — |
| `logging` | Loki single-binary + Fluent Bit | — |
| `tracing` | Tempo + OpenTelemetry Collector | — |
| `messaging` | Strimzi, schema-registry and kafdrop | — |
| `data` | MongoDB/Valkey operators + shared database resources | — |
| `keycloak` | Keycloak + PostgreSQL + Terraform config | `cnpg`, `secrets` |
| `velero` | Velero backup/restore + CSI snapshotter | `secrets` |
| `elastic` | ECK, Elasticsearch/Kibana, exporter and Fluentd | `secrets` |
| `network` | external-dns against the lab BIND server | `secrets`, lab reachable |
| `maintenance` | system-upgrade and descheduler | — |
| `e-commerce` | e-commerce demo workload | `cnpg`, `data`, `secrets`, `keycloak`, `messaging`, `ingress`, `tracing`, `observability` |
{: .table .border-dark }

Removing a profile from the list prunes its resources on the next reconcile.
Heavy profiles (`observability`, `messaging`, `keycloak`, `elastic`,
`e-commerce`) should not run more than two at a time on a 16 GB laptop.

Profiles that list `secrets` read credentials from the external dev Vault
(`VAULT=1 make dev-services-up`); only `observability` is fully self-contained.

`external-dns` needs the lab's BIND server reachable at `EXTERNAL_DNS_SERVER`
(`10.0.0.11`) and the TSIG key under `bind9/ddns` in the dev Vault. It publishes
into a zone named after `CLUSTER_DOMAIN`, which for dev is `picluster.local.test`;
the lab server has no such zone, so the `network` profile cannot publish dev
records and should be left off. The dev names live as `*.picluster` records in
the laptop's `local.test` zone, which that server does not serve either. Making
`network` usable would need a real `picluster.local.test` zone on the laptop
BIND with `allow-update` (and `EXTERNAL_DNS_SERVER` pointing at it), not a
subdomain inside `local.test`.

The `elastic` profile stores data on `local-path` and uses
`node.store.allow_mmap: false`, so no host `vm.max_map_count` tuning is required.

The dev `observability` profile is self-contained: there is no Vault, so the
Grafana instance uses the admin secret generated by the operator
(`grafana-admin-credentials`), only the Prometheus datasource, and `local-path`
persistence. Grafana CRDs are installed by the operator chart
(`install.crds: Create`); prod installs them from Ansible instead.

### Accessing services from the host

With the `ingress` profile enabled, Envoy Gateway is published on a
Cilium-assigned LoadBalancer IP — `HTTP_GATEWAY_LOAD_BALANCER_IP`, default
`172.30.200.1` — on the `picluster` Docker bridge. The host already has a route
to `172.30.0.0/16` through that bridge, so the gateway is reachable without
`kubectl port-forward`; only DNS and TLS trust are missing.

![k3d dev network namespaces](/assets/img/pi-cluster-dev-k3d-architecture.png)

The diagram is split by network namespace: the host owns the `picluster` bridge
and the `veth` side of every pair, the containers own the other side. `veth1`
pairs with the k3d node, `veth2` with RustFS and `veth3` with Vault. Cilium
answers ARP for the LoadBalancer IP `172.30.200.1` on that bridge, which is why
the host reaches it without a port mapping. With `K3D_AGENTS=1` the agent
containers join the same bridge at `172.30.0.3`, `172.30.0.4`, …; the L2
announcer answers for `172.30.200.1` from whichever node holds the lease.

Host requests go from the tools to the bridge and straight to the LoadBalancer
IP or to the two container IPs — no port mapping involved. Pods resolve the same
names through CoreDNS, which answers the dev zone itself with three chained
`template` rules: `rustfs` and `vault` get their container addresses, every
other single-label name goes to the gateway. The published `127.0.0.1` ports
(RustFS `:9091`/`:9092`, Vault `:8200`) are a fallback that bypasses DNS and the
gateway; pods cannot use them. The `elastic` profile additionally claims
`172.30.200.12` for the Fluentd LoadBalancer.

{{site.data.alerts.note}}
CoreDNS cannot forward the dev zone to the laptop resolver: it forwards to the
node's `/etc/resolv.conf`, which is Docker's embedded resolver, and that
resolver's upstream is the host's loopback stub — unreachable from a container
namespace. Answering the zone in CoreDNS also keeps pods independent of whether
BIND is running.
{{site.data.alerts.end}}

The dev `CLUSTER_DOMAIN` is `picluster.local.test`, an RFC 2606 `.test` name
that is never published to the lab BIND. The laptop resolver described in
[BIND9](#bind9) serves it as a child zone of `local.test`; `127.0.0.1` would
not work because nothing listens on the host's port 80/443 — `k3d`'s load
balancer and `servicelb` are disabled.

Inside that zone the wildcard sends `<svc>.picluster.local.test` to Envoy
Gateway, while the exact `rustfs` and `vault` records keep the external
services on `172.30.100.10` and `172.30.100.11`. The parent `local.test`
wildcard does not interfere: BIND answers from the longest matching zone.

`*.picluster.local.test` is signed by the dev CA, which also signs the RustFS
and Vault server certificates, so a single trust entry covers the gateway and
both external services. See [Private PKI](#private-pki-dev-only) for how the
CA is created, published into the cluster and rotated.

Verify routing, TLS and DNS in that order before opening a browser:

```bash
# bypass DNS: does the gateway answer and present a valid chain?
curl -sv --cacert dev-ca.crt \
  --resolve app.picluster.local.test:443:172.30.200.1 https://app.picluster.local.test/ -o /dev/null

# through the resolver
dig +short app.picluster.local.test      # expected: 172.30.200.1
curl -sv https://app.picluster.local.test/ -o /dev/null

# the external services
dig +short rustfs.picluster.local.test   # expected: 172.30.100.10
dig +short vault.picluster.local.test    # expected: 172.30.100.11
curl -sS --cacert dev-ca.crt https://rustfs.picluster.local.test:9091/health
curl -sS --cacert dev-ca.crt https://vault.picluster.local.test:8200/v1/sys/health
```

{{site.data.alerts.note}}
Use `https://` explicitly. The `public-gateway` `http` listener only accepts
routes from the `envoy-gateway-system` namespace (the HTTPS redirect), so
workload `HTTPRoute`s attach to the `https` listener only.
{{site.data.alerts.end}}

Two more constraints:

- The wildcard certificate covers a single label: `app.picluster.local.test` is
  valid, `a.b.picluster.local.test` is not.
- Pods that call the gateway by hostname (Keycloak issuer URLs, OIDC callbacks)
  must resolve it inside the cluster too. The dev CoreDNS overlay answers the
  zone itself with chained `template` rules: the two exact names resolve to the
  external containers, the single-label wildcard to the gateway. See
  `kubernetes/platform/coredns/app/overlays/dev/values.yaml` — the `servers`
  list is repeated there because Helm replaces lists instead of merging them.

### Private PKI (dev only)

Dev has a single private CA. `dev/external-services/gen-certs.sh` creates it
(`certs/ca.crt`) and signs the RustFS and Vault server certificates with it;
cert-manager signs the cluster certificates with the same CA through
`ClusterIssuer/ca-issuer`, which in dev is backed by the `dev-root-ca` Secret
instead of the self-signed root that prod uses. The result is one trust anchor:
`https://app.picluster.local.test/`,
`https://rustfs.picluster.local.test:9091` and
`https://vault.picluster.local.test:8200` all validate against the same CA.

`make -C dev dev-seed-ca` publishes it into the cluster:

| Object | Purpose |
| --- | --- |
| `Secret/cert-manager/dev-root-ca` | CA certificate and key; a `ca` type issuer needs the key to sign |
| `Secret/<ns>/rustfs-ca` | public CA for workloads that verify RustFS (`velero`, `databases`, `loki`, `tempo`) |
| `Secret/external-secrets/vault-ca` | public CA referenced by the dev `ClusterSecretStore` through `caProvider` |
{: .table .border-dark }

The seed is idempotent and no-ops on a non-k3d context or when the cluster is
unreachable. It creates the `cert-manager` and `external-secrets` namespaces if
they do not exist, because the issuer Secret is a prerequisite for the
cert-manager profile, not a product of it; consumer namespaces (`velero`, `loki`,
`tempo`, …) are only seeded when they already exist. Export the certificate for
the browser with:

```bash
cp dev/external-services/certs/ca.crt dev-ca.crt
# or read it back from the cluster:
kubectl --context k3d-picluster -n cert-manager get secret dev-root-ca \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > dev-ca.crt
```

{{site.data.alerts.important}}
Every consumer needs an explicit CA reference: a trust anchor is not a setting.
Velero reads `configuration.backupStorageLocation[].config.caCert`, CNPG reads
`spec.backup.barmanObjectStore.endpointCA`, and External Secrets reads
`caProvider`. The dev `vault-backend` ClusterSecretStore uses the seeded
`vault-ca` Secret; Velero and CNPG are not wired in dev yet — their `rustfs-ca`
Secret is seeded and waiting for those fields.

A `ClusterTrustBundle` is not published either. Nothing in the tree projects
one, its `spec.trustBundle` is inline PEM with no `secretRef` (so it cannot be a
static manifest without committing the CA and letting it drift on rotation), and
trust-manager is not part of the dev stack. Publish one, or adopt trust-manager,
when a workload actually needs the cluster-wide anchor.
{{site.data.alerts.end}}

{{site.data.alerts.warning}}
The CA key has to live in a cluster Secret for the issuer to sign, so any
workload that can read `dev-root-ca` can mint certificates the laptop trusts.
That is acceptable for a disposable dev CA and never for prod, which uses Let's
Encrypt for public hostnames and the `components/internal-ca` self-signed CA
for cluster-internal certificates.

Deleting `certs/` rotates the CA. After that, re-run `gen-certs.sh` and
`make dev-seed-ca`, restart the compose stack, and delete the issued
Certificate secrets so cert-manager re-creates them — cert-manager does not
detect CA rotation on its own.
{{site.data.alerts.end}}

### Overlay conventions

Both environments share the same `base` and differ only through overlays and
components:

| Layer | Contains |
| --- | --- |
| `base/` | Chart reference, namespace and values that are identical in every environment |
| `components/<name>/` | Optional resources and value bundles (Grafana dashboards, ServiceMonitors, S3 ExternalSecrets, CNPG backups, Longhorn snapshot classes) |
| `overlays/dev/` | Dev-only values and patches: single replica, `local-path`, filesystem storage, dev Vault |
| `overlays/prod/` | Prod-only values and patches: replicas, Longhorn, S3/RustFS, prod Vault, ACME issuer |
{: .table .border-dark }

Rules of thumb:

- Base never carries a resource that an environment must delete. If dev does
  not need it, it belongs in a component that only prod includes.
- Env-specific choices (replica counts, storage class, issuer, IP ranges,
  endpoints, retention, credentials) live in the overlay, not in base.
- Overlays add or override; they should not need `$patch: delete` or
  `op: remove` against base.
- Grafana dashboards live under `components/monitoring` and are prod-only.
  ServiceMonitors and PodMonitors that dev also needs live under
  `components/metrics`, so a dev profile remains usable without the
  observability stack.

### External services

RustFS (and optional Vault) run outside the cluster in Docker Compose:

```bash
cd dev
make dev-services-up              # RustFS
VAULT=1 make dev-services-up      # RustFS + Vault
make dev-services-down            # stop, keep data
make dev-services-reset           # stop and delete data (confirmation)
```

The cluster reaches RustFS through `https://rustfs.picluster.local.test:9091` and
Vault through `https://vault.picluster.local.test:8200`; CoreDNS answers both
from its template rules, so pods use the same names as the host. Both serve TLS
with the dev CA. The CA is seeded into POC namespaces as the `rustfs-ca` Secret
by `dev-poc-new.sh`, and into the other consumer namespaces (`rustfs-ca`,
`vault-ca`) by `make dev-seed-ca`.

### POC workflow

```bash
cd dev
make dev-poc-new NAME=cnpg-barman
```

This creates `test/cnpg-barman/` with a Namespace, ResourceQuota (requests
2 GiB, limits 3 GiB), LimitRange and a kustomization, plus a Flux Kustomization
in `kubernetes/clusters/dev/profiles/poc-cnpg-barman.yaml`. Add that file to
`profiles/kustomization.yaml` and commit.

### Resource budget

| Item | Budget |
| --- | --- |
| Host baseline (browser + editor) | ~4.6 GiB |
| Host reserve | ~2 GiB |
| Usable for cluster + external services | ~8.5 GiB |
| Single-node k3d cap | 5 GiB |
| Base measured target | <= 1.5 GiB |
| POC namespace quota | requests 2 GiB, limits 3 GiB |
{: .table .border-dark }

Expected combinations:

| Combination | Estimated total | Verdict |
| --- | --- | --- |
| Base + `cnpg` + RustFS | ~2.7 GiB | comfortable |
| Base + `cnpg` + `ingress` + RustFS | ~3.0 GiB | comfortable |
| Base + `observability` + `cnpg` + `ingress` | ~3.8 GiB | fine |
| Base + `messaging` + `observability` | ~3.7 GiB | memory-fine, CPU-tight |
| Base + all heavy profiles | ~5–6 GiB | not recommended |
{: .table .border-dark }

### Limitations and troubleshooting

- **Longhorn is not supported in k3d.** Dev uses `local-path`; PVCs are
  node-local and lost with the cluster. The `longhorn/app` dev overlay sets one
  replica and a `/var/lib/longhorn` data path, but Longhorn also needs
  `iscsid`/open-iscsi on the Docker host, which is not installed here, so it is
  kept for parity and is not validated.
- **cert-manager-webhook-ionos is prod-only.** Dev uses the self-signed CA
  issuer from the `cert-manager` profile; the IONOS DNS-01 webhook needs
  credentials that only exist in prod.
- **Istio ambient is not usable on k3d.** The Istio CNI plugin rewrites
  Cilium's `/etc/cni/net.d/05-cilium.conflist`; pod sandbox creation then fails
  (`FailedCreatePodSandBox`) and the node eventually reports `NotReady`. The
  `istio/app` dev overlay is kept for rendering and prod parity, but there is no
  dev profile for Istio or Kiali. Recovery: remove the profile (Flux prunes
  Istio and the CNI agent restores the Cilium config), then restart the k3d
  node if it stays `NotReady`.
- The cluster is x86-only in practice; prod is hybrid ARM64/AMD64.
- The dev CA is local and untrusted. Do not reuse it outside the dev cluster.
- Flux tracks `master`. Branch validation must follow the `flux-change`
  procedure and be reverted afterwards.

| Symptom | Check |
| --- | --- |
| Wrong context | Use `--context k3d-picluster` (dev) or `--context picluster-prod` (lab) |
| Flux not reconciling | `make dev-status`; `flux get kustomizations -A` |
| Pods Pending after create | Cilium not Ready: `kubectl -n kube-system rollout status ds/cilium` |
| DNS failures | `kubectl -n kube-system get pods -l k8s-app=kube-dns` |
| PVC Pending | `local-path` uses `WaitForFirstConsumer`; a consumer pod is required |
| RustFS unreachable | `make dev-services-up`; check `https://127.0.0.1:9091/health` with the dev CA |
| RustFS TLS errors in a pod | `make dev-seed-ca` seeds `rustfs-ca`; reference it with `endpointCA` |
| Vault unreachable | `VAULT=1 make dev-services-up`; `curl --cacert dev/external-services/certs/ca.crt https://127.0.0.1:8200/v1/sys/health` |
| Vault TLS errors from ESO | `make dev-seed-ca` seeds `vault-ca`; the `vault-backend` store reads it via `caProvider` |
| Memory pressure | `make dev-usage`; remove a heavy profile; `make dev-down` |
| Cluster wedged | `make dev-recreate` (external data is kept) |
{: .table .border-dark }

## Preparing the development environment

The following need to be installed in your local development environment

- Docker
- a `picluster` Docker bridge network for the cluster and its external services
- BIND9 (local resolver for the `local.test` and `picluster.local.test` zones)
- [K3D](https://k3d.io/)
- kubectl
- helm

### Docker


Follow official [installation guide](https://docs.docker.com/engine/install/ubuntu/).

- Step 1. Uninstall old versions of docker

  ```shell
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
  ```

- Step 2. Install packages to allow apt to use a repository over HTTPS

  ```shell
  sudo apt-get update

  sudo apt-get install \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release
  ```
  
- Step 3. Add Docker's official GPG key

  ```shell
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  ```
  
- Step 4: Add x86_64 repository 

  ```shell
  echo \
    "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  ```

- Step 5: Install Docker Engine

  ```shell
  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  ```

- Step 6: Enable Docker management with a non-privileged user

  - Create docker group

    ```shell
    sudo groupadd docker
    ```
    
  - Add user to docker group

    ```shell
    sudo usermod -aG docker $USER
    ```
    
- Step 7: Configure Docker to start on boot

  ```shell
  sudo systemctl enable docker.service
  sudo systemctl enable containerd.service
  ```

- Step 8: Configure docker daemon.

  - Edit file `/etc/docker/daemon.json`
  
    Set storage driver to overlay2 and to use systemd for the management of the container’s cgroups.
    Optionally default directory for storing images/containers can be changed to a different disk partition (example /data).
    Documentation about the possible options can be found [here](https://docs.docker.com/engine/reference/commandline/dockerd/#daemon-configuration-file)
    
    ```json
    {
        "exec-opts": ["native.cgroupdriver=systemd"],
        "log-driver": "json-file",
        "log-opts": {
        "max-size": "100m"
        },
        "storage-driver": "overlay2",
        "data-root": "/data/docker"  
    }
    ``` 
  - Restart docker

    ```shell
    sudo systemctl restart docker
    ```

### Docker network

The k3d nodes and the external services (RustFS, Vault) share one Docker bridge
network. Create it before the DNS zones below, so every address in them comes
from a network that already exists. The command is idempotent-safe:

```shell
docker network inspect picluster >/dev/null 2>&1 || docker network create \
      --driver bridge \
      --subnet "172.30.0.0/16" \
      --gateway "172.30.0.1" \
      --ip-range "172.30.0.0/17" \
      "picluster"
```

`dev/create_cluster.sh` and `dev/external-services/up.sh` reuse the network when
it is already there, so running this by hand changes nothing.

| Address | Used by |
| --- | --- |
| `172.30.0.1` | bridge gateway, reachable from the host |
| `172.30.0.2` | k3d server (agents follow at `.3`, `.4`, …) |
| `172.30.100.10` / `.11` | RustFS / Vault, fixed in `compose.yaml` |
| `172.30.200.1–254` | Cilium LB-IPAM pool: Envoy Gateway `.1`, Fluentd `.12` |
| `127.172.30.1:6443` | k3s API endpoint as seen from the host |
{: .table .border-dark }

The `local.test` records in the next section point at these addresses.

### BIND9

The dev hostnames are resolved by a BIND9 instance running on the laptop. It
is authoritative for `local.test` (used by other local projects) and for the
`picluster.local.test` child zone that holds everything the dev environment
publishes. Nothing is delegated to or published in the lab DNS.

- Step 1. Install BIND9 and its tools

  ```shell
  sudo apt-get update
  sudo apt-get install -y bind9 bind9utils bind9-dnsutils
  ```

- Step 2. Make sure BIND9 can own port 53

  `systemd-resolved` normally listens on `127.0.0.53:53`. Check it with:

  ```shell
  sudo ss -lntp 'sport = :53'
  ```

  If `systemd-resolved` owns the port, free it by setting `DNSStubListener=no`
  in `/etc/systemd/resolved.conf`, restarting `systemd-resolved`, and pointing
  `/etc/resolv.conf` at `nameserver 127.0.0.1` so the host queries BIND9.

- Step 3. Declare both zones in `/etc/bind/named.conf.local`

  ```bind
  zone "local.test" {
      type master;
      file "/etc/bind/db.local.test";
  };

  zone "picluster.local.test" {
      type master;
      file "/etc/bind/db.picluster.local.test";
  };
  ```

  No delegation is needed in `local.test`: both zones are served by the same
  instance, which answers from the longest matching zone.

- Step 4. Create the parent zone `/etc/bind/db.local.test`

  ```bind
  $TTL 2d
  $ORIGIN local.test.

  @   IN  SOA  ns.local.test. admin.local.test. (
               2026110901 ; serial
               12h        ; refresh
               15m        ; retry
               3w         ; expire
               2h )       ; minimum TTL
      IN  NS   ns.local.test.
  ns  IN  A    127.0.0.1
  *   IN  A    127.0.0.1
  ```

- Step 5. Create the dev zone `/etc/bind/db.picluster.local.test`

  ```bind
  $TTL 2d
  $ORIGIN picluster.local.test.

  @        IN  SOA  ns.picluster.local.test. admin.picluster.local.test. (
                  2026110901 ; serial
                  12h        ; refresh
                  15m        ; retry
                  3w         ; expire
                  2h )       ; minimum TTL
           IN  NS   ns.picluster.local.test.
  ns       IN  A    127.0.0.1
  *        IN  A    172.30.200.1    ; Envoy Gateway: <svc>.picluster.local.test
  rustfs   IN  A    172.30.100.10   ; RustFS S3:9091 + console:9092
  vault    IN  A    172.30.100.11   ; Vault:8200
  ```

  The wildcard sends application hostnames to the k3d Envoy Gateway; the exact
  `rustfs` and `vault` records win over it and keep the external services on
  their own container addresses.

- Step 6. Validate, load and test

  ```shell
  sudo named-checkconf
  sudo named-checkzone local.test /etc/bind/db.local.test
  sudo named-checkzone picluster.local.test /etc/bind/db.picluster.local.test
  sudo systemctl restart named
  ```

  ```shell
  dig +short app.picluster.local.test      # 172.30.200.1
  dig +short rustfs.picluster.local.test   # 172.30.100.10
  dig +short vault.picluster.local.test    # 172.30.100.11
  dig +short db.local.test                 # 127.0.0.1
  ```

  Bump the SOA serial whenever a zone changes, and reload it with
  `sudo rndc reload <zone>` after editing a file.

{{site.data.alerts.note}}
The three dev records can also live in the existing `local.test` zone as
`*.picluster`, `rustfs.picluster` and `vault.picluster` entries. The child zone
is preferable: it keeps the dev names together, and it is the only layout that
can accept dynamic updates if `external-dns` is ever enabled in dev (the
`network` profile expects `EXTERNAL_DNS_RFC2136_ZONE` to be a real zone).
{{site.data.alerts.end}}

{{site.data.alerts.note}}
If you restrict `listen-on` or `allow-query` in `/etc/bind/named.conf.options`,
keep `127.0.0.1` reachable. Allowing `172.30.0.1` (the `picluster` bridge
address) also lets k3d containers query the laptop resolver directly, which is
an alternative to the CoreDNS `template` workaround described in
[Accessing services from the host](#accessing-services-from-the-host).
{{site.data.alerts.end}}

### K3D

Follow official [K3D installation guide](https://docs.docker.com/engine/install/ubuntu/).

- Step 1. Uninstall old versions of docker

  ```shell
  wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  ```


- Step 3. Check k3d version installed

  ```shell
  $ k3d version
  k3d version v5.8.3
  k3s version v1.37.1-k3s1 (default)
  ```

### Kubectl


Follow official [kubectl installation guide](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)

- Step 1: Download latest stable version

  ```shell
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  ```


- Step 2: Install kubectl in /usr/local/bin

  ```shell
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  ```

- Step 3: Check version installed

  ```shell
  $ kubectl version --client --output=yaml
  clientVersion:
    buildDate: "2024-06-11T20:29:44Z"
    compiler: gc
    gitCommit: 39683505b630ff2121012f3c5b16215a1449d5ed
    gitTreeState: clean
    gitVersion: v1.30.2
    goVersion: go1.22.4
    major: "1"
    minor: "30"
    platform: linux/amd64
  kustomizeVersion: v5.0.4-0.20230601165947-6ce0bf390ce3
  ```

### Cluster contexts

One kubeconfig can describe both clusters; they are distinguished by context name:

| Context | Cluster | Written by |
| --- | --- | --- |
| `picluster-prod` | lab (`10.0.0.10:6443`) | `make k3s-install` |
| `k3d-picluster` | local k3d cluster | `make dev-up` |
{: .table .border-dark }

`k3s_install.yml` writes the production entry to `$HOME/.kube/pi-cluster.yaml`
and merges it into `$HOME/.kube/config`, so reinstalling the lab never deletes
the dev context. Pass `--context` rather than relying on the current context:

```shell
kubectl --context picluster-prod get nodes
kubectl --context k3d-picluster get pods -A
```

Running any `dev/` target switches the current context to `k3d-picluster`.

`flux` takes the same global flags (`--context`, `--kubeconfig`, before or
after the subcommand) and honours `KUBECONFIG`, so scripts can target a cluster
without touching the current context:

```shell
flux --context picluster-prod get kustomizations -A
flux --context k3d-picluster reconcile kustomization flux-system --with-source
```

### Helm

- Step 1: Download helm install script

  ```shell
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  $ chmod 700 get_helm.sh
  $ ./get_helm.sh
  ```
- Step 2: Give it executable permissions
  
  ```shell
  chmod 700 get_helm.sh
  ```
- Step 3: Install helm

  ```shell
  ./get_helm.sh
  ```

- Step 4: Check version

  ```shell
  $ helm version
  version.BuildInfo{Version:"v3.15.3", GitCommit:"3bb50bbbdd9c946ba9989fbe4fb4104766302a64", GitTreeState:"clean", GoVersion:"go1.22.5"}
  ```

## Creating dockerized k3s cluster

k3s cluster can be created using K3D. The cluster will be configured with same options as production environment:

- CNI cilium is used, instead of default Flannel
- All K3s add-ons are not installed (traefik, helmcontroller, localpath, coredns, etc.)
- kube-proxy is disabled (Cilium Kube-proxy replacement feature will be used)
- Cilium L2 LB announcement will be used


### Prerequisites

#### Enable kernel modules

Since cilium uses IPtables to write routes to kernel, we need to enable additional kernel modules

```shell
sudo modprobe -v iptable_filter  
sudo modprobe -v ip_tables  
sudo modprobe -v iptable_mangle  
sudo modprobe -v iptable_raw  
sudo modprobe -v iptable_nat  
sudo modprobe -v xt_socket
```
Add this configuration in kernel modules configuration file to persist the modules after restart

```shell
echo "iptable_filter
ip_tables
iptable_mangle
iptable_raw
iptable_nat
xt_socket" | sudo tee /etc/modules-load.d/modules.conf
```

#### Ensure sysctl parameters are enabled

```shell
echo "net.core.devconf_inherit_init_net=1
net.netfilter.nf_conntrack_max=196608
net.ipv4.conf.all.forwarding = 1 | sudo tee /etc/sysctl.d/01-sysctl.conf > /dev/null

sudo sysctl -p
```


### Creating K3D cluster

The cluster attaches to the `picluster` network created in
[Docker network](#docker-network); `k3d-cluster.yaml` selects it with
`network: picluster`.

- Step 1. Create k3d-config.yaml file

  In the repository this file is generated from
  `dev/k3d-cluster/k3d-cluster.yaml.tmpl` by `dev/create_cluster.sh`
  (`make -C dev create-k3d`). The rendered example is:

  ```yaml
  apiVersion: k3d.io/v1alpha5
  kind: Simple
  metadata:
    name: picluster
  servers: 1
  # Default dev topology is single-node. Use K3D_AGENTS=1 (or 2) for
  # scheduling/failover POCs; multi-node partitions the same laptop memory.
  agents: 0
  kubeAPI: # same as `--api-port myhost.my.domain:6445` (where the name would resolve to 127.0.0.1)
    hostIP: 127.172.30.1 # where the Kubernetes API will be listening on
    hostPort: "6443"
  # Setting version of k3s
  # Same k3s minor as prod; override with K3S_IMAGE for a POC.
  image: rancher/k3s:v1.37.1-k3s1
  # Setting docker network to be used
  network: picluster
  options:
    # Disable Load balancer
    k3d:
      disableLoadbalancer: true
    # Extra arguments for k3s
    k3s:
      extraArgs:
        - arg: --tls-san=127.0.0.1
          nodeFilters:
            - server:*
        # Disable helmcontroller
        - arg: --disable-helm-controller
          nodeFilters:
            - server:*
        # Disable coreDNS
        - arg: --disable=coredns
          nodeFilters:
            - server:*
        # Disable traefik
        - arg: --disable=traefik
          nodeFilters:
            - server:*
        # Disable servicelb
        - arg: --disable=servicelb
          nodeFilters:
            - server:*
        # local-path is left enabled and is the default StorageClass.
        # Disable metric server
        - arg: --disable=metrics-server
          nodeFilters:
            - server:*
        # Disable network-policy
        - arg: --disable-network-policy
          nodeFilters:
          - server:*
        # Disable kube-proxy
        - arg: --disable-kube-proxy
          nodeFilters:
          - server:*
        # Disable flannel-backend
        - arg: --flannel-backend=none
          nodeFilters:
          - server:*
        # Adding cluster PODs and Services CIDRs
        - arg: --cluster-cidr=10.42.0.0/16
          nodeFilters:
            - server:*
        - arg: --service-cidr=10.43.0.0/16
          nodeFilters:
            - server:*
        # Exposing metrics
        - arg: --kube-controller-manager-arg=bind-address=0.0.0.0
          nodeFilters:
            - server:*
        - arg: --kube-scheduler-arg=bind-address=0.0.0.0
          nodeFilters:
            - server:*
    kubeconfig:
      updateDefaultKubeconfig: true
      switchCurrentContext: true  
  ```

  - By default this creates a single-node cluster (1 control plane node and 0 workers) connected to the docker network created before (`picluster`):

    - k3d-picluster-server-0, with IP 172.30.0.2

    Set `K3D_AGENTS=1` (or `2`) in `dev/create_cluster.sh` to add workers; each agent gets the next `172.30.0.x` address.

  - k3s version is defined through the corresponding docker image label (`image: rancher/k3s:v1.37.1-k3s1`), matching production.

  - Following k3s services are disabled: `kube-proxy`, `traefik`, `servicelb`, `flannel`, `network-policy` and `metrics-server` (Flux installs metrics-server). `local-path` is left enabled and is the default StorageClass.

  - k3d default load balancer is also disabled (`k3d.disableLoadbalancer: true`)


- Step 2: Create K3d cluster

  ```shell
  K3D_FIX_MOUNTS=1 K3D_FIX_DNS=0 k3d cluster create -c k3d-config.yaml
  ```

  In the repository, `make -C dev create-k3d` renders the template and runs
  the equivalent command. `make -C dev dev-up` also installs Cilium, CoreDNS
  and Flux afterwards.

  {{site.data.alerts.note}}

  **K3D_FIX_MOUNTS** environment variable need to be set before executing k3d command.
  That makes / in the node containers `rshared` mounts fixing issues with Cilium installation.
  See details in this these k3d issues: [#1268](https://github.com/k3d-io/k3d/pull/1268) and [#479](https://github.com/k3d-io/k3d/discussions/479).

  **K3D_FIX_DNS** environment variable need to be set also, so K3d DNS fix that is executed by default is disabled.

  Purpose of this DNS fix is to update defautl behaviour of DNS in docker. By default, containers use the Docker daemon’s embedded DNS resolver, which listens on the default DNS server IP address 127.0.0.11. This DNS server handles DNS queries from containers and forwards them to the appropriate DNS server for resolution.

  K3D_FIX_DNS variable makes k3d to execute a fixing script that modifies /etc/resolv.conf in the container to point to host IP address, so host stub DNS resolver can be used.

  However, DNS fix (K3D_FIX_DNS=1) breaks DNS resolution for external domain names (Internet)": See details in open k3d issue: [#1515](https://github.com/k3d-io/k3d/issues/1515)


  {{site.data.alerts.end}}

- Step 3: Check cluster is running 

  ```shell
  kubectl get nodes
  ```

  {{site.data.alerts.note}}
  The node stays `NotReady` until a CNI is installed. This is expected because
  flannel and kube-proxy are disabled; continue with the Cilium installation.
  {{site.data.alerts.end}}

### Installing Cilium CNI

In the automated workflow, `dev/bootstrap.sh` installs the same chart and Flux
adopts the release. The manual steps below are the equivalent for debugging or
for building the environment by hand.

Installation using `Helm` (Release 3):

- Step 1: Add Cilium Helm repository:

    ```shell
    helm repo add cilium https://helm.cilium.io/
    ```
- Step2: Fetch the latest charts from the repository:

    ```shell
    helm repo update
    ```
  
- Step 4: Create helm values file `cilium-values.yml`

  ```yaml
  # Cilium operator config
  operator:
    replicas: 1
    # Roll out cilium-operator pods automatically when configmap is updated.
    rollOutPods: true

    # Install operator on control-plane node
    nodeSelector:
      node-role.kubernetes.io/control-plane: "true"

  # Roll out cilium agent pods automatically when ConfigMap is updated.
  rollOutCiliumPods: true

  # K8s API service
  # K3s API server inside the k3d node
  k8sServiceHost: 127.0.0.1
  k8sServicePort: 6443

  # Replace Kube-proxy
  kubeProxyReplacement: true
  kubeProxyReplacementHealthzBindAddr: 0.0.0.0:10256

  # Configure IP Address Management mode.
  # https://docs.cilium.io/en/stable/network/concepts/ipam/
  ipam:
    operator:
      clusterPoolIPv4PodCIDRList: "10.42.0.0/16"

  # Configure L2 announcements (LB-IPAM configuration)
  l2announcements:
    enabled: true
  externalIPs:
    enabled: true

  # Increase the k8s api client rate limit to avoid being limited due to increased API usage 
  k8sClientRateLimit:
    qps: 50
    burst: 200
  
  # Istio configuration
  # https://docs.cilium.io/en/latest/network/servicemesh/istio/
  # Disable socket lb for non-root ns. This is used to enable Istio routing rules
  socketLB:
    hostNamespaceOnly: true
  # Istio uses a CNI plugin to implement functionality for both sidecar and ambient modes. 
  # To ensure that Cilium does not interfere with other CNI plugins on the node,
  cni:
    exclusive: false
  ```

- Step 5: Install Cilium in kube-system namespace

  ```shell
  helm upgrade --install cilium cilium/cilium \
    --version 1.20.4 \
    --namespace kube-system \
    -f cilium-values.yaml \
    --wait
  ```
 
- Step 1: Configure Cilium LB-IPAM

  Create the following manifest file: `cilium-config.yaml`
    ```yml
    ---
    apiVersion: "cilium.io/v2alpha1"
    kind: CiliumLoadBalancerIPPool
    metadata:
      name: "first-pool"
      namespace: kube-system
    spec:
      blocks:
        - start: "172.30.200.1"
          stop: "172.30.200.254"

    ---
    apiVersion: cilium.io/v2alpha1
    kind: CiliumL2AnnouncementPolicy
    metadata:
      name: default-l2-announcement-policy
      namespace: kube-system
    spec:
      externalIPs: true
      loadBalancerIPs: true
    ```
   
   Apply the manifest file

   ```shell
   kubectl apply -f cilium-config.yaml
   ```


- Step 6: Confirm that the deployment succeeded, run:

  ```shell
  kubectl -n kube-system get pod
  ``` 

{{site.data.alerts.note}}

For details about Cilium installation and configuration see ["Cilium CNI"](/docs/cilium/)

{{site.data.alerts.end}}


## References

- [Testing cilium with k3d and kind](https://blogops.mixinet.net/posts/testing_cilium_with_k3d_and_kind/)
- [Harnessing the Power of Cilium: A Guide to BGP Integration with Gateway API on IPv4](https://allanjohn909.medium.com/harnessing-the-power-of-cilium-a-guide-to-bgp-integration-with-gateway-api-on-ipv4-7b0d058a1c0d)
- [Integrating Cilium with Gateway API, IPv6, and BGP for Advanced Networking Solutions](https://allanjohn909.medium.com/integrating-cilium-with-gateway-api-ipv6-and-bgp-for-advanced-networking-solutions-5b41b0ca0090)
- [Understanding Docker DNS](https://medium.com/@prajwal.chin/understanding-docker-dns-2ed4b070a0)
- [k3d documentation](https://k3d.io/)
- [FluxCD documentation](https://fluxcd.io/flux/)
- [RustFS Docker installation](https://docs.rustfs.com/installation/docker/)
- [`dev/README.md`](https://github.com/ricsanfre/pi-cluster/blob/master/dev/README.md) — automated workflow quickstart
- [`dev/external-services/README.md`](https://github.com/ricsanfre/pi-cluster/blob/master/dev/external-services/README.md) — RustFS/Vault details
