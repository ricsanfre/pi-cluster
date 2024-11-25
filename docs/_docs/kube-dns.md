---
title: DNS (CoreDNS and External-DNS)
permalink: /docs/kube-dns/
description: Kubernetes DNS setup. CoreDNS and External-DNS installation and configuration
last_modified_at: "23-11-2024"
---

PODs within Kubernetes will use DNS service to discover Kubernetes services and external services. [CoreDNS](https://coredns.io/) is the default Kubernetes DNS service that need to be deployed in the cluster.

Kubernetes DNS service provided by CoreDNS is complemented with [ExternalDNS](https://github.com/kubernetes-sigs/external-dns).

External DNS is used to synchronize exposed Kubernetes Services (LoadBalancer type services) and Ingresses with cluster authoritative DNS server, Bind9. So DNS records associated to exposed services can be automatically created and services can be accessed from out-side using their DNS names.

DNS kubernetes services will relay on DNS split horizon architecture deployed for the cluster. See details in [Pi Cluster - DNS Architecture](/docs/dns/).

## CoreDNS

Pods and kubernetes services are automatically discovered, using Kubernetes API, and assigned a DNS name within cluster-dns domain (default `cluster.local`) so they can be accessed by PODs running in the cluster. 
  
CoreDNS also takes the role of Resolver/Forwarder DNS to resolve POD's dns queries for any domain, using default DNS server configured at node level.  

![core-dns-architecture](/assets/img/core-dns-architecture.png)

### Installation

Using [CoreDNS Helm Chart](https://github.com/coredns/helm)

- Add Git repo

  ```shell
  helm repo add coredns https://coredns.github.io/helm
  ```

- Install helm chart in `kube-system` namespace
  ```shell
  helm --namespace=kube-system install coredns coredns/coredns
  ```


## ExternalDNS

ExternalDNS synchronizes exposed Kubernetes Services and Ingresses with DNS providers.

ExternalDNS allows you to control DNS records dynamically via Kubernetes resources in a DNS provider-agnostic way.

![external-dns-architecture](/assets/img/external-dns-architecture.png)

### How does it work?

ExternalDNS makes Kubernetes resources discoverable via public DNS servers. Like CoreDNS, it retrieves a list of resources (Services, Ingresses, etc.) from the [Kubernetes API](https://kubernetes.io/docs/api/) to determine a desired list of DNS records. Unlike CoreDNS, however, it’s not a DNS server itself, but merely configures other DNS providers.

Details on how to configure rfc2136 provider, used for integrating Bind9, can be found in
[External-DNS documentation- RFC2136 Provider](https://kubernetes-sigs.github.io/external-dns/latest/docs/tutorials/rfc2136/)


### Configuring rfc2136 provider (Bind9)


- Create TSIG shared key
  First a TSIG shared key can be created using `tsig-keygen` command:

  ```shell
  tsig-keygen -a hmac-sha512 externaldns-key > /etc/bind/keys/external-dns.key
  ```

- Include shared key in `named` configuration
  
  Update `named.conf.options` file with the following 
  
  ```
  // The following keys are used for dynamic DNS updates
  include "/etc/bind/keys/external-dns.key";  
  ```


- Configure zone to accept dynamic updates

  Dynamic updates from external-dns is allowed including  `update-policy` and `allow-transfer` clauses in the `zone` statement.
  
  Update `named.conf.local`

  ```
  zone "homelab.ricsanfre.com" {
    type primary;
    file "/var/lib/bind/db.homelab.ricsanfre.com";
    allow-transfer {
        key "externaldns-key";
    };
    update-policy {
        grant extenaldns-key zonesub any;
    };
  };
  ```
  
- Reload or restart bind9

### Installation

- Add Helm repository

  ```shell
  helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
  ```

- Store TSIG secret into a Kubernetes secret
  ```yaml
  apiVersion: v1
  kind: Secret
  metadata:
    name: external-dns-bind9-secret
    namespace: external-dns
  data:
    ddns-key: <base64 encode of the tsig key>
  ``` 

- Prepare `external-dns-values.yaml`

 ```yaml
 provider:
  name: rfc2136

  env:
    - name: EXTERNAL_DNS_RFC2136_HOST
      value: "10.0.0.11"
    - name: EXTERNAL_DNS_RFC2136_PORT
      value: "53"
    - name: EXTERNAL_DNS_RFC2136_ZONE
      value: homelab.ricsanfre.com
    - name: EXTERNAL_DNS_RFC2136_TSIG_AXFR
      value: "true"
    - name: EXTERNAL_DNS_RFC2136_TSIG_KEYNAME
      value: externaldns-key
    - name: EXTERNAL_DNS_RFC2136_TSIG_SECRET_ALG
      value: hmac-sha512 
    - name: EXTERNAL_DNS_RFC2136_TSIG_SECRET
      valueFrom:
        secretKeyRef:
          name: external-dns-bind9-secret
          key: ddns-key

  policy: sync
  registry: txt
  txtOwnerId: k8s
  txtPrefix: external-dns-
  sources: 
    - crd
    - service
    - ingress

  domainFilters: 
    - homelab.ricsanfre.com
  serviceMonitor:
    enabled: true
 ```

With this configuration External-DNS will listen to Ingress, Services, Istio-Gateway and external-dns specific DNSEndpoint Resources (`sources`) containing references to hostnames in domain `homelab.ricsanfre.com` (`domainFilter`), and it will create the corresponding DNS records in the DNS server specified by `EXTERNAL_DNS_RFC2136_HOST` environement variable using the TGSIG key speficied by `EXTERNAL_DNS_RFC2136_TSIG_*` environment variables.

It also enables the Prometheus `serviceMonitor.enabled`


{{site.data.alerts.important}}

Environment variables
external-dns supports all arguments as environment variables adding the prefix "EXTERNAL_DNS_" and uppercasing the parameter name, converting all hyphen into underscore
so `rfc2136-tsig-secret`, becomes EXTERNAL_DNS_RFF1236_TSIG_SECRET

{{site.data.alerts.end}}

- Install helm chart

  ```shell
  helm install external-dns external-dns/external-dns -n external-dns -f external-dns-values.yaml
  ```

### Use external-dns

To use external-dns add an ingress or a LoadBalancer service with a host that is part of the domain-filter

For example the following wll add A records to the DNS:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  annotations:
    external-dns.alpha.kubernetes.io/hostname: svc.homelab.ricsanfre.com
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: nginx
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
    name: my-ingress
spec:
    rules:
    - host: ingress.homelab.ricsanfre.com
      http:
          paths:
          - path: /
            backend:
                serviceName: my-service
                servicePort: 8000
```

Services of type "LoadBalancer" need to be annotated with `external-dns-aplpha.kubernetes.io/hostname`
Ingress resources does not need to be annotated. If the host is part of domain-filter it will be added automatically.

Also new DNS records can be created using external-dns specific CRD (DNSEndpoint)

```yaml
apiVersion: externaldns.k8s.io/v1alpha1
kind: DNSEndpoint
metadata:
  name: examplednsrecord
spec:
  endpoints:
  - dnsName: foo.homelab.ricsanfre.com
    recordTTL: 180
    recordType: A
    targets:
    - 10.0.0.216
```