---
title: S3 Backup Backend (RustFS)
permalink: /docs/s3-backup/
description: How to deploy a RustFS S3 object storage server in Bare-metal environment as backup backend for our Raspberry Pi Kubernetes Cluster.
last_modified_at: "19-06-2026"
---

RustFS can be deployed as a Kubernetes service or as stand-alone in bare-metal environment. Since I want to use the S3 Server for backing-up/restoring the cluster itself, I will go with a bare-metal installation, considering RustFS as an external service in Kubernetes.

[RustFS](https://github.com/rustfs/rustfs) is a high-performance, S3-compatible distributed object storage system written in Rust. It is fully open-source and designed for low resource consumption, making it a good fit for ARM64-based homelab clusters.

Official documentation can be found at [docs.rustfs.com](https://docs.rustfs.com).

For installing the RustFS S3 storage server, a VM (Ubuntu OS) hosted in Public Cloud or any Linux server/VM that is not part of the cluster can be used.

RustFS installation and configuration tasks can be automated using the Ansible role: [**ricsanfre.rustfs**](https://github.com/ricsanfre/ansible-role-rustfs). This role installs the RustFS Server and CLI client (`rc`) and can create S3 buckets.

## RustFS installation (baremetal server)

-   Step 1. Create RustFS UNIX user/group

    ```shell
    sudo groupadd rustfs
    sudo useradd rustfs -g rustfs
    ```

-   Step 2. Create RustFS S3 storage directory

    ```shell
    sudo mkdir /storage/minio
    chown -R rustfs:rustfs /storage/minio
    chmod -R 750 /storage/minio
    ```

-   Step 3. Create RustFS config directories

    ```shell
    sudo mkdir -p /etc/rustfs
    sudo mkdir -p /etc/rustfs/ssl
    chown -R rustfs:rustfs /etc/rustfs
    chmod -R 750 /etc/rustfs
    ```

-   Step 4. Create RustFS log directory

    ```shell
    sudo mkdir -p /var/log/rustfs
    chown -R rustfs:rustfs /var/log/rustfs
    chmod -R 750 /var/log/rustfs
    ```

-   Step 5. Download server binary (`rustfs`) and CLI client (`rc`) and copy them to `/usr/local/bin`

    ```shell
    wget https://github.com/rustfs/rustfs/releases/download/${RUSTFS_VERSION}/rustfs-linux-${ARCH}-musl-latest.zip
    unzip rustfs-linux-${ARCH}-musl-latest.zip
    chmod +x rustfs
    sudo mv rustfs /usr/local/bin/rustfs

    wget https://github.com/rustfs/cli/releases/download/${CLI_VERSION}/rc-linux-${ARCH}
    chmod +x rc-linux-${ARCH}
    sudo mv rc-linux-${ARCH} /usr/local/bin/rc
    ```

    Where:
    - `${RUSTFS_VERSION}` is the RustFS server release version (e.g., `1.0.0-beta.7`)
    - `${CLI_VERSION}` is the `rc` CLI release version (e.g., `v0.1.20`)
    - `${ARCH}` is `amd64` or `arm64` depending on the server architecture

    {{site.data.alerts.note}}
    The `musl` build variant provides a statically linked binary for maximum compatibility across Linux distributions.
    {{site.data.alerts.end}}

-   Step 6: Create RustFS config file `/etc/rustfs/rustfs.conf`

    This file contains environment variables that will be used by the RustFS server.

    ```
    # RustFS admin credentials
    RUSTFS_ACCESS_KEY="<admin_user>"
    RUSTFS_SECRET_KEY="<admin_user_passwd>"

    # RustFS data volumes
    RUSTFS_VOLUMES="/storage/minio"

    # RustFS listen addresses
    RUSTFS_ADDRESS=":9091"
    RUSTFS_CONSOLE_ADDRESS=":9092"

    # Web console
    RUSTFS_CONSOLE_ENABLE=true

    # Logging
    RUSTFS_OBS_LOGGER_LEVEL=error
    RUSTFS_OBS_LOG_DIRECTORY="/var/log/rustfs/"
    ```

    RustFS is configured with the following parameters:

    -   RustFS S3 API Port 9091 (`RUSTFS_ADDRESS`)
    -   RustFS Console Port: 9092 (`RUSTFS_CONSOLE_ADDRESS`)
    -   RustFS Storage data dir (`RUSTFS_VOLUMES`): `/storage/minio`
    -   Admin credentials (`RUSTFS_ACCESS_KEY` / `RUSTFS_SECRET_KEY`)
    -   Web console enabled (`RUSTFS_CONSOLE_ENABLE`)
    -   Log level: `error` (`RUSTFS_OBS_LOGGER_LEVEL`)

-   Step 7. Create systemd RustFS service file `/etc/systemd/system/rustfs.service`

    ```
    [Unit]
    Description=RustFS Object Storage Server
    Documentation=https://docs.rustfs.com
    Wants=network-online.target
    After=network-online.target
    AssertFileIsExecutable=/usr/local/bin/rustfs

    [Service]
    Type=notify
    NotifyAccess=main

    User=rustfs
    Group=rustfs
    WorkingDirectory=/usr/local

    EnvironmentFile=-/etc/rustfs/rustfs.conf

    ExecStart=/usr/local/bin/rustfs $RUSTFS_VOLUMES

    # Let systemd restart this service always
    Restart=always
    RestartSec=10s

    # Specifies the maximum file descriptor number that can be opened by this process
    LimitNOFILE=1048576
    LimitNPROC=32768

    # Specifies the maximum number of threads this process can create
    TasksMax=infinity

    # Disable timeout logic and wait until process is stopped
    TimeoutStopSec=30s
    SendSIGKILL=no
    OOMScoreAdjust=-1000

    # Security hardening
    NoNewPrivileges=true
    ProtectHome=true
    PrivateTmp=true
    PrivateDevices=true
    ProtectClock=true
    ProtectKernelTunables=true
    ProtectKernelModules=true
    ProtectControlGroups=true
    RestrictSUIDSGID=true
    RestrictRealtime=true
    ReadWritePaths=/var/log/rustfs

    # Logging
    StandardOutput=append:/var/log/rustfs/rustfs.log
    StandardError=append:/var/log/rustfs/rustfs-err.log

    [Install]
    WantedBy=multi-user.target
    ```

    This service starts the RustFS server using the `rustfs` UNIX user/group, loading environment variables from `/etc/rustfs/rustfs.conf` and executing:

    ```shell
    /usr/local/bin/rustfs $RUSTFS_VOLUMES
    ```

-   Step 8. Enable RustFS `systemd` service

    ```shell
    sudo systemctl enable rustfs.service
    ```

-   Step 9. Start RustFS service

    ```shell
    sudo systemctl start rustfs.service
    ```

-   Step 10: Check service is online and functional:

    ```shell
    sudo systemctl status rustfs.service
    journalctl -f -u rustfs.service
    ```

### Enable TLS

RustFS enables Transport Layer Security (TLS) by setting the `RUSTFS_TLS_PATH` environment variable to a directory containing valid `rustfs_cert.pem` and `rustfs_key.pem` files.

#### RustFS TLS directory

By default, the TLS directory is `/etc/rustfs/ssl`. This is configured via `RUSTFS_TLS_PATH` and the server URL scheme changes to `https://` automatically when TLS is enabled.

#### Create RustFS TLS certificate

##### Trusted Certificate with Let's Encrypt

In case you have your own domain, a valid TLS certificate signed by [Letsencrypt](https://letsencrypt.org/) can be obtained for the RustFS server, using [Certbot](https://certbot.eff.org/).

See certbot installation instructions and how to issue certificates in ["PiCluster - TLS Certificates (Certbot)"](/docs/certbot/).

##### Private PKI

If generating a public trusted TLS certificate is not possible, self-signed certificates with a custom CA can be used instead.

Follow this procedure for creating a self-signed certificate for the RustFS Server:

-   Step 1. Create Root CA

    -   Create Root CA Key

        ```shell
        openssl genrsa -out rootCA.key 4096
        ```
    -   Create and self sign the Root Certificate

        ```shell
        openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 1024 -out rootCA.crt
        ```

-   Step 2. Create the signing request (csr)

    -   Create key

        ```shell
        openssl genrsa -out private.key 4096
        ```
    -   Create a file named `openssl.conf` with the content below. Set `IP.1` and/or `DNS.1` to point to the correct IP/DNS addresses:

        ```sh
        [req]
        distinguished_name = req_distinguished_name
        x509_extensions = v3_req
        prompt = no

        [req_distinguished_name]
        C = ES
        ST = Madrid
        L = Somewhere
        O = MyOrg
        OU = MyOU
        CN = MyServerName

        [v3_req]
        subjectAltName = @alt_names

        [alt_names]
        IP.1 = 127.0.0.1
        DNS.1 = myserver.mydomain.com
        ```

        Run `openssl` by specifying the configuration file and enter a passphrase if prompted:

        ```shell
        openssl req -new -x509 -nodes -days 730 -key private.key -out public.csr -config openssl.conf
        ```
    -   Verify the csr's content

        ```shell
        openssl req -in public.csr -noout -text
        ```
    -   Generate the certificate using the mydomain csr and key along with the CA Root key

        ```shell
        openssl x509 -req -in public.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out public.crt -days 500 -sha256
        ```

#### Install RustFS TLS certificate

Once the certificate is created, the public certificate and private key need to be installed on the RustFS server:

1. Update RustFS config file `/etc/rustfs/rustfs.conf` to enable TLS:

    ```
    # TLS
    RUSTFS_TLS_PATH="/etc/rustfs/ssl"
    ```

2. Copy public certificate as `/etc/rustfs/ssl/rustfs_cert.pem`

    ```shell
    sudo cp public.crt /etc/rustfs/ssl/rustfs_cert.pem
    sudo chown rustfs:rustfs /etc/rustfs/ssl/rustfs_cert.pem
    sudo chmod 640 /etc/rustfs/ssl/rustfs_cert.pem
    ```

3. Copy private key as `/etc/rustfs/ssl/rustfs_key.pem`

    ```shell
    sudo cp private.key /etc/rustfs/ssl/rustfs_key.pem
    sudo chown rustfs:rustfs /etc/rustfs/ssl/rustfs_key.pem
    sudo chmod 640 /etc/rustfs/ssl/rustfs_key.pem
    ```

4. Restart RustFS server.

    ```shell
    sudo systemctl restart rustfs.service
    ```

## RustFS Configuration

### Install RustFS CLI client

The RustFS CLI client (`rc`) can be installed on any server to perform management operations remotely.

-   Step 1: Download `rc` binary

    ```shell
    cd /tmp
    wget https://github.com/rustfs/cli/releases/download/${CLI_VERSION}/rc-linux-${ARCH}
    ```

    Where:
    - `${CLI_VERSION}` is the `rc` CLI version (e.g., `v0.1.20`)
    - `${ARCH}` is `amd64` or `arm64` depending on the architecture of the Linux host

-   Step 2: Move binary to `/usr/local/bin`

    ```shell
    sudo mv /tmp/rc-linux-${ARCH} /usr/local/bin/rc
    chmod +x /usr/local/bin/rc
    ```

-   Step 3: Configure connection alias to the RustFS server.

    ```shell
    rc alias set ${S3_ALIAS} ${S3_URL} ${ACCESS_KEY} ${SECRET_KEY}
    ```

    Where:
    - `${S3_ALIAS}` is a connection alias assigned to the S3 server
    - `${S3_URL}`: URL of the S3 service (e.g., `https://object-store.homelab.ricsanfre.com:9091`)
    - `${ACCESS_KEY}`: The RustFS `root` user access key configured during installation
    - `${SECRET_KEY}`: The RustFS `root` user secret key configured during installation

    {{site.data.alerts.note}}
    If using self-signed TLS certificates, add the `--insecure` flag:

    ```shell
    rc alias set ${S3_ALIAS} ${S3_URL} ${ACCESS_KEY} ${SECRET_KEY} --insecure
    ```
    {{site.data.alerts.end}}

-   Step 4: Test client connectivity

    ```shell
    rc admin info cluster ${S3_ALIAS}
    ```

### Buckets

Buckets can be created using RustFS CLI (`rc`):

```shell
rc mb ${S3_ALIAS}/${BUCKET_NAME}
```

Where:
- `${S3_ALIAS}` is the `rc` alias connection to the S3 Server created during client configuration
- `${BUCKET_NAME}` is the name of the bucket to be created

### Users and ACLs

Users can be created using RustFS CLI:

```shell
rc admin user add ${S3_ALIAS} ${USER_NAME} ${USER_PASSWORD}
```

Where:
- `${S3_ALIAS}` is the `rc` alias connection to the S3 Server
- `${USER_NAME}` is the name of the user to be created
- `${USER_PASSWORD}` is the password assigned to the user

Access policies to buckets can be assigned to users using:

```shell
rc admin policy create ${S3_ALIAS} ${POLICY_NAME} user_policy.json
rc admin policy attach ${S3_ALIAS} ${POLICY_NAME} ${USER_NAME}
```

Where `user_policy.json` contains an AWS IAM-style access policy definition:

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

This policy grants read-write access to `bucket_name`. For each user a different JSON should be created, granting access to the dedicated bucket.

### Terraform-based configuration

As an alternative to manual `rc` CLI commands, S3 resources (buckets, IAM users, and IAM policies) can be managed declaratively using OpenTofu/Terraform with the existing [MinIO Terraform provider (`aminueza/minio`)](https://registry.terraform.io/providers/aminueza/minio/latest). This provider works against RustFS without modification.

#### Why the MinIO provider works with RustFS

RustFS implements two distinct API layers that the MinIO Terraform provider relies on:

| Terraform Resource | API Used | RustFS Support |
|:---|:---|:---|
| `minio_s3_bucket` | Standard AWS S3 REST API (`PUT /bucket-name`) | ✅ Native S3 compatibility |
| `minio_iam_user` | MinIO Admin API (`/minio/admin/v3/add-user`) | ✅ RustFS emulates this endpoint |
| `minio_iam_policy` | MinIO Admin API (`/minio/admin/v3/add-canned-policy`) | ✅ RustFS emulates this endpoint |
| `minio_iam_user_policy_attachment` | MinIO Admin API (identity engine mapping) | ✅ RustFS identity engine supports it |

**Bucket resources** use the universal S3 API. Since RustFS is natively S3-compatible, standard `CreateBucket`, `PutBucketVersioning`, and related operations succeed without any special handling.

**IAM resources** use MinIO's Admin REST API. Under the hood, the Terraform provider uses the MinIO Go Admin Client SDK (`madmin-go`) to manage identity. RustFS includes a dedicated compatibility layer that listens on the same `/minio/admin/v3/*` routes, parses the MinIO-formatted payloads, and writes credentials and policies into its own internal identity database.

{{site.data.alerts.warning}} **Server configuration resources are unsupported**

Resources that modify MinIO's proprietary internal configuration (such as `minio_server_config_*` or `minio_iam_group`) attempt to alter system settings that don't exist in RustFS. Only bucket, IAM user, and IAM policy resources are compatible.
{{site.data.alerts.end}}

#### Example Terraform configuration

```hcl
terraform {
  required_providers {
    minio = {
      source  = "aminueza/minio"
      version = "~> 3.0"
    }
  }
}

provider "minio" {
  minio_server   = "object-store.homelab.ricsanfre.com:9091"
  minio_region   = "eu-west-1"
  minio_user     = var.minio_admin_user
  minio_password = var.minio_admin_password
  minio_ssl      = true
  minio_insecure = false
}

# S3 bucket
resource "minio_s3_bucket" "backup" {
  bucket        = "k3s-velero"
  force_destroy = true
}

# IAM policy
resource "minio_iam_policy" "velero" {
  name = "velero"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:PutObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ]
      Resource = [
        "arn:aws:s3:::k3s-velero",
        "arn:aws:s3:::k3s-velero/*"
      ]
    }]
  })
}

# IAM user with secret from Vault
resource "minio_iam_user" "velero" {
  name   = "velero"
  secret = var.velero_secret_key
}

# Attach policy to user
resource "minio_iam_user_policy_attachment" "velero" {
  user_name   = minio_iam_user.velero.name
  policy_name = minio_iam_policy.velero.name
}
```

{{site.data.alerts.note}} **Vault integration**

User secrets can be sourced from HashiCorp Vault using the `hashicorp/vault` provider, keeping credentials out of Terraform state. The same pattern used with MinIO works unchanged against RustFS.
{{site.data.alerts.end}}

#### Data-driven pattern

For managing multiple buckets, users, and policies at scale, resource definitions can be loaded from JSON files stored in a `resources/` directory. This keeps Terraform HCL thin and makes adding new services a matter of dropping in a JSON file — the same pattern described in the [PiCluster S3 Backup Backend documentation](/docs/s3-backup/).

The full Terraform implementation for this cluster is available in the repository at [`terraform/minio/`](https://github.com/ricsanfre/pi-cluster/tree/master/terraform/minio), including the provider configuration, resource definitions, and the data-driven JSON resource files for all cluster services (Velero, Loki, Tempo, Longhorn, Restic, and Barman/CNPG).

## Observability

### Metrics

RustFS uses OpenTelemetry (OTLP) for observability. It does not expose direct Prometheus HTTP scrape endpoints. Instead, RustFS pushes metrics, traces, and logs to an OpenTelemetry Collector via `RUSTFS_OBS_ENDPOINT`.

{{site.data.alerts.important}} **OpenTelemetry (OTLP) vs Prometheus scrape**

Unlike MinIO, which exposes `/minio/v2/metrics/*` endpoints for direct Prometheus scraping with bearer token authentication, RustFS follows the OpenTelemetry standard. To collect RustFS metrics:

1. Deploy an OpenTelemetry Collector in the cluster
2. Set `RUSTFS_OBS_ENDPOINT=http://otel-collector:4318` in the RustFS config
3. Configure Prometheus to scrape the OTel Collector's Prometheus exporter

This is a separate project tracked outside this documentation.
{{site.data.alerts.end}}

#### Observability configuration

RustFS observability is configured via environment variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `RUSTFS_OBS_ENDPOINT` | OTLP HTTP endpoint for all telemetry | `http://otel-collector:4318` |
| `RUSTFS_OBS_LOGGER_LEVEL` | Log verbosity (`error`, `warn`, `info`, `debug`) | `error` |
| `RUSTFS_OBS_LOG_DIRECTORY` | Directory for file-based logging | `/var/log/rustfs/` |
| `RUSTFS_OBS_PROFILING_ENDPOINT` | Pyroscope continuous profiling endpoint | `http://pyroscope:4040` |

These variables are set in the RustFS config file `/etc/rustfs/rustfs.conf`.

#### Systemd logging

In addition to OTLP export, RustFS systemd service captures stdout/stderr output to log files:

-   `/var/log/rustfs/rustfs.log` — standard output
-   `/var/log/rustfs/rustfs-err.log` — standard error

---

[^1]: [https://docs.rustfs.com/features/logging/](https://docs.rustfs.com/features/logging/)
[^2]: [https://github.com/rustfs/rustfs](https://github.com/rustfs/rustfs)
[^3]: [https://github.com/rustfs/cli](https://github.com/rustfs/cli)
