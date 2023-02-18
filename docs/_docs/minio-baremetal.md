---
title: S3 Backup Backend (Minio)
permalink: /docs/s3-backup/
description: How to deploy a Minio S3 object storage server in Bare-metal environment as backup backend for our Raspberry Pi Kubernetes Cluster.
last_modified_at: "17-02-2023"
---

Minio can be deployed as a Kuberentes service or as stand-alone in bare-metal environment. Since I want to use Minio Server for backing-up/restoring the cluster itself, I will go with a bare-metal installation, considering Minio as an external service in Kubernetes.

Official [documentation](https://docs.min.io/minio/baremetal/installation/deploy-minio-standalone.html) can be used for installing stand-alone Minio Server in bare-metal environment. 

For a more secured and multi-user Minio installation the instructions of this [post](https://www.civo.com/learn/create-a-multi-user-minio-server-for-s3-compatible-object-hosting) can be used.

For installing Minio S3 storage server, I am using a VM (Ubuntu OS) hosted in Public Cloud (Oracle Cloud Infrastructure), but any linux server/VM that is not not part of the cluster can be used.

Minio installation and configuration tasks have been automated with Ansible developing a role: **ricsanfre.minio**. This role, installs Minio Server and Minio Client and automatically create S3 buckets, and configure users and ACLs for securing the access.

## Minio installation (baremetal server)

- Step 1. Create minio's UNIX user/group

  ```shell
  sudo groupadd minio
  sudo useradd minio -g minio
  ```
- Step 2. Create minio's S3 storage directory

  ```shell
  sudo mkdir /storage/minio
  chown -R minio:minio /storage/minio
  chmod -R 750 /storage/minio
  ```

- Step 3. Create minio's config directories

  ```shell
  sudo mkdir -p /etc/minio
  sudo mkdir -p /etc/minio/ssl
  sudo mkdir -p /etc/minio/policy
  chown -R minio:minio /etc/minio
  chmod -R 750 /etc/minio
  ```

- Step 4. Download server binary (`minio`) and minio client (`mc`) and copy them to `/usr/local/bin`

  ```shell
   wget https://dl.min.io/server/minio/release/linux-<arch>/minio
   wget https://dl.minio.io/client/mc/release/linux-<arch>/mc
   chmod +x minio
   chmod +x mc
   sudo mv minio /usr/local/bin/minio
   sudo mv mc /usr/local/bin/mc
  ```
  where `<arch>` is amd64 or arm64.

- Step 5: Create minio Config file `/etc/minio/minio.conf`

  This file contains environment variables that will be used by minio server.
  ```
  # Minio local volumes.
  MINIO_VOLUMES="/storage/minio"

  # Minio cli options.
  MINIO_OPTS="--address :9091 --console-address :9092 --certs-dir /etc/minio/ssl"

  # Access Key of the server.
  MINIO_ROOT_USER="<admin_user>"
  # Secret key of the server.
  MINIO_ROOT_PASSWORD="<admin_user_passwd>"
  # Minio server region
  MINIO_SITE_REGION="eu-west-1"
  # Minio server URL
  MINIO_SERVER_URL="https://s3.picluster.ricsanfre.com:9091"
  ```

  Minio is configured with the following parameters:

  - Minio Server API Port 9091 (`MINIO_OPTS`="--address :9091")
  - Minio Console Port: 9092 (`MINIO_OPTS`="--console-address :9092")
  - Minio Storage data dir (`MINIO_VOLUMES`): `/storage/minio`
  - Minio Site Region (`MINIO_SITE_REGION`): `eu-west-1`
  - SSL certificates stored in (`MINIO_OPTS`="--certs-dir /etc/minio/ssl"): `/etc/minio/ssl`.
  - Minio server URL (`MINIO_SERVER_URL`): Url used to connecto to Minio Server API

- Step 6. Create systemd minio service file `/etc/systemd/system/minio.service`

  ```
  [Unit]
  Description=MinIO
  Documentation=https://docs.min.io
  Wants=network-online.target
  After=network-online.target
  AssertFileIsExecutable=/usr/local/bin/minio

  [Service]
  WorkingDirectory=/usr/local/

  User=minio
  Group=minio
  ProtectProc=invisible

  EnvironmentFile=/etc/minio/minio.conf
  ExecStartPre=/bin/bash -c "if [ -z \"${MINIO_VOLUMES}\" ]; then echo \"Variable MINIO_VOLUMES not set in /etc/minio/minio.conf\"; exit 1; fi"

  ExecStart=/usr/local/bin/minio server $MINIO_OPTS $MINIO_VOLUMES

  # Let systemd restart this service always
  Restart=always

  # Specifies the maximum file descriptor number that can be opened by this process
  LimitNOFILE=65536

  # Specifies the maximum number of threads this process can create
  TasksMax=infinity

  # Disable timeout logic and wait until process is stopped
  TimeoutStopSec=infinity
  SendSIGKILL=no

  [Install]
  WantedBy=multi-user.target
  ```
  This service start minio server using minio UNIX group, loading environment variables located in `/etc/minio/minio.conf` and executing the following startup command:

  ```shell
  /usr/local/minio server $MINIO_OPTS $MINIO_VOLUMES
  ```

- Step 7. Enable minio systemd service

  ```shell
  sudo systemctl enable minio.service
  ```

- Step 8. Create Minio SSL certificate

  In case you have your own domain, a valid SSL certificate signed by [Letsencrypt](https://letsencrypt.org/) can be obtained for Minio server, using [Certbot](https://certbot.eff.org/).

  See certbot installation instructions in [CertManager - Letsencrypt Certificates Section](/docs/certmanager/#installing-certbot-ionos). Those instructions indicate how to install certbot using DNS challenge with IONOS DNS provider (my DNS provider). Similar procedures can be followed for other DNS providers.

  Letsencrypt using HTTP challenge is avoided for security reasons (cluster services are not exposed to public internet).

  If generating valid SSL certificate is not possible, selfsigned certificates with a custom CA can be used instead.

  {{site.data.alerts.important}}

  `restic` backup to a S3 Object Storage backend using self-signed certificates does not work (See issue [#26](https://github.com/ricsanfre/pi-cluster/issues/26)). However, it works if SSL certificates are signed using a custom CA.

  {{site.data.alerts.end}}

  Follow this procedure for creating a self-signed certificate for Minio Server

  1. Create a self-signed CA key and self-signed certificate

     ```shell
     openssl req -x509 \
            -sha256 \
            -nodes \
            -newkey rsa:4096 \
            -subj "/CN=Ricsanfre CA" \
            -keyout rootCA.key -out rootCA.crt
     ```
  2. Create a SSL certificate for Minio server signed using the custom CA
    
     ```shell
     openssl req -new -nodes -newkey rsa:4096 \
                 -keyout minio.key \
                 -out minio.csr \
                 -batch \
                 -subj "/C=ES/ST=Madrid/L=Madrid/O=Ricsanfre CA/OU=picluster/CN=s3.picluster.ricsanfre.com"

      openssl x509 -req -days 365000 -set_serial 01 \
            -extfile <(printf "subjectAltName=DNS:s3.picluster.ricsanfre.com") \
            -in minio.csr \
            -out minio.crt \
            -CA rootCA.crt \
            -CAkey rootCA.key
     ```

  Once the certificate is created, public certificate and private key need to be installed in Minio server following this procedure:


  1. Copy public certificate `minio.crt` as `/etc/minio/ssl/public.crt`

     ```shell
     sudo cp minio.crt /etc/minio/ssl/public.crt
     sudo chown minio:minio /etc/minio/ssl/public.crt
     ```
  2. Copy private key `minio.key` as `/etc/minio/ssl/private.key`

     ```shell
     cp minio.key /etc/minio/ssl/private.key
     sudo chown minio:minio /etc/minio/ssl/private.key
     ```
  3. Restart minio server.
     
     ```shell
     sudo systemctl restart minio.service
     ```

  {{site.data.alerts.note}}

  Certificate must be created for the DNS name associated to MINIO S3 service, i.e `s3.picluster.ricsanfre.com`.

  `MINIO_SERVER_URL` environment variable need to be configured, to avoid issues with TLS certificates without IP Subject Alternative Names.

  {{site.data.alerts.end}}

  To connect to Minio console use the URL https://s3.picluster.ricsanfre.com:9091

- Step 9. Configure minio client: `mc`

  Configure connection alias to minio server.
  
  ```shell
  mc alias set minio_alias <minio_url> <minio_root_user> <minio_root_password>
  ```

## Minio Configuration

### Buckets

The following buckets need to be created for backing-up different cluster components:

- Longhorn Backup: `k3s-longhorn`
- Velero Backup: `k3s-velero`
- OS backup: `restic`

Buckets can be created using Minio's CLI (`mc`)

```shell
mc mb <minio_alias>/<bucket_name> 
```
Where: `<minio_alias>` is the mc's alias connection to Minio Server using admin user credentials, created during Minio installation in step 9.

### Users and ACLs

Following users will be created to grant access to Minio S3 buckets:

- `longhorn` with read-write access to `k3s-longhorn` bucket.
- `velero` with read-write access to `k3s-velero` bucket. 
- `restic` with read-write access to `restic` bucket

  
Users can be created usinng Minio's CLI
```shell
mc admin user add <minio_alias> <user_name> <user_password>
```
Access policies to the different buckets can be assigned to the different users using the command:

```shell
mc admin policy add <minio_alias> <user_name> user_policy.json
```
Where `user_policy.json`, contains AWS access policies definition like:

```json
{
"Version": "2012-10-17",
"Statement": [
  {
      "Effect": "Allow",
      "Action": [
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject"
      ],
      "Resource": [
          "arn:aws:s3:::bucket_name",
          "arn:aws:s3:::bucket_name/*"
      ]
  }  
]
}
``` 
This policy grants read-write access to `bucket_name`. For each user a different json need to be created, granting access to dedicated bucket. Those json files can be stored in `/etc/minio/policy` directory.