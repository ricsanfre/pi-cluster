---
title: DNS
permalink: /docs/dns/
description: DNS setup for homelab and Kubernetes cluster. 
last_modified_at: "19-11-2024"
---

Split-horizon DNS architecture is used in my homelab so services can be accessed from my private network and also they can be accessed from external network.

![dns-architecture](/assets/img/pi-cluster-dns-architecture.png)

Homelab DNS Architecture is composed of the following components:

- **Authoritative internal DNS server**, based on [Bind9](https://www.isc.org/bind/), deployed in one of the homelab nodes (`node1`). 

  Authoritative DNS server for homelab subdomain `homelab.ricsanfre.com`, resolving DNS names to homelab's private IP address.

- **Authoritative external DNS server**, IONOS/CloudFlare, resolving DNS names from same homelab subdomain `homelab.ricsanfre.com` to public IP addresses.

  Potentially this external DNS can be used to access internal services from Internet through my home network firewall, implementing a VPN/Port Forwarding solution.
  
  Initially all homelab services are not accesible from Internet, but that External DNS is needed for when generating valid TLS certificates with Let's Encrypt. DNS01 challenge used by Let's Encrypt to check ownership of the DNS domain before issuing the TLS certificate will be implemented using this external DNS service. 

- **Forwarder/Resolver DNS server**, based on `dnsmasq`, running in my homelab router (`gateway`), able to resolve recursive queries by forwarding the requests to the corresponding authoritative servers.

  Configured as DNS server in all homelab nodes. It forwards request for `homelab.ricsanfre.com` domain to Authoritative Internal DNS server runing in `node1` and the rest of request to default DNS servers 1.1.1.1 (cloudflare) and 8.8.8.8 (google)

This architecture is complemented with the following Kubernetes components:

- **Kubernetes DNS service**, [CoreDNS](https://coredns.io/). DNS server that can perform service discovery and name resolution within the cluster. 

  Pods and kubernetes services are automatically discovered, using Kubernetes API, and assigned a DNS name within cluster-dns domain (default `cluster.local`) so they can be accessed by PODs running in the cluster. 
  
  CoreDNS also takes the role of Resolver/Forwarder DNS to resolve POD's dns queries for any domain, using default DNS server configured at node level.  

![core-dns-architecture](/assets/img/core-dns-architecture.png)


- [ExternalDNS](https://github.com/kubernetes-sigs/external-dns), to synchronize exposed Kubernetes Services and Ingresses with cluster authoritative DNS, Bind9. So DNS records associated to exposed services can be automatically created and services can be accessed from out-side using their DNS names.


![external-dns-architecture](/assets/img/external-dns-architecture.png)


## Installation DNS Authoritative (Bind9)

Authoritative DNS server for homelab zone (`homlab.ricsanfre.com`) is deployed in one of the nodes of the cluster: `node1`


### Bind9 Installation

Use apt package manager to install Bind9 in a Ubuntu server.
    
```shell
sudo apt-get install bind9 bind9-doc dnsutils
```

Ubuntu packages install bind9 with a default configuration in `/etc/bind/named.conf`

  
#### About folders permissions in Ubuntu with AppArmor

Ubuntu bind9 packages install [[AppArmor]] profile `/etc/apparmor.d/usr.sbin.named`.
This profile set permissions for named application and control the access only to a set of directories.

Ubuntu packate configure Apparmor permissions so `/var/lib/bind` directory is configured with proper permissions to store and keep zones files and its journals. That is the folder that must be used to store the zone files in case DDNS is in going to be used. If that directory is not used, DDNS updates are not working because of permission issues.

The same happens with log directory: `/var/logs/named` directory should be used if AppArmor profile is active.

See [https://ubuntu.com/server/docs/domain-name-service-dns](https://ubuntu.com/server/docs/domain-name-service-dns)


### DNS Server Configuration

#### Disabling IPv6


- Edit `/etc/default/named` file:
  ```shell
  #
  # run resolvconf?
  RESOLVCONF=no
  
  # startup options for the server
  OPTIONS="-u bind"

  ```
- Add following `OPTIONS="-u bind -4"`

- Restart bind

  ```shell
  sudo systemctl restart bind9
  ```

#### Configuring the Options File

`/etc/bind/named.conf.options`

```
options {
  directory "/var/cache/bind";

  dnssec-validation auto;

  // listening addreses
  listen-on { any; };

  // allow query from any network
  allow-query { any; };
  
  // Disable recursive queries
  recursion no;

  // Disable zone transfer by default
  allow-transfer { none; };
};


```
DNS server is authoritative server only. Recursive or Forwarder roles are disabled.
- Disable recursive queries: `recursion no` option.
- It does not contain `forwarders` section.
- Allow queries from any subnet: `allow-query { any; }`
- Disable zone transfer by default `allow-transfer { none; }`
- DNS configured to listen only on IPv4 IP addresses `listen-on { any; }`.


#### Adding local zones

*DNS zones* designate a specific scope for managing and defining DNS records. 
In this file it must be specified the DNS zones managed by DNS server
Zones files are define in dedicated files `/etc/bind.db.x`

Two types of zones need to be created:
- Direct Zone: Used for forward dns lookup (DNS name -> IP)
- Reverse zone: Used for reververse dns lookup (IP -> DNS name)


Edit config file: `/etc/bind/named.conf.local`
```
//
// Do any local configuration here
//

// Consider adding the 1918 zones here, if they are not used in your
// organization
//include "/etc/bind/zones.rfc1918";

// forward zone name
zone "homelab.ricsanfre.com" {
    type primary;
    file "/var/lib/bind/db.homelab.ricsanfre.com";
    
};

// reverse zone name
zone "0.10.in-addr.arpa" {
    type primary;
    file "/var/lib/bind/zones/db.10.0";  # 10.0.0.0/16 subnet
};
```
#### Creating the Forward Zone File
The forward zone file is where you define DNS records for forward DNS lookups.

- Initial file can be copied from `/etc/bind/db.local`
- Create the file: `/var/lib/bind/db.<domain>`: (i.e: `/var/lib/bind.db.homelab.ricsanfre.com`)

```
;
; BIND data file for local loopback interface
;
$TTL	604800
@	IN	SOA	ns.homelab.ricsanfre.com. admin.homelab.ricsanfre.com. (
			      2		; Serial
			 604800		; Refresh
			  86400		; Retry
			2419200		; Expire
			 604800 )	; Negative Cache TTL
;
@	IN	NS	ns.
@	IN	A	127.0.0.1
@	IN	AAAA	::1

; name servers - A records
ns.homelab.ricsanfre.com.      IN      A       10.0.0.11


; 10.0.0.0/16 - A records
node1.homelab.ricsanfre.com.  IN      A      10.0.0.11
node2.homelab.ricsanfre.com.  IN      A      10.0.0.12
...

```

#### Create Reverse Zone File
Used for the reverse DNS lookup (From IP to name)

- Initial file can be copied from `/etc/bind/db.127`
- Create the file (`/var/lib/bind/db.<IP>`)

```
$TTL    604800
@       IN      SOA     ns.homelab.ricsanfre.com. admin.homelab.ricsanfre.com. (
                              1         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;

; name servers - NS records
      IN      NS      ns.homelab.ricsanfre.com.

; PTR Records
11.0    IN      PTR     ns.homelab.example.com.  ; 10.0.0.11


11.0 IN      PTR     node1.homelab.ricsanfre.com.  ; 10.0.0.11
12.0 IN      PTR     node2.homelab.ricsanfre.com.  ; 10.0.0.12
...
```  
  

#### About Zone File syntax

`Resource Records (RR)` follows the following syntax, defined in [RFC1035](https://datatracker.ietf.org/doc/html/rfc1035):

`{name} {ttl} {class} {type} {data}`

where:
- `name`: domain name
- `ttl`: TTL of the record
- `class`: class. (`IN` value)
- `type`: type of record (SOA, A, AAAA, MX, CNAME, etc.)
- `data`: data content. Structure depends on the record type.

Special symbols:

- **`@`**: 
  Used as RR `name`: it  represents the current origin. At the start of the zone file, it is the <**zone_name**>, followed by a trailing dot (.).
- **`$ORIGIN` Directive:**
  `$ORIGIN <domain>.`: **$ORIGIN** sets the domain name that is appended to any unqualified records.
  When a zone is first read, there is an implicit `$ORIGIN <zone_name>.`
- **`$TTL`Directive:**
  `$TTL <default-ttl>`: This sets the default Time-To-Live (TTL) for subsequent records
  
See further information about the Zone file structure in https://bind9.readthedocs.io/en/v9.18.30/chapter3.html#soa-rr


## DNS Resolver/Forwarder (Dnsmasq)

A DNS Resolver/Forwarder is configured as default DNS server for all nodes in the cluster. This DNS server is able to resolve DNS queries forwarding the request to upstream DNS servers.

dnsmasq installed in `gateway` is providing DHCP/DNS services and it should have the following options

- Step 1. Configure DNS service in dnsmasq

  Edit file `/etc/dnsmasq.d/dnsmasq.conf`

  ```
  # DNS server is not authoritative
  # Disable local domain and do not read addresses from /etc/host
  # Also `addresses=` configuration in dnsmasq.conf file should be avoided
  # local should be unset
  # local=
  # Do not use /etc/host
  # expand-hosts=
 
  # Specify domain for DHCP server
  domain=homelab.ricsanfre.com

  # DNS upstream nameservers
  # Default upstream servers
  server=1.1.1.1
  server=8.8.8.8
  # Conditional forward for domain homelab.ricsanfre.com
  server=/homelab.ricsanfre.com/10.0.0.11

  # Never forward plain names (without a dot or domain part)
  domain-needed

  ```

- Step 2. Restart dnsmasq service

  ```shell
  sudo systemctl restart dnsmasq
  ```


## CoreDNS

[CoreDNS](https://coredns.io/) is used within Kubernetes cluster to discover all Services

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

ExternalDNS allows you to control DNS records dynamically via Kubernetes resources in a DNS provider-agnostic way

### How does it work?

ExternalDNS makes Kubernetes resources discoverable via public DNS servers. Like [[CoreDNS]], it retrieves a list of resources (Services, Ingresses, etc.) from the [Kubernetes API](https://kubernetes.io/docs/api/) to determine a desired list of DNS records. Unlike CoreDNS, however, it’s not a DNS server itself, but merely configures other DNS providers.

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

