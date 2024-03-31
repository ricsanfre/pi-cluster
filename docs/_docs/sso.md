---
title: SSO with KeyCloak and Oauth2-Proxy
permalink: /docs/sso/
description: How to configure Single-Sign-On (SSO) in our Pi Kubernetes cluster.
last_modified_at: "31-03-2024"
---

Centralized authentication and Single-Sign On can be implemented using [Keycloak](https://www.keycloak.org/).
Keycloak is an opensource Identity Access Management solution, providing centralized authentication and authorization 
services based on standard protocols and provides support for OpenID Connect, OAuth 2.0, and SAML.

![keycloak-sso](/assets/img/keycloak-sso.png)


Some of the GUIs of the Pi Cluster, Grafana or Kibana, SSO can be configured, so authentication can be done
using Keycloak instead of local accounts.

{{site.data.alerts.note}}

Elasticsearch/Kibana SSO integration using OpenID Connect is not available in community edition.
So, SSO won't be configured for this component.
Grafana SSO capability is enabled configuring OAuth2.0/OpenID Connect authentication.
Follow instructions in [Documentation: Monitoring (Prometheus)](/docs/prometheus/) on how to integrate Grafana with Keycloak.

{{site.data.alerts.end}}

For those applications not providing any authentication capability (i.e. Longhorn, Prometheus, Linkerd-viz), Ingress controller-based External Authentication can be configured.
Ingress NGINX supports OAuth2-based external authentication mechanism using [Oauth2-Proxy](https://oauth2-proxy.github.io/oauth2-proxy/).
See [Ingress NGINX external Oauth authentication document](https://kubernetes.github.io/ingress-nginx/examples/auth/oauth-external-auth/)
Oauth2-proxy can be integrated with OpenId-Connect IAM, such us Keycloak.

![picluster-sso](/assets/img/picluster-sso.png)

## Keycloak Installation

For installing Keycloak Bitnami's helm chart will be used.
This helm chart bootstraps a Keycloak deployment on Kubernetes using as backend a PostgreSQL database

- Step 1: Add Bitnami Helm repository:

  ```shell
  helm repo add bitnami https://charts.bitnami.com/bitnami
  ```
- Step 2: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```
- Step 3: Create namespace

  ```shell
  kubectl create namespace keycloak
  ```

- Step 4: Create file `keycloak-values.yml`

  ```yaml
  global:
    storageClass: longhorn

  # Run in production mode behind NGINX proxy terminating TLS sessions
  # ref: https://www.keycloak.org/server/reverseproxy
  # edge proxy mode: Enables communication through HTTP between the proxy and Keycloak.
  # This mode is suitable for deployments with a highly secure internal network where the reverse proxy keeps a secure connection (HTTP over TLS) with clients while communicating with Keycloak using HTTP.
  production: true
  proxy: edge
  # Admin user
  auth:
    adminUser: admin
  # postgresSQL
  postgresql:
    enabled: true
    auth:
      username: keycloak
      database: keycloak
  # Ingress config
  ingress:
    enabled: true
    ingressClassName: "nginx"
    pathType: Prefix
    annotations:
      cert-manager.io/cluster-issuer: ca-issuer
      # Increasing proxy buffer size to avoid
      # https://stackoverflow.com/questions/57503590/upstream-sent-too-big-header-while-reading-response-header-from-upstream-in-keyc
      nginx.ingress.kubernetes.io/proxy-buffers-number: "4"
      nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
    hostname: sso.picluster.ricsanfre.com
    tls: true
  ```
  
  With this configuration:
  - Keycloak is deployed in 'production proxy-edge': running behind NGINX proxy terminating TLS connections.
  - PostgreSQL is deployed in standalone mode.
  - Ingress resource is configured

  {{site.data.alerts.note}}
  With this configuration all passwords (Keycloak's admin password and postgreSQL passwords are generated randomly. 
  If helm chart is upgraded, it might cause issues generating a new passwords if the existing ones are not provided when executing helm upgrade command.
  See details in [bitnami's keycloak helm chart documentation: How to manage passwords](https://github.com/bitnami/charts/tree/main/bitnami/keycloak#manage-secrets-and-passwords)
  {{site.data.alerts.end}}
  
- Step 5: Install Keycloak in `keycloak` namespace
  ```shell
  helm install keycloak bitnami/keycloak -f keycloak-values.yml --namespace keycloak
  ```
  
- Step 6: Check status of Keycloak pods
  ```shell
  kubectl get pods -n keycloak
  ```

- Step 7: Get keycloak `admin` user password

  ```shell
  kubectl get secret keycloak -o jsonpath='{.data.admin-password}' -n keycloak | base64 -d && echo
  ```
  
- Step 8: connect to keycloak admin console
  https://sso.picluster.ricsanfre.com

  Log in using 'admin' user and password obtained in step 7.

### Alternative installation using external secret (GitOps)

Keycloak admin password and postgreSQL passwords can be provided during helm installation in values.yaml file. 
Alternatively, it can be provided in an external secret.

- Step 1: Create secret containing admin password and posgresql passwords:

  ```yaml
  apiVersion: v1
  kind: Secret
  metadata:
      name: keycloak-secret
      namespace: keycloak
  type: kubernetes.io/basic-auth
  data:
      admin-password: <`echo -n 'supersecret1' | base64`>
      postgresql-admin-password: <`echo -n 'supersecret2' | base64`>
      password: <`echo -n 'supersecret3' | base64`>
  ```

- Step 2: Add externalSecret to keycloak-values.yaml

  ```yaml
  # Admin user
  auth:
      existingSecret: keycloak-secret
      adminUser: admin
  
  # postgresSQL
  postgresql:
    enabled: true
    auth:
      username: keycloak
      database: keycloak
      existingSecret: keycloak-secret
      secretKeys:
        adminPasswordKey: postgresql-admin-password
        userPasswordKey: password
    architecture: standalone
  ```

## Keycloak Configuration

### Pi Cluster realm configuration

- Step 1: Login as admin to Keycloak console

  Open URL: https://sso.picluster.ricsanfre.com

- Step 9: Create a new realm 'picluster'
  
  Follow procedure in Keycloak documentation:[Keycloak: Creating a Realm](https://www.keycloak.org/docs/latest/server_admin/#proc-creating-a-realm_server_administration_guide)


### Configure Oauth2-Proxy Client

OAuth2-Proxy client application need to be configured within 'picluster' realm.

Procedure in Keycloak documentation: [Keycloak: Creating an OpenID Connect client](https://www.keycloak.org/docs/latest/server_admin/#proc-creating-oidc-client_server_administration_guide)

Follow procedure in [Oauth2-Proxy: Keycloak OIDC Auth Provider Configuration](https://oauth2-proxy.github.io/oauth2-proxy/configuration/oauth_provider/#keycloak-oidc-auth-provider) to provide the proper configuration.

- Step 1: Create a new OIDC client in 'picluster' Keycloak realm by navigating to:
  Clients -> Create client
  
  ![oauth2-proxy-client-1](/assets/img/oauth2-proxy-client-1.png)
  
  - Provide the following basic configuration:
    - Client Type: 'OpenID Connect'
    - Client ID: 'oauth2-proxy'
  - Click Next.
  
  ![oauth2-proxy-client-2](/assets/img/oauth2-proxy-client-2.png)
  
  - Provide the following 'Capability config'
    - Client authentication: 'On'
    - Authentication flow
      - Standard flow 'selected'
      - Direct access grants 'deselect'
  - Click Next
  
  ![oauth2-proxy-client-3](/assets/img/oauth2-proxy-client-3.png)
  
  - Provide the following 'Logging settings'
    - Valid redirect URIs: https://ouath2-proxy.picluster.ricsanfre.com/oauth2/callback
  - Save the configuration.

- Step 2: Locate oauth2-proxy client credentials
  
  Under the Credentials tab you will now be able to locate oauth2-proxy client's secret.
  
  ![oauth2-proxy-client-4](/assets/img/oauth2-proxy-client-4.png)
  
- Step 3: Configure a dedicated audience mapper for the client

  - Navigate to Clients -> oauth2-proxy client -> Client scopes.
    
    ![oauth2-proxy-client-5](/assets/img/oauth2-proxy-client-5.png)
    
  - Access the dedicated mappers pane by clicking 'oauth2-proxy-dedicated', located under Assigned client scope.
  (It should have a description of "Dedicated scope and mappers for this client")
  - Click on 'Configure a new mapper' and select 'Audience'
  
    ![oauth2-proxy-client-6](/assets/img/oauth2-proxy-client-6.png)
  
    ![oauth2-proxy-client-7](/assets/img/oauth2-proxy-client-7.png)
  
    ![oauth2-proxy-client-8](/assets/img/oauth2-proxy-client-8.png)
  
  - Provide following data:
    - Name 'aud-mapper-oauth2-proxy'
    - Included Client Audience select oauth2-proxy client's id from the dropdown.
    - Add to ID token 'On'
    - Add to access token 'On'
    OAuth2 proxy can be set up to pass both the access and ID JWT tokens to your upstream services. 
  - Save the configuration.

### Automatic import of Realm configuration

Realm configuration can be exported or imported to/from JSON files.

Once realm and clients are configured manually configuration can be exported to JSON file.
See [Keycloak export import configuration](https://www.keycloak.org/server/importExport).

Realm configuration can be imported automatically from json file when deploying helm chart.
See [Importing realm on start-up](https://www.keycloak.org/server/importExport#_importing_a_realm_during_startup)

New ConfigMap, containing the JSON files to be imported need to be mounted by keycloak PODs as
`/opt/bitnami/keycloak/data/import`. `--import-realm` also need to be provided as extra arguments when starting the PODs.

- Step 1: Create realm config map containing realm json files to be imported

  ```yaml
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: keycloak-realm-configmap
    namespace: keycloak
  data:
    picluster-realm.json: |  
      # JSON file
  ```

- Step 3: Apply configMap
  
  ```shell
  kubectl apply -f keycloak-realm-configmap.yaml
  ```
- Step 2: Add to keycloak-values.yaml the following configuration and install helm char

  ```yml
  # Importing realm on start-up
  # https://www.keycloak.org/server/importExport#_importing_a_realm_during_startup
  extraStartupArgs: "--import-realm"
  extraVolumes:
    - name: realm-config
      configMap:
        name: keycloak-realm-configmap
  extraVolumeMounts:
    - mountPath: /opt/bitnami/keycloak/data/import
      name: realm-config
  ```


## Proxy Oauth 2.0 Installation

- Step 1: Add Helm repository:

  ```shell
  helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests
  ```
- Step 2: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```
- Step 3: Create namespace

  ```shell
  kubectl create namespace oauth2-proxy
  ```

- Step 4: Create file `oauth2-proxy-values.yml`

  ```yaml
  config:
    # Add config annotations
    annotations: {}
    # OAuth client ID
    # Follow instructions to configure Keycloak client
    # https://oauth2-proxy.github.io/oauth2-proxy/docs/configuration/oauth_provider#keycloak-oidc-auth-provider

    # Oauth2 client configuration. From Keycloak configuration
    clientID: "oauth2-proxy"
    clientSecret: "supersecreto"
    
    # Cookie secret
    # Create a new secret with the following command
    # openssl rand -base64 32 | head -c 32 | base64
    cookieSecret: "bG5pRDBvL0VaWis3dksrZ05vYnJLclRFb2VNcVZJYkg="
    # The name of the cookie that oauth2-proxy will create
    # If left empty, it will default to the release name
    cookieName: "oauth2-proxy"

    # Config file
    configFile: |-
      # Provider config
      provider="keycloak-oidc"
      provider_display_name="Keycloak"
      redirect_url="https://oauth2-proxy.picluster.ricsanfre.com/oauth2/callback"
      oidc_issuer_url="https://sso.picluster.ricsanfre.com/realms/picluster"
      code_challenge_method="S256"
      ssl_insecure_skip_verify=true
      # Upstream config
      http_address="0.0.0.0:4180"
      upstreams="file:///dev/null"
      email_domains=["*"]
      cookie_domains=["picluster.ricsanfre.com"]
      cookie_secure=false
      scope="openid"
      whitelist_domains=[".picluster.ricsanfre.com"]
      insecure_oidc_allow_unverified_email="true"

  sessionStorage:
    # Can be one of the supported session storage cookie|redis
    type: redis
  # Enabling redis backend installation
  redis:
    enabled: true
    # standalone redis. No cluster
    architecture: standalone

  ingress:
    enabled: true
    className: "nginx"
    pathType: Prefix
    path: /oauth2
    annotations:
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      # Possible Cluster-Issuer values:
      #   * 'letsencrypt-issuer' (valid TLS certificate using IONOS API)
      #   * 'ca-issuer' (CA-signed certificate, not valid)
      cert-manager.io/cluster-issuer: letsencrypt-issuer
      cert-manager.io/common-name: oauth2-proxy.picluster.ricsanfre.com
      nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
    hosts:
      - oauth2-proxy.picluster.ricsanfre.com
    tls:
      - hosts:
          - oauth2-proxy.picluster.ricsanfre.com
        secretName: oauth2-proxy-tls  
  ```

  - Step 5: Install helm chart
    
    ```shell
    helm install oauth2-proxy oauth2-proxy/oauth2-proxy -f oauth2-proxy-values.yml --namespace oauth2-proxy
    ```

  - Step 6: Check status oauth2-proxy PODs 

    ```shell
    kubectl --namespace=oauth2-proxy get pods -l "app=oauth2-proxy"
    ```

### Alternative installation using external secret (GitOps)

OAuth credentials (clientID, client secret), cookie secret and redis password can be provided from external secret

{{site.data.alerts.note}}

Redis backend is installed using redis bitnami helm sub-chart. This helm chart creates a random credential for redis backend.
When using ArgoCD, helm native commands, like `random` or `lookup`, used by the helm chart for generating this random secret are not supported and so oauth2-proxy fails to save any data to redis.
See [issue bitnami@charts#18130](https://github.com/bitnami/charts/issues/18130) and [issue argocd@argocd#14944](https://github.com/argoproj/argo-cd/issues/14944)

As workaround, the issue can be solved providing the credentials in a external secrets.

{{site.data.alerts.end}}

- Step 1: Create secret containing oauth2-proxy credentials:

  ```yaml
  apiVersion: v1
  kind: Secret
  metadata:
      name: oauth2-proxy-secret
      namespace: oauth2-proxy
  type: kubernetes.io/basic-auth
  data:
    client-id: <`echo -n 'oauth2-proxy' | base64`> 
    client-secret:  <`echo -n 'supersecret | base64`>
    cookie-secret: <`openssl rand -base64 32 | head -c 32 | base64`>
    redis-password: <`openssl rand -base64 32 | head -c 32 | base64`>
  ```
  
  client-secret value should be taken from Oauth2-proxy client configuration

- Step 2: Add existingSecret to oauth2-proxy-values.yaml and install helm chart

  ```yaml
  # Admin user
  auth:
    existingSecret: oauth2-proxy-secret
    # clientID: "oauth2-proxy"
    # clientSecret: "supersecreto"
    # cookieSecret: "bG5pRDBvL0VaWis3dksrZ05vYnJLclRFb2VNcVZJYkg="
  
  sessionStorage:
    type: redis
    redis:
      existingSecret: oauth2-proxy-secret
      passwordKey: redis-password
  
  redis:
    enabled: true
    # standalone redis. No cluster
    architecture: standalone
    # Get redis password from existing secret using key redis-password
    auth:
      existingSecret: oauth2-proxy-secret
      existingSecretPasswordKey: redis-password
  ```
  
## Configure Ingress external authentication

Following annotations need to be added to any Ingress resource to use Oauth2-proxy authentication

```yaml
nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.picluster.ricsanfre.com/oauth2/start?rd=https://$host$request_uri
nginx.ingress.kubernetes.io/auth-url: http://oauth2-proxy.oauth2-proxy.svc.cluster.local/oauth2/auth
nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"
nginx.ingress.kubernetes.io/auth-response-headers: Authorization
```
