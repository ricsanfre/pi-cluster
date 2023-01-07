---
title: Secret Management (Vault)
permalink: /docs/vault/
description: How to deploy Hashicorp Vault as a Secret Manager for our Raspberry Pi Kubernetes Cluster.
last_modified_at: "27-12-2022"
---

[HashiCorp Vault](https://www.vaultproject.io/) is used as Secret Management solution for Raspberry PI cluster. All cluster secrets (users, passwords, api tokens, etc) will be securely encrypted and stored in Vault.

Vault will be deployed as a external service, not running as a Kuberentes service, so it can be used by GitOps solution, ArgoCD, to deploy automatically all cluster services.

Vault could be installed as Kuberentes service, deploying it using an official Helm Chart or a community operator like [Banzai Bank-Vault](https://banzaicloud.com/products/bank-vaults/), but it would make impossible to use Secrets from Vault for installing K3S cluster itself or other external services like Minio S3 Server.

[External Secrets Operator](https://external-secrets.io/) will be used to automatically generate the Kubernetes Secrets from Vault data that is needed to deploy the different services using ArgoCD.


## Vault installation


VAult installation and configuration tasks have been automated with Ansible developing a role: **ricsanfre.vault**. This role, installs Vault Server, initialize it and install a systemd service to automatically unseal it whenever vault server is restarted.

### Vault installation from binaries

Instead of installing Vault using official Ubuntu packages, installation will be done manually from binaries, so the version to be installed can be decided.

- Step 1. Create vault's UNIX user/group

  vault user is a system user, not login allowed
  ```shell
  sudo groupadd vault 
  sudo useradd vault -g vault -r -s /sbin/nologin
  ```
- Step 2. Create vault's storage directory

  ```shell
  sudo mkdir /var/lib/vault
  chown -R vault:vault /var/lib/vault
  chmod -R 750 /vault/lib/vault
  ```

- Step 3. Create vault's config directories

  ```shell
  sudo mkdir -p /etc/vault
  sudo mkdir -p /etc/vault/tls
  sudo mkdir -p /etc/vault/policy
  sudo mkidr -p /etc/vault/plugin
  chown -R vault:vault /etc/vault
  chmod -R 750 /etc/vault
  ```

- Step 4: Create vault's log directory

  ```shell
  sudo mkdir /var/log/vault
  chown -R vault:vault /var/log/vault
  chmod -R 750 /vault/log/vault
  ```
- Step 5. Download server binary (`vault`) and copy them to `/usr/local/bin`

  ```shell
   wget https://releases.hashicorp.com/vault/<version>/vault_<version>_linux_<arch>.zip
   unzip vault_<version>_linux_<arch>.zip
   chmod +x vault
   sudo mv vault /usr/local/bin/.
  ```
  where `<arch>` is amd64 or arm64, and `<version>` is vault version (for example: 1.12.2).


- Step 6. Create Vault TLS certificate

  In case you have your own domain, a valid TLS certificate signed by [Letsencrypt](https://letsencrypt.org/) can be obtained for Minio server, using [Certbot](https://certbot.eff.org/).

  See certbot installation instructions in [CertManager - Letsencrypt Certificates Section](/docs/certmanager/#installing-certbot-ionos). Those instructions indicate how to install certbot using DNS challenge with IONOS DNS provider (my DNS provider). Similar procedures can be followed for other DNS providers.

  Letsencrypt using HTTP challenge is avoided for security reasons (cluster services are not exposed to public internet).

  If generating valid TLS certificate is not possible, selfsigned certificates with a custom CA can be used instead.

  Follow this procedure for creating a self-signed certificate for Vault Server

  1. Create a self-signed CA key and self-signed certificate

     ```shell
     openssl req -x509 \
            -sha256 \
            -nodes \
            -newkey rsa:4096 \
            -subj "/CN=Ricsanfre CA" \
            -keyout rootCA.key -out rootCA.crt
     ```

    {{site.data.alerts.note}}

    The one created during Minio installation can be re-used.

    {{site.data.alerts.end}}

  2. Create a TLS certificate for Vault server signed using the custom CA
    
     ```shell
     openssl req -new -nodes -newkey rsa:4096 \
                 -keyout vault.key \
                 -out vault.csr \
                 -batch \
                 -subj "/C=ES/ST=Madrid/L=Madrid/O=Ricsanfre CA/OU=picluster/CN=vault.picluster.ricsanfre.com"

      openssl x509 -req -days 365000 -set_serial 01 \
            -extfile <(printf "subjectAltName=DNS:vault.picluster.ricsanfre.com") \
            -in vault.csr \
            -out vault.crt \
            -CA rootCA.crt \
            -CAkey rootCA.key
     ```

  Once the certificate is created, public certificate and private key need to be installed in Vault server following this procedure:


  1. Copy public certificate `vault.crt` as `/etc/vault/tls/vault.crt`

     ```shell
     sudo cp vault.crt /etc/vault/tls/public.crt
     sudo chown vault:vault /etc/vault/tls/public.crt
     ```
  2. Copy private key `vault.key` as `/etc/vault/tls/vault.key`

     ```shell
     cp vault.key /etc/vault/tls/vault.key
     sudo chown vault:vault /etc/vault/tls/vault.key
     ```
  3. Copy CA certificate `rootCA.crt` as `/etc/vault/tls/vault-ca.crt`

     {{site.data.alerts.note}}

     This step is only needed if using selfsigned certificate.

     {{site.data.alerts.end}}

     ```shell
     cp rootCA.crt /etc/vault/tls/vault-ca.crt
     sudo chown vault:vault /etc/vault/tls/vault-ca.crt
     ```

- Step 7: Create vault config file `/etc/vault/vault_main.hcl`

  ```
  cluster_addr  = "https://<node_ip>:8201"
  api_addr      = "https://<node_ip>:8200"

  plugin_directory = "/etc/vault/plugin"

  disable_mlock = true

  listener "tcp" {
    address     = "0.0.0.0:8200"
    tls_cert_file      = "/etc/vault/tl/vault.crt"
    tls_key_file       = "/etc/vault/tls/vault.key"

    tls_disable_client_certs = true

  }

  storage "raft" {
    path    = /var/lib/vault

  }
  ```

  Vault is configured, as a single node of HA cluster, with the following parameters:

  - Node's URL address to be used in internal communications between nodes of the cluster. (`cluster_addr` and `api_addr`)
  - Vault server API listening in all node's addresses at port 8200: (`listener "tcp" address=0.0.0.0:8200`)
  - TLS certifificates are stored in `/etc/vault/tls`
  - Client TLS certificates validation is disabled (`tls_disable_client_certs`)
  - Vault is configured to use integrated storage [Raft](https://developer.hashicorp.com/vault/docs/configuration/storage/raft) data dir `/var/lib/vault`
  - Disables the server from executing the mlock syscall (`disable_mlock`) recommended when using Raft storage


- Step 8. Create systemd vault service file `/etc/systemd/system/vault.service`

  ```
  [Unit]
  Description="HashiCorp Vault - A tool for managing secrets"
  Documentation=https://www.vaultproject.io/docs/
  Requires=network-online.target
  After=network-online.target
  ConditionPathExists=/etc/vault/vault_main.hcl

  [Service]
  User=vault
  Group=vault
  ProtectSystem=full
  ProtectHome=read-only
  PrivateTmp=yes
  PrivateDevices=yes
  SecureBits=keep-caps
  Capabilities=CAP_IPC_LOCK+ep
  AmbientCapabilities=CAP_SYSLOG CAP_IPC_LOCK
  CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
  NoNewPrivileges=yes
  ExecStart=/bin/sh -c 'exec {{ vault_bin_path }}/vault server -config=/etc/vault/vault_main.hcl -log-level=info'
  ExecReload=/bin/kill --signal HUP $MAINPID
  KillMode=process
  KillSignal=SIGINT
  Restart=on-failure
  RestartSec=5
  TimeoutStopSec=30
  StartLimitInterval=60
  StartLimitBurst=3
  LimitNOFILE=524288
  LimitNPROC=524288
  LimitMEMLOCK=infinity
  LimitCORE=0

  [Install]
  WantedBy=multi-user.target
  ```

  {{site.data.alerts.note}}

  This systemd configuration is the one that official vault ubuntu's package installs.

  {{site.data.alerts.end}}

  This service start vault server using vault UNIX group and executing the following startup command:

  ```shell
  /usr/local/vault server -config=/etc/vault/vault_main.hcl -log-level=info
  ```

- Step 9. Enable vault systemd service and start it

  ```shell
  sudo systemctl enable vault.service
  sudo systemctl start vault.service
  ```

- Step 10. Check vault server status

  ```shell
  export VAULT_ADDR=https://<vault_ip>:8200
  export VAULT_CACERT=/etc/vault/tls/vault-ca.crt

  vault status
  ```

  The output should be like the following

  ```shell
  Key                Value
  ---                -----
  Seal Type          shamir
  Initialized        false
  Sealed             true
  Total Shares       0
  Threshold          0
  Unseal Progress    0/0
  Unseal Nonce       n/a
  Version            1.12.2
  Build Date         2022-11-23T12:53:46Z
  Storage Type       raft
  HA Enabled         true
  ```

  It shows Vault server status as not initialized (Initialized = false) and sealed (Sealed = true).

  {{site.data.alerts.note}}

  VAULT_CACERT variable is only needed if Vault's TLS certifica is signed using custom CA. This will be used by vault client to validate Vault's certificate.

  {{site.data.alerts.end}}


### Vault initialization and useal

During initialization, Vault generates a root key, which is stored in the storage backend alongside all other Vault data. The root key itself is encrypted and requires an unseal key to decrypt it.

Unseal process, where uneal keys are provided to rebuid the root key, need to be completed every time vault server is started.

The default Vault configuration uses [Shamir's Secret Sharing](https://en.wikipedia.org/wiki/Shamir%27s_Secret_Sharing) to split the root key into a configured number of shards (referred as key shares, or unseal keys). A certain threshold of shards is required to reconstruct the root key, which is then used to decrypt the Vault's encryption key.

To initialize vault [`vault operator init`](https://developer.hashicorp.com/vault/docs/commands/operator/init) command must be used.

```shell
vault operator init -key-shares=1 -key-threshold=1 -format=json > /etc/vault/unseal.json
```
where number of key shares (`-key-shares`) and threshold (`-key-threshold`) is set to 1. Only one key is needed to unseal vault.

The vault init command output is redirected to a file (`/etc/vautl/unseal.json`) containing unseal keys values and root token needed to connect to vault.

```json
{
  "unseal_keys_b64": [
    "UEDYFGa/oVUehw5eflXt2mdoE8zJD3QVub8b++rNCm8="
  ],
  "unseal_keys_hex": [
    "5040d81466bfa1551e870e5e7e55edda676813ccc90f7415b9bf1bfbeacd0a6f"
  ],
  "unseal_shares": 1,
  "unseal_threshold": 1,
  "recovery_keys_b64": [],
  "recovery_keys_hex": [],
  "recovery_keys_shares": 0,
  "recovery_keys_threshold": 0,
  "root_token": "hvs.AJxt0CgXT9BcVe5dMNeI0Unm"
}
```

`vault status` shows Vault server initialized but sealed

```shell
vault status
Key                Value
---                -----
Seal Type          shamir
Initialized        true
Sealed             true
Total Shares       1
Threshold          1
Unseal Progress    0/1
Unseal Nonce       n/a
Version            1.12.2
Build Date         2022-11-23T12:53:46Z
Storage Type       raft
HA Enabled         true
```

To unseal vault `vault operator unseal` command need to be executed, providing unseal keys generated during initialization process.


Using the key stored in `unseal.json` file the following command can be executed:

```shell
vault operator unseal $(jq -r '.unseal_keys_b64[0]' /etc/vault/unseal.json)
```

`vault status` shows Vault server initialized and unsealed

```shell
vault status
Key                Value
---                -----
Seal Type          shamir
Initialized        true
Sealed             true
Total Shares       1
Threshold          1
Unseal Progress    0/1
Unseal Nonce       n/a
Version            1.12.2
Build Date         2022-11-23T12:53:46Z
Storage Type       raft
HA Enabled         true
```

### Vault automatic unseal

A systemd service can be created to automatically unseal vault every time it is started.


- Step 1: Create a script (`/etc/vault/vault-unseal.sh`) for automating the unseal process using the keys stored in `/etc/vault/unseal.json`

  ```shell
  #!/usr/bin/env sh

  #Define a timestamp function
  timestamp() {
  date "+%b %d %Y %T %Z"
  }


  URL=https://<vault_dns>:8200
  KEYS_FILE=/etc/vault/unseal.json

  LOG=info

  SKIP_TLS_VERIFY=true

  if [ true = "$SKIP_TLS_VERIFY" ]
  then
    CURL_PARAMS="-sk"
  else
    CURL_PARAMS="-s"
  fi

  # Add timestamp
  echo "$(timestamp): Vault-useal started" | tee -a $LOG
  echo "-------------------------------------------------------------------------------" | tee -a $LOG

  initialized=$(curl $CURL_PARAMS $URL/v1/sys/health | jq '.initialized')

  if [ true = "$initialized" ]
  then
    echo "$(timestamp): Vault already initialized" | tee -a $LOG
    while true
    do
      status=$(curl $CURL_PARAMS $URL/v1/sys/health | jq '.sealed')
      if [ true = "$status" ]
      then
          echo "$(timestamp): Vault Sealed. Trying to unseal" | tee -a $LOG
          # Get keys from json file
          for i in `jq -r '.keys[]' $KEYS_FILE` 
            do curl $CURL_PARAMS --request PUT --data "{\"key\": \"$i\"}" $URL/v1/sys/unseal
          done
      sleep 10
      else
          echo "$(timestamp): Vault unsealed" | tee -a $LOG
          break
      fi
    done
  else
    echo "$(timestamp): Vault not initialized yet"
  fi
  ```

- Step 2: Create systemd vault service file `/etc/systemd/system/vault-unseal.service`

  ```
  [Unit]
  Description=Vault Unseal
  After=vault.service
  Requires=vault.service
  PartOf=vault.service

  [Service]
  Type=oneshot
  User=vault
  Group=vault
  ExecStartPre=/bin/sleep 10
  ExecStart=/bin/sh -c '/etc/vault/vault-unseal.sh'
  RemainAfterExit=false

  [Install]
  WantedBy=multi-user.target vault.service
  ```

  This service is defined as part of vault.service (`PartOf`), so stopping/starting vault.service is propagated to this service.

- Step 3. Enable vault systemd service and start it

  ```shell
  sudo systemctl enable vault-unseal.service
  sudo systemctl start vault-unseal.service
  ```


## Vault configuration


Once vault is unsealed following configuration requires to provide vault's root token generated during initialization procces. See `root_token` in `unseal.json` output.

```shell
export VAULT_TOKEN=$(jq -r '.root_token' /etc/vault/unseal.json)
```

{{site.data.alerts.note}}

As an alternative to `vault` commands, API can be used. See [Vault API documentation](https://developer.hashicorp.com/vault/api-docs)

`curl` command can be used. Vault token need to be provider as a HTTP header `X-Vault-Token`

Get request
```shell
curl -k -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/<api_endpoint>
```

Post request

```shell
curl -k -x POST -H "X-Vault-Token: $VAULT_TOKEN" -d '{"key1":"value1", "key2":"value2"}' $VAULT_ADDR/<api_endpoint>
```

{{site.data.alerts.end}}

### Enabling KV secrets

Enable [KV (KeyValue) secrets engine](https://developer.hashicorp.com/vault/docs/secrets/kv) to manage static secrets.

```shell
vault secrets enable -version=2 -path=secret kv
```

This command enables KV version 2 at path `/secret`

### Vault policies

Create vault policies to read and read/write KV secrets

- Read-write policy

  Create file `/etc/vault/policy/secrets-write.hcl`

  ```
  path "secret/*" {
    capabilities = [ "create", "read", "update", "delete", "list", "patch" ]
  }
  ```
  Add policy to vault

  ```shell
  vault policy write readwrite /etc/vault/policy/secrets-readwrite.hcl
  ```

- Read-only policy

  Create file `/etc/vault/policy/secrets-read.hcl`
  ```
  path "secret/*" {
    capabilities = [ "read" ]
  }
  ```

  Add policy to vault

  ```shell
  vault policy write readonly /etc/vault/policy/secrets-read.hcl
  ```

Testing policies:

- Generate tokens for read and write policies

  ```shell
  READ_TOKEN=$(vault token create -policy="readonly" -field=token)
  WRITE_TOKEN=$(vault token create -policy="readwrite" -field=token)
  ```

- Try write a secret using read token

  ```shell
  VAULT_TOKEN=$READ_TOKEN
  vault kv put secret/secret1 user="user1" password="s1cret0"
  ```
  
  Permission denied error:

  ```
  Code: 403. Errors:

  * 1 error occurred:
    * permission denied
  ```

- Try write a secret using write token

  ```shell
  VAULT_TOKEN=$WRITE_TOKEN
  vault kv put secret/secret1 user="user1" password="s1cret0"
  ```
  The secret is stored with success:
  ```
  === Secret Path ===
  secret/data/secret1

  ======= Metadata =======
  Key                Value
  ---                -----
  created_time       2023-01-02T11:04:21.01853116Z
  custom_metadata    <nil>
  deletion_time      n/a
  destroyed          false
  version            1
  ```

- Secret can be read using both tokens
 
  ```shell
  vault kv get secret/secret1
  ```

  ```
  === Secret Path ===
  secret/data/secret1

  ======= Metadata =======
  Key                Value
  ---                -----
  created_time       2023-01-02T11:04:21.01853116Z
  custom_metadata    <nil>
  deletion_time      n/a
  destroyed          false
  version            1

  ====== Data ======
  Key         Value
  ---         -----
  password    s1cret0
  user        user1
  ```

### Kubernetes Auth Method

Enabling [Vault kubernetes auth method](https://developer.hashicorp.com/vault/docs/auth/kubernetes) to authenticate with Vault using a Kubernetes Service Account Token. This method of authentication makes it easy to introduce a Vault token into a Kubernetes Pod.



- Step 1. Create `vault` namespace

  ```shell
  kubectl create namespace vault
  ```

- Step 2. Create service account `vault-auth` to be used by Vault kuberentes authentication
 
  ```yml 
  ---
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: vault-auth
    namespace: vault
  ```

- Step 3. Add proper permissions to service account

  Vault kubernetes authentication method accesses the Kubernetes TokenReview API to validate the provided JWT is still valid. Service Accounts used in this auth method will need to have access to the TokenReview API. If Kubernetes is configured to use RBAC roles, the Service Account should be granted permissions to access this API.
  Check more details in [Vault - Kubernetes Auth Method](https://developer.hashicorp.com/vault/docs/auth/kubernetes#configuring-kubernetes)

  ```yml
  ---
  apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRoleBinding
  metadata:
    name: role-tokenreview-binding
    namespace: vault
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: ClusterRole
    name: system:auth-delegator
  subjects:
    - kind: ServiceAccount
      name: vault-auth
      namespace: vault
  ```

- Step 4. Create long-lived token for vault-auth service account.
  From Kubernetes v1.24, secrets contained long-lived tokens associated to service accounts are not longer created.
  See how to create it in [Kubernetes documentation](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#manually-create-a-long-lived-api-token-for-a-serviceaccount)

  ```yml
  apiVersion: v1
  kind: Secret
  type: kubernetes.io/service-account-token
  metadata:
    name: vault-auth-secret
    namespace: vault
    annotations:
      kubernetes.io/service-account.name: vault-auth
  ```

- Step 5. Get Service Account token
  
  ```shell
  KUBERNETES_SA_SECRET_NAME=$(kubectl get secrets --output=json -n vault | jq -r '.items[].metadata | select(.name|startswith("vault-auth")).name')
  TOKEN_REVIEW_JWT=$(kubectl get secret $KUBERNETES_SA_SECRET_NAME -n vault -o jsonpath='{.data.token}' | base64 --decode)
  ```

- Step 6. Get Kubernetes CA cert and API URL

  ```shell
  # Get Kubernetes CA
  kubectl config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.certificate-authority-data}' | base64 --decode > k3s_ca.crt

  # Get Kubernetes Url
  KUBERNETES_HOST=$(kubectl config view -o jsonpath='{.clusters[].cluster.server}')
  ```

- Step 7. Enable Kubernetes auth method

  ```shell
  vault auth enable kubernetes
  ```

  Or using Vault API

  ```shell
  curl -k --header "X-Vault-Token:$VAULT_TOKEN" --request POST\
    --data '{"type":"kubernetes","description":"kubernetes auth"}' \
    https://vault.picluster.ricsanfre.com:8200/v1/sys/auth/kubernetes
  ```

- Step 8. Configure Vault kubernetes auth method

  ```shell
  vault write auth/kubernetes/config  \
    token_reviewer_jwt="${TOKEN_REVIEW_JWT}" \
    kubernetes_host="${KUBERNETES_HOST}" \
    kubernetes_ca_cert=@k3s_ca.crt
    disable_iss_validation=true
  ```

  Or using Vault API:

  ```shell
  KUBERNETES_CA_CERT=$(kubectl config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.certificate-authority-data}' | base64 --decode | awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}')

  curl --cacert /etc/vault/tls/vault_ca.pem --header "X-Vault-Token:$VAULT_TOKEN" --request POST --data '{"kubernetes_host": "'"$KUBERNETES_HOST"'", "kubernetes_ca_cert":"'"$KUBERNETES_CA_CERT"'", "token_reviewer_jwt":"'"$TOKEN_REVIEW_JWT"'"}' https://vault.picluster.ricsanfre.com:8200/v1/auth/kubernetes/config
  ```

## External Secrets Operator installation

-  Step 1: Add External sercrets repository:
  ```shell
  helm repo add external-secrets https://charts.external-secrets.io
  ```
- Step 2: Fetch the latest charts from the repository:
  ```shell
  helm repo update
  ```
- Step 3: Create namespace
  ```shell
  kubectl create namespace external-secrets
  ```
- Step 4: Install helm chart
  ```shell
  helm install external-secrets \
     external-secrets/external-secrets \
      -n external-secrets \
      --set installCRDs=true
  ```
- Step 5: Create external secrets vault role. Applying read policy

  ```shell
  vault write auth/kubernetes/role/external-secrets \
    bound_service_account_names=external-secrets \
    bound_service_account_namespaces=external-secrets \
    policies=readonly \
    ttl=24h
  ```

  Or using the Vault API

  ```shell
  curl -k --header "X-Vault-Token:$VAULT_TOKEN" --request POST \
    --data '{ "bound_service_account_names": "external-secrets", "bound_service_account_namespaces": "external-secrets", "policies": ["readonly"], "ttl" : "24h"}' \
    https://vault.picluster.ricsanfre.com:8200/v1/auth/kubernetes/role/external-secrets
  ```


- Step 6: Create Cluster Secret Store

  ```yml
  apiVersion: external-secrets.io/v1beta1
   kind: ClusterSecretStore
   metadata:
     name: vault-backend
     namespace: external-secrets
   spec:
     provider:
       vault:
         server: "https://vault.picluster.ricsanfre.com:8200"
         # caBundle needed if vault TLS is signed using a custom CA.
         # If Vault TLS is valid signed by Letsencrypt this is not needed?
         # ca cert base64 encoded and remobed '\n' characteres"
         # <vault-ca> =`cat vault-ca.pem | base64 | tr -d "\n"`
         caBundle: <vault-ca>
         path: "secret"
         version: "v2"
         auth:
           kubernetes:
             mountPath: "kubernetes"
             role: "external-secrets"
  ```
  
  Check ClusterSecretStore status

  ```shell
  kubectl get clustersecretstore -n external-secrets
  NAME            AGE   STATUS   CAPABILITIES   READY
  vault-backend   10m   Valid    ReadWrite      True
  ```

- Step 7: Create External secret

  ```yml
  kind: ExternalSecret
  metadata:
   name: vault-example
  spec:
   secretStoreRef:
     name: vault-backend
     kind: ClusterSecretStore
   target:
     name: mysecret
   data:
   - secretKey: password
     remoteRef:
       key: secret1
       property: password
   - secretKey: user
     remoteRef:
       key: secret1
       property: user
  ```

  Check ExternalSecret status

  ```shell
  kubectl get externalsecret
  NAME            STORE           REFRESH INTERVAL   STATUS         READY
  vault-example   vault-backend   1h                 SecretSynced   True
  ```

  Check Secret created

  ```shell
  kubectl get secret mysecret -o yaml
  ```

## References

- [Vault - Kubernetes Auth Method](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
- [External Vault configuriation guide](https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-external-vault)

- [Tutorial: How to Set External-Secrets with Hashicorp Vault](https://blog.container-solutions.com/tutorialexternal-secrets-with-hashicorp-vault)