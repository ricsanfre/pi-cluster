---
title: SSL Certificates (Cert-Manager)
permalink: /docs/certmanager/
description: How to deploy a centralized SSL certification management solution based on Cert-manager in our Raspberry Pi Kuberentes cluster.
last_modified_at: "08-03-2022"
---

In the Kubernetes cluster, [Cert-Manager](https://cert-manager.io/docs/) can be used to automate the certificate management tasks (issue certificate request, renewals, etc.). Cert-manager adds certificates and certificate issuers as resource types in Kubernetes clusters, and simplifies the process of obtaining, renewing and using those certificates.

It can issue certificates from a variety of supported sources, including support for auto-signed certificates or use [Let's Encrypt](https://letsencrypt.org/) service to obtain validated SSL certificates. It will ensure certificates are valid and up to date, and attempt to renew certificates at a configured time before expiry. It also keep up to date the associated Kuberentes Secrets storing key pairs used by Ingress resources when securing the incoming communications.

![picluster-certmanager](/assets/img/cert-manager.png)

## Cert-Manager certificates issuers

In cert-manager different kind of certificate issuer can be configured to generate signed SSL certificates

### Self-signed Issuer

The SelfSigned issuer doesn’t represent a certificate authority as such, but instead denotes that certificates will “sign themselves” using a given private key. In other words, the private key of the certificate will be used to sign the certificate itself.

This Issuer type is useful for bootstrapping a root certificate (CA) for a custom PKI (Public Key Infrastructure).

We will use this Issuer for bootstrapping our custom CA.

### CA Issuer

The CA issuer represents a Certificate Authority whereby its certificate and private key are stored inside the cluster as a Kubernetes Secret, and will be used to sign incoming certificate requests. This internal CA certificate can then be used to trust resulting signed certificates.

This issuer type is typically used in a private Public Key Infrastructure (PKI) setup to secure your infrastructure components to establish mTLS or otherwise provide a means to issue certificates where you also own the private key. Signed certificates with this custom CA will not be trusted by clients, such a web browser, by default.

### ACME issuers (Lets Encrypt)

The ACME Issuer type represents a single account registered with the Automated Certificate Management Environment (ACME) Certificate Authority server. See section [Let's Encrypt certificates](#lets-encrypt-certificates). 


{{site.data.alerts.important}}

CertManager has been configured to have in the cluster a private PKI (Public Key Infrastructure) using a self-signed CA to issue auto-signed certificates.

CertManager integration with Let's Encrypt has not been configured since my DNS provider does not suppport yet the API for automating DNS challenges. See open issue [#16](https://github.com/ricsanfre/pi-cluster/issues/16).

{{site.data.alerts.end}}


## Cert Manager Usage

Cert-manager add a set of Kubernetes custom resource (CRD):

- `Issuer` and `ClusterIssuer`: resources that represent certificate authorities (CA) able to genertate signed certificates in response to certificate signed request (CSR). `Issuer` is a namespaced resource, able to issue certificates only for the namespace where the issuer is located. `ClusterIssuer` is able to issue certificates across all namespaces.

- `Certificate`, resources that represent a human readable definition of a certificate request that need to be generated and keep up to date by an issuer.

In order to generate new SSL certificates a `Certificate` resource can be created. 

Once the Certificate resource is created, Cert-manager signed the certificate issued by the specified issuer and stored it in a `kubernetes.io/tls Secret` resource, which is the one used to secure Ingress resource. See kuberentes [Ingress TLS documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls)

```yml
apiVersion: v1
kind: Secret
metadata:
  name: testsecret-tls
  namespace: default
data:
  tls.crt: base64 encoded cert
  tls.key: base64 encoded key
type: kubernetes.io/tls
```

See further details in the [cert-manager documentation](https://cert-manager.io/docs/usage/certificate/)


### Securing Ingress resources

`Ingress` resources can be configured using annotations, so cert-manager can automatically generate the needed self-signed certificates to secure the incoming communications using HTTPS/TLS

As stated in the [documentation](https://cert-manager.io/docs/usage/ingress/), cert-manager can be used to automatically request TLS signed certificates to secure any `Ingress` resources. By means of annotations cert-manager can generate automatically the needed certificates and store them in corresponding secrets used by Ingress resource

Ingress annotation `cert-manager.io/cluster-issuer` indicates the `ClusterIssuer` to be used.

Ingress rule example:

```yml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    # add an annotation indicating the issuer to use.
    cert-manager.io/cluster-issuer: nameOfClusterIssuer
  name: myIngress
  namespace: myIngress
spec:
  rules:
  - host: example.com
    http:
      paths:
      - pathType: Prefix
        path: /
        backend:
          service:
            name: myservice
            port:
              number: 80
  tls: # < placing a host in the TLS config will determine what ends up in the cert's subjectAltNames
  - hosts:
    - example.com
    secretName: myingress-cert # < cert-manager will store the created certificate in this secret.
```


## Cert Manager Installation

Installation using `Helm` (Release 3):

- Step 1: Add the JetStack Helm repository:

    ```shell
    helm repo add jetstack https://charts.jetstack.io
    ```
- Step2: Fetch the latest charts from the repository:

    ```shell
    helm repo update
    ```
- Step 3: Create namespace

    ```shell
    kubectl create namespace certmanager-system
    ```
- Step 3: Install Cert-Manager

    ```shell
    helm install cert-manager jetstack/cert-manager --namespace certmanager-system --set installCRDs=true
    ```
- Step 4: Confirm that the deployment succeeded, run:

    ```shell
    kubectl -n certmanager-system get pod
    ```

## Cert-Manager Configuration

A PKI (Public Key Infrastructure) with a custom CA will be created in the cluster and all certificates will be auto-signed by this CA. For doing so, A CA `ClusterIssuer` resource need to be created.

Root CA certificate is needed for generated this CA Issuer. A selfsigned `ClusterIssuer` resource will be used to generate that root CA certificate (self-signed root CA).

- Step 1: Create selfsigned `ClusterIssuer`

  First step is to create the self-signed issuer for being able to selfsign a custom root certificate of the PKI (CA certificate).

  In order to obtain certificates from cert-manager, we need to create an issuer to act as a certificate authority. We have the option of creating an `Issuer` which is a namespaced resource, or a `ClusterIssuer` which is a global resource. We’ll create a self-signed `ClusterIssuer` using the following definition:

  ```yml
  apiVersion: cert-manager.io/v1
  kind: ClusterIssuer
  metadata:
    name: self-signed-issuer
  spec:
    selfSigned: {}
  ```

- Step 2: Bootstrapping CA Issuers

  Bootstrap a custom root certificate for a private PKI (custom CA) and create the corresponding cert-manager CA issuer

  ```yml
  ---
  apiVersion: cert-manager.io/v1
  kind: Certificate
  metadata:
    name: my-selfsigned-ca
    namespace: sandbox
  spec:
    isCA: true
    commonName: my-selfsigned-ca
    secretName: root-secret
    privateKey:
      algorithm: ECDSA
      size: 256
    issuerRef:
      name: selfsigned-issuer
      kind: ClusterIssuer
      group: cert-manager.io
  ---
  apiVersion: cert-manager.io/v1
  kind: ClusterIssuer
  metadata:
    name: my-ca-issuer
    namespace: sandbox
  spec:
    ca:
      secretName: root-secret
  ```

{{site.data.alerts.important}}

Algorithm used for creating private keys is ECDSA P-256. The use of this algorithm is required by the service mesh implementation I have selected for the cluster, Linkerd. RootCa and Linkerd identity issuer certificate must used ECDSA P-256 algorithm.

{{site.data.alerts.end}}



## Lets Encrypt Certificates

Lets Encrypt provide publicly validated TLS certificates for free. Not need to generate auto-signed SSL Certificates for the websites that are not automatic validated by HTTP browsers.

The process is the following, we issue a request for a certificate to Let's Encrypt for a domain name that we own. Let's Encrypt verifies that we own that domain by using an ACME DNS or HTTP validation mechanism. If the verification is successful, Let's Encrypt provides us with certificates that cert-manager installs in our website (or other TLS encrypted endpoint). These certificates are good for 90 days before the process needs to be repeated. Cert-manager, however, will automatically keep the certificates up-to-date for us.

For details see cert-manager [ACME issuer type documentation](https://cert-manager.io/docs/configuration/acme/)


### Let's Encrypt DNS validation method

DNS validation method requires to expose a "challenge DNS" record within the DNS domain associated to the SSL certificate.
This method do not require to expose to the Public Internet the web services hosted within my K3S cluster and so it would be the preferred method to use Let's Encrypt.

1. Cert-manager issues a certifate request to Let's Encrypt
2. Let's Encript request an ownership verification challenge in response. The challenge will be to put a DNS TXT record with specific content that proves that we have the control of the DNS domain. The theory is that if we can put that TXT record and Let's Encrypt can retrieve it remotely, then we must really be the owners of the domain
3. Cert-manager temporary creates the requested TXT record in the DNS. If Let's Encrypt can read the challenge and it is correct, it will issue the certificates back to cert-manager.
4. Cert-manager will then store the certificates as secrets, and our website (or whatever) will use those certificates for securing our traffic with TLS.

Cert-manager by default support several DNS providers to automatically configure the requested DNS record challenge. For supporting additional DNS providers webhooks can be developed. See supported list and further documentation [here](https://cert-manager.io/docs/configuration/acme/dns01/).

IONOS, my DNS server provider, is not in the list of supported ones. 

Since Dec 2020, IONOS launched an API for remotelly configure DNS, and so the integration could be possible as it is detailed in this [post](https://dev.to/devlix-blog/automate-let-s-encrypt-automate-let-s-encrypt-wildcard-certificate-creation-with-ionos-dns-rest-api-o23). This new API can be used as well for developing a Certbot plugin ([Cerbot](https://certbot.eff.org/) is an opensource software to automate the interaction with Let's Encrypt). See implementation in this [git repository](https://github.com/helgeerbe/certbot-dns-ionos).

Unfortunally IONOS API is part of a beta program that it is not available yet in my location (Spain).

### Lets Encrypt HTTP validation method

HTTP validation method requires to actually expose a "challenge URL" in the Public Internet using the DNS domain associated to the SSL certificate.

HTTP validation method is as follows: 
1. Cert-manager issues a certificate request to Let's Encrypt. 
2. Let's Encrypt requests an ownership verification challenge in response. 
The challenge will be to put an HTTP resource at a specific URL under the domain name that the certificate is being requested for. The theory is that if we can put that resource at that URL and Let's Encrypt can retrieve it remotely, then we must really be the owners of the domain. Otherwise, either we could not have placed the resource in the correct place, or we could not have manipulated DNS to allow Let's Encrypt to get to it. 
3. Cert-manager puts the resource in the right place and automatically creates a temporary Ingress record that will route traffic to the correct place. If Let's Encrypt can read the challenge and it is correct, it will issue the certificates back to cert-manager.
4. Cert-manager will then store the certificates as secrets, and our website (or whatever) will use those certificates for securing our traffic with TLS.

For this procedure to work it is needed to enable and route HTTP traffic from the Internet to our Cluster Load Balancer Ingress node (Traefik).

- Configure Dynamic DNS

  To keep up to date the DNS records mapped to my public IP address (dynamic IP address)

- Configure Home Router

  To forward HTTP/HTTPS traffic to the cluster (forward to `gateway`)

- Configure Pi Cluster firewall (`gateway`)

#### Configure Dynamic DNS

Lets Encrypt validation process includes to make a resolution of the domain included in the certificate requests.

In my home network only a public dysnamic IP is available from my ISP. My DNS provider, 1&1 IONOS supports DynDNS with an open protocol [Domain Connect](https://www.domainconnect.org/).
To configure DynDNS IONOS provide the following [instructions](https://www.ionos.com/help/domains/configuring-your-ip-address/connecting-a-domain-to-a-network-with-a-changing-ip-using-dynamic-dns-linux/).

- Step 1: Install python package

  ```shell
  pip3 install domain-connect-dyndns
  ```

- Step 2: Configure domain to be dynamically updated

  ```shell
  domain-connect-dyndns setup --domain picluster.ricsanfre.com
  ```

- Step 3: Update it

  ```shell
  domain-connect-dyndns update --all
  ```

#### Configure Home Router

Enable port forwarding for TCP ports 80/443 to `gateway` node.

| WAN Port | LAN IP | LAN Port |
|----------|--------|----------|
| 80 | `gateway` | 8080 |
| 443 | `gateway`| 4430 |
{: .table }

#### Configure Pi cluster Gateway

Configure NFtables for forwarding incoming traffic at 8080 and 4430 ports.

