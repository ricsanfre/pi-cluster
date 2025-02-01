---
layout: post
title:  Kubernetes Pi Cluster relase v1.10
date:   2025-01-16
author: ricsanfre
description: PiCluster News - announcing release v1.10
---


Today I am pleased to announce the tenth release of Kubernetes Pi Cluster project (v1.9).
Main features/enhancements of this release are:


## Homelab Gateway migration to OpenWRT

Replace current home lab router/gateway based on a Raspberry Pi node, gateway node, running networking services (dnsmasq, nftables, etc.) in Ubuntu OS to a OpenWrt OS based router.

[OpenWrt](https://openwrt.org/) (from open wireless router) is a highly extensible GNU/Linux distribution for embedded devices to route traffic. OpenWrt can run on various types of devices, including CPE routers, residential gateways, smartphones and SBC (like Raspeberry Pis). It is also possible to run OpenWrt on personal computers.

As an alternative to Raspberry PI, a wifi pocket-sized travel router running OpenWRT as OS can be used. In my case, Slate Plus (GL-A1300) from GL-Inet has been used for this purpose.

Networking Services running previously in `gateway` node using Ubuntu OS have been migrated to new OpenWRT based router.

![gateway-migration](/assets/img/gateway-dns-dhcp-config.png)

See details in ["Cluster Gateway (OpenWrt)"](/docs/openwrt/)


## Re-architect Homelab and Kubernetes DNS service

Reconfigure complete DNS architecture of my homelab implementing a split-horizon DNS architecture, so services can be accessed from my private network and also they can be accessed from external network.

![dns-architecture](/assets/img/pi-cluster-dns-architecture.png)

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

- [ExternalDNS](https://github.com/kubernetes-sigs/external-dns), to synchronize exposed Kubernetes Services and Ingresses with cluster authoritative DNS, Bind9. So DNS records associated to exposed services can be automatically created and services can be accessed from out-side using their DNS names.

![external-dns-architecture](/assets/img/external-dns-architecture.png)

See details in ["DNS Homelab Architecture"](/docs/dns/) and ["DNS (CoreDNS and External-DNS)"](/docs/kube-dns/)

### Dev environment

Add guidelines to install a development evironment for PiCluster meant to run on a laptop/VM running linux server.

Tools like [kind](https://kind.sigs.k8s.io/) or [K3D](https://k3d.io/) can be used for running local Kubernetes clusters using Docker container “nodes”.

For the development environment K3D is be used instead of kind. k3d is a lightweight wrapper to run k3s in docker. That way the software running in dev environment will be similar to the one running in production environment.

The development setup with K3D will be using same K3s configuration as the production environment:

- K3D cluster installed disabling flannel CNI, kube-proxy and load balancer.
- Cilium is installed as CNI which also takes care of the routing which was handled by kube-proxy. 
- Cilium L2-LB awareness is enabled, and a set of IP’s are configured for Loadbalancers services and advertised via L2 announcements. 
- Flux CD used to deploy applications. 

![picluster-dev-k3d](/assets/img/pi-cluster-dev-k3d-architecture.png)

See details in ["Kubernetes development environment"](/docs/dev/)


### MongoDB Cloud-native deployment

Add support to deploy MongoDB databases in a declarative way using a [MongoDB Community Kubernetes Operator](https://github.com/mongodb/mongodb-kubernetes-operator).

Declarative deployment of MongoDB clusters (replicasets) secured using TLS certificates and SCRAM authentication.

See details in ["Databases - MongoDB operator"](/docs/databases/#mongodb-operator)


## Release v1.10.0 Notes

Homelab/Kuberenes DNS rearchitecture, migration to OpenWRT based router/firewall, and new 3D-based dev environment and suppor MongoDB declarative deployment.

### Release Scope:

- Migrate Homelab Gateway Ubuntu OS based to OpenWRT
  - Migrate firewall rules to OpenWrt router
    - OpenWrt firewall is also using `nftables` to implemt its firewall functionallity.
  - Migrate DNS/DHCP services to OpenWrt
    - OpenWrt DNS/DCHP is also based on dnsmasq.
  - Migrate PXE boot services (TFTF server and Kick-start web servers) to other node in the cluster (node1). GL-A1300 does not have enough disk space to store boot and iso files.


- New DNS Architecure
  - Cluster domain changed to `homelab.picluster.ricsanfre.com`
  - New Homelab DNS authoritative server based on Bind9
  - Gateway DNS resolver/forwarder service reconfiguration
  - External-DNS kubernetes service deployment integrated with Bind9
  - Cert-manager reconfiguration to support LetsEncrypt certificates in split DNS horizon architecture

- New Dev Environment
  - Add documentation to install k3d development platform
  - Add Flux configuration for dev cluster environment

- Add support for creating MongoDB clusters
  - Deploy [MongoDB Community Operator](https://cloudnative-pg.io/) operator
  - Add sample mongoDB FluxCD cluster kustomized application.
  - Document how to create MondoDB cluster databases and secure using TLS certificates generated by Cert-Manager
