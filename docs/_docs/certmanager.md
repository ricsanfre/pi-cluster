---
title: SSL Certificates (Cert-Manager)
permalink: /docs/certmanager/
description: How to deploy a centralized SSL certification management solution based on Cert-manager in our Raspberry Pi Kuberentes cluster.
last_modified_at: "02-10-2022"
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

CertManager is configured to deploy in the cluster a private PKI (Public Key Infrastructure) using a self-signed CA to issue auto-signed certificates.

Such private PKI will be used internally by Linkerd to issue certiticates to each POD to implement mTLS communictions.

CertManager also is configured to deliver valid certificates, using your own DNS domain, through its integration with Let's Encrypt using ACME DNS challenges. Configuration is provided for using IONOS DNS provider, using developer API available to automate challenge resolution. Similar configuration can be implemented for other supported DNS providers.

Valid certificates signed by Letscript will be used for cluster exposed services.

{{site.data.alerts.end}}


## Cert Manager Usage

Cert-manager add a set of Kubernetes custom resource (CRD):

- `Issuer` and `ClusterIssuer`: resources that represent certificate authorities (CA) able to genertate signed certificates in response to certificate signed request (CSR). `Issuer` is a namespaced resource, able to issue certificates only for the namespace where the issuer is located. `ClusterIssuer` is able to issue certificates across all namespaces.

- `Certificate`, resources that represent a human readable definition of a certificate request that need to be generated and keep up to date by an issuer.

In order to generate new SSL certificates a `Certificate` resource can be created. 

```yml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-test-com
spec:
  dnsNames:
    - 'example.com'
  issuerRef:
    name: nameOfClusterIssuer
  secretName: example-test-com-tls
```

Once the Certificate resource is created, Cert-manager signed the certificate issued by the specified issuer and stored it in a `kubernetes.io/tls Secret` resource, which is the one used to secure Ingress resource. See kuberentes [Ingress TLS documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/#tls)

```yml
apiVersion: v1
kind: Secret
metadata:
  name: example-test-com-tls
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
    namespace: certmanager-system
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
    namespace: certmanager-system
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

Cert-manager by default support several DNS providers to automatically configure the requested DNS record challenge. For supporting additional DNS providers webhooks can be developed. See supported list and further documentation in [Certmanager documentation: "ACME DNS01" ](https://cert-manager.io/docs/configuration/acme/dns01/).

IONOS, my DNS server provider, is not supported by Certmanager (neither OOTB support nor through supported external webhooks). Even when it is not officially supported by the community, there is a github project  providing a [IONOS cert-manager webhook](https://github.com/fabmade/cert-manager-webhook-ionos).

This ionos-webhook uses the [IONOS developer API](https://developer.hosting.ionos.es/), allowing the remote configuration of the DNS using a RESTFUL API.

This IONOS developer API can be used also with Certbot. [Cerbot](https://certbot.eff.org/) is an opensource software to automate the interaction with Let's Encrypt. A Certbot plugin is needed to automate DNS challenge process using IONOS developer API. See an implementation of such Cerbot plugin in this [cerbot-dns-ionos project](https://github.com/helgeerbe/certbot-dns-ionos).

#### Creating IONOS developer API Key

To use IONOS developer API, first API key must be created.

Follow [IONOS developer API: Get Started instructions](https://developer.hosting.ionos.es/docs/getstarted) to obtain API key.

API key is composed of two parts:  Public Prefix (public key) and Secret (private key)

#### Installing Certbot IONOS

In `pimaster` node, Certbot and [certbot-dns-ionos plugin](https://github.com/helgeerbe/certbot-dns-ionos) can be installed so, Lets encrypt certificates can be issued.

Cerbot will be installed in a python virtualenv. Similar procedure to the one used to build ansible developer environment.

Execute all the following commands from $HOME directory.

- Step 1. Create Virtual Env for Ansible

  ```shell
  python3 -m venv letsencrypt
  ```

- Step 2. Activate Virtual Environment

  ```shell
  source letsencrypt/bin/activate
  ```

- Step 3. Upgrade setuptools and pip packages

  ```shell
  pip3 install --upgrade pip setuptools
  ```

- Step 4. Install certbot and certbot-ionos-plugin

  ```shell
  pip3 install certbot certbot-dns-ionos
  ```

- Step 5. Create certbot working directories

  ```shell
  mkdir -p letsencrypt/config
  mkdir -p letsencrypt/logs
  mkdir -p letsencrypt/.secrets
  chmod 700 letsencrypt/.secrets
  ```

- Step 6. Create ionos credentials file `letsencrypt/.secrets/ionos-credentials.ini`

  ```
  dns_ionos_prefix = myapikeyprefix
  dns_ionos_secret = verysecureapikeysecret
  dns_ionos_endpoint = https://api.hosting.ionos.com
  ```
  
  In this file, IONOS API key prefix and secret need to be provided

- Step 7. Change permission of `ionos-credentials.ini` file

  ```shell
  chmod 600 letsencrypt/.secrets/ionos-credentials.ini
  ```

- Step 8. Certificate can be created using the following command

  ```shell
  letsencrypt/bin/certbot certonly \
  --config-dir letsencrypt/config \
  --work-dir letsencrypt \
  --logs-dir letsencrypt/logs \
  --authenticator dns-ionos \
  --dns-ionos-credentials letsencrypt/.secrets/ionos-credentials.ini \
  --dns-ionos-propagation-seconds 900 \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --agree-tos \
  --non-interactive \
  --rsa-key-size 4096 \
  -m <your-email> \
  -d <host_dns>
  ```
  
  Signed certificate will be stored in letsencrypt/config.

  {{site.data.alerts.note}}

  Certificates managed by certbot can be listed using the commad:

  ```shell
  letsencrypt/bin/certbot certificates \
  --config-dir letsencrypt/config \
  --work-dir letsencrypt \
  --logs-dir letsencrypt/logs \
  ```

  Certificate and key path are showed. Also expiration date is showed.

  To automatic renew the certificates the following command can be executed periodically in a cron

  ```shell
  letsencrypt/bin/certbot/certbot renew
  ```

  {{site.data.alerts.end}}


#### Configuring Certmanager Letsencrypt

- Step 1: Install cert-manager-webhook-ionos chart repo:

  ```shell
  helm repo add cert-manager-webhook-ionos https://fabmade.github.io/cert-manager-webhook-ionos
  ```
- Step 2: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```
- Step 3: Create values.yml file for customizing helm chart

  ```yml
  ---
  groupName: acme.<your-domain>

  certManager:
    namespace: certmanager-system
    serviceAccountName: certmanager-cert-manager
  ```
  `groupName` is a unique identifier that need to be referenced in each Issuer's `webhook` stanza to inform cert-manager of where to send challengePayload resources in order to solve the DNS01 challenge. `acme.<yourdomain>` can be used.

  CertManager namespace and its servceAccount name need to be specified.

- Step 4: Install cert-manager-webhook-ionos

  ```shell
  helm install cert-manager-webhook-ionos cert-manager-webhook-ionos/cert-manager-webhook-ionos -n certmanager-system -f values-certmanager-ionos.yml
  ```

- Step 5: Create IONOS API secret

  ```yml
  apiVersion: v1
  stringData:
    IONOS_PUBLIC_PREFIX: <your-public-key>
    IONOS_SECRET: <your-private-key>
  kind: Secret
  metadata:
    name: ionos-secret
    namespace: certmanager-system
  type: Opaque
  ```

- Step 6: Configure a Letsencrypt Cluster Issuer

  ```yml
  ---
  apiVersion: cert-manager.io/v1
  kind: ClusterIssuer
  metadata:
    name: letsencrypt-issuer
    namespace: certmanager-system
    spec:
        acme:
          # The ACME server URL
          server: https://acme-v02.api.letsencrypt.org/directory
          # Email address used for ACME registration
          email: <your-email-address>
          # Name of a secret used to store the ACME account private key
          privateKeySecretRef:
            name: letsencrypt-ionos-prod
          # Enable the dns01 challenge provider
          solvers:
            - dns01:
                webhook:
                  groupName: acme.<your-domain>
                  solverName: ionos
                  config:
                    apiUrl: https://api.hosting.ionos.com/dns/v1
                    publicKeySecretRef:
                      key: IONOS_PUBLIC_PREFIX
                      name: ionos-secret
                    secretKeySecretRef:
                      key: IONOS_SECRET
                      name: ionos-secret
  ```

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
To configure DynDNS IONOS provider, follow these [instructions](https://www.ionos.com/help/domains/configuring-your-ip-address/connecting-a-domain-to-a-network-with-a-changing-ip-using-dynamic-dns-linux/).

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

