# SSL and HTTPS

The frontends that will be deployed on the Kubernetes cluster must be SSL encrypted and access through HTTPS must use valid public certificates.

In the Kubernetes cluster Cert-Manager can be used to automate the certificate management tasks (issue certificate request, renewals, etc.) and we can use Let's Encrypt service to obtain validated SSL certificates.

## Lets Encrypt

Lets Encrypt provide publicly validated TLS certificates for free. Not need to generate auti-signed SSL Certificates for the websites that are not automatic validated by HTTP browsers.

The process is the following, we issue a request for a certificate to Let's Encrypt for a domain name that we own. Let's Encrypt verifies that we own that domain by using an ACME DNS or HTTP validation mechanism. If the verification is successful, Let's Encrypt provides us with certificates that cert-manager installs in our website (or other TLS encrypted endpoint). These certificates are good for 90 days before the process needs to be repeated. Cert-manager, however, will automatically keep the certificates up-to-date for us.

### Let`s Encrypt HTTP validation method

HTTP validation method is as follows: 
1) Cert-manager issues a certificate request to Let's Encrypt. 
2) Let's Encrypt requests an ownership verification challenge in response. 
The challenge will be to put an HTTP resource at a specific URL under the domain name that the certificate is being requested for. The theory is that if we can put that resource at that URL and Let's Encrypt can retrieve it remotely, then we must really be the owners of the domain. Otherwise, either we could not have placed the resource in the correct place, or we could not have manipulated DNS to allow Let's Encrypt to get to it. 
3) Cert-manager puts the resource in the right place and automatically creates a temporary Ingress record that will route traffic to the correct place. If Let's Encrypt can read the challenge and it is correct, it will issue the certificates back to cert-manager.
4) Cert-manager will then store the certificates as secrets, and our website (or whatever) will use those certificates for securing our traffic with TLS.

For this procedure to work it is needed to enable and route HTTP traffic from the Internet to our Cluster Load Balancer Ingress node (Traefik).

- Configure Dynamic DNS

   To keep up to date the DNS records mapped to my public IP address (dynamic IP address)

- Configure Home Router

   To forward HTTP/HTTPS traffic to the cluster (forward to `gateway`)

- Configure Pi Cluster firewall (`gateway`)

### Configure Dynamic DNS

Lets Encrypt validation process includes to make a resolution of the domain included in the certificate requests.

In my home network only a public dysnamic IP is available from my ISP. My DNS provider, 1&1 IONOS supports DynDNS with an open protocol [Domain Connect](https://www.domainconnect.org/).
To configure DynDNS IONOS provide the following [instructions](https://www.ionos.com/help/domains/configuring-your-ip-address/connecting-a-domain-to-a-network-with-a-changing-ip-using-dynamic-dns-linux/).

- Step 1: Install python package

    pip3 install domain-connect-dyndns

- Step 2: Configure domain to be dynamically updated

    domain-connect-dyndns setup --domain picluster.ricsanfre.com

- Step 3: Update it

    domain-connect-dyndns update --all

### Configure Home Router

Enable port forwarding for TCP ports 80/443 to `gateway` node.

| WAN Port | LAN IP | LAN Port |
|----------|--------|----------|
| 80 | `gateway` | 8080 |
| 443 | `gateway`| 4430 |


### Configure Pi cluster Gateway

Configure NFtables for forwarding incoming traffic at 

# Cert Manager

[cert-manager](https://cert-manager.io/docs/) cert-manager adds certificates and certificate issuers as resource types in Kubernetes clusters, and simplifies the process of obtaining, renewing and using those certificates. 
Sites be encrypted, but they will be using valid public certificates that are automatically provisioned and automatically renewed from Let's Encrypt

It can issue certificates from a variety of supported sources, including Let’s Encrypt. It will ensure certificates are valid and up to date, and attempt to renew certificates at a configured time before expiry.

## Installation procedure using Helm

Installation using `Helm` (Release 3):

- Step 1: Add the JetStack Helm repository:
    ```
    helm repo add jetstack https://charts.jetstack.io
    ```
- Step2: Fetch the latest charts from the repository:
    ```
    helm repo update
    ```
- Step 3: Create namespace
    ```
    kubectl create namespace certmanager-system
    ```
- Step 3: Install Cert-Manager
    ```
    helm install cert-manager jetstack/cert-manager --namespace certmanager-system --version v1.5.3 --set installCRDs=true
    ```
- Step 4: Confirm that the deployment succeeded, run:
    ```
    kubectl -n longhorn-system get pod
    ```