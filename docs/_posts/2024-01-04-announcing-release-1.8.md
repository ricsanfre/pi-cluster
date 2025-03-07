---
layout: post
title:  Kubernetes Pi Cluster relase v1.8
date:   2024-01-04
author: ricsanfre
description: PiCluster News - announcing release v1.8
---


Today I am pleased to announce the eighth release of Kubernetes Pi Cluster project (v1.8). 

Main features/enhancements of this release are:


## K3S High Availability configuration

Pi-Cluster K3S update to use a high availability deployment using 3 master nodes.

See reference document: [K3s High availability embedded etcd datastore deployment](https://docs.k3s.io/architecture#high-availability-k3s).
Three or more server nodes can be configured to serve the Kubernetes API and run other control plane services An embedded etcd datastore (as opposed to the embedded SQLite datastore used in single-server setups).
A load balancer is needed for providing High availability to Kubernetes API. In our case, a network load balancer, HAProxy , is deployed.

Implementation details:

- 3 master nodes (`node1`, `node2`, `node3`)
- HAproxy load balancer installed in `gateway` node
- Embedded etcd data store

![K3S Architecture](/assets/img/k3s-HA-configuration.png)

Ansible's automation code has been update to be able to deploy HAProxy and install K3s in HA.

See ["K3S Installation: HA"](/docs/k3s-installation/#high-availability-k3s)

## Ingress Controller migration: Traefik to NGINX

Migrate Ingress Controller, from Traefik to NGINX.

Main reasons for this migration:

- Use a more mature ingress controller with a broader installation base, so you could find easily how to configure it in almost any use case. As an example, I found some difficulties integrating Traefik with other components like Oauth2-proxy.
- More portable configuration in case of future migration to another Ingress Controller. Use of standard Kuberentes resources, avoiding the use of Traefik's custom resoures (Middleware, IngressRoute, etc.), that are required whenever you need to implement a more complex configuration. 


All packaged applications are updated to use NGINX ingress controller instead of Traefik.

See ["Ingress Controller (NGINX)"](/docs/nginx/).

## Single Sign-on

Deploy Single sign-on solution based on OAuth2.0/OpenId Connect standard, using [Keycloak](https://www.keycloak.org/)
Keycloak is an opensource Identity Access Management solution, providing centralized authentication and authorization services based on standard protocols: OpenID Connect, OAuth 2.0, and SAML.

Keycloak is also a IdP (Identity Provider), a service able to authenticate the users.
Keycloak can authenticate users defined locally or users defined on external LDAP/Active Directory services.
It also can delegate the authentication two other IdPs, i.e.: Google, Github,  using OpenId Connect/SAML protocols

For Pi cluster, Keycloak will act as standalone IAM/IdP, not integrated with any external LDAP/ActiveDirectory/IdP to authenticate users accessing to different GUIs.

For those applications not providing any authentication capability (i.e. Longhorn, Prometheus, Linkerd-viz), current Ingress-controlled authentication based on HTTP basic auth is migrated to
External Authentication, delegating authentication to a Oauth2 application, [OAuth2.0-Proxy](https://oauth2-proxy.github.io/oauth2-proxy/).

![picluster-sso](/assets/img/picluster-sso.png)

Grafana SSO capability is configured to use Keycloak as authentication provider using OAuth2.0 protocol.

See ["SSO with KeyCloak and Oauth2-Proxy"](/docs/sso/).

## New Kafka service

Adding Kafka as event streaming platform to enable data-driven microservices architecture.

Deploy Kafka Schema Registry, a component in the Apache Kafka ecosystem, providing a centralized schema management service for Kafka producers and consumers.
It allows producers to register schemas for the data they produce, and consumers to retrieve and use these schemas for data validation and deserialization. The Schema Registry helps ensure that data exchanged through Kafka is compliant with a predefined schema, enabling data consistency, compatibility, and evolution across different systems and applications.

Implementation details:

- Use of [Strimzi Operator](https://strimzi.io/) to streamline the deployment of Kafka cluster
- Integrate Kafka Schema Registry, based on [Confluent Schema Registry](https://github.com/confluentinc/schema-registry)
- Use of Kafka GUI, [Kafdrop](https://github.com/obsidiandynamics/kafdrop)

See ["Kafka"](/docs/kafka/).

## Release v1.8.0 Notes

K3S HA deployment and SSO support.

### Release Scope:

  - K3S HA deployment.
    - 3 masters with embedded etcd database using HA proxy as Kubernetes API load balancer.
    - Ansible code update for supporting K3s single-node and HA deployments.

  - Single sign-on (SSO) solution
    - Identity Access Management solution based on Keycloak
    - OAuth2.0 Proxy deployment for securing applications not using any authentication mechanism.
    - Ingress NGINX integration with OAuth2-Proxy
    - Grafana SSO configuration. Integration with Keycloak.

  - Ingress Controller migration.
    - Ingress NGINX deployment. Traefik ingress controller deprecation.
    - ArgoCD packaged applications update to use standard Ingress resources implemented by NGINX.

  - Kafka service
    - Use of Strimzi Operator to streamline the deployment of Kafka cluster
    - Integrate Kafka Schema Registry, based on Confluent Schema Registry
    - Use of Kafka GUI, Kafdrop

