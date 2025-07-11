---
title: S3 Backup Backend (Minio)
permalink: /docs/s3-backup/
description: How to deploy a Minio S3 object storage server in Bare-metal environment as backup backend for our Raspberry Pi Kubernetes Cluster.
last_modified_at: "24-06-2025"
---

Minio can be deployed as a Kuberentes service or as stand-alone in bare-metal environment. Since I want to use Minio Server for backing-up/restoring the cluster itself, I will go with a bare-metal installation, considering Minio as an external service in Kubernetes.

Official [documentation](https://docs.min.io/minio/baremetal/installation/deploy-minio-standalone.html) can be used for installing stand-alone Minio Server in bare-metal environment. 

For installing Minio S3 storage server, a VM (Ubuntu OS) hosted in Public Cloud or any linux server/VM that is not not part of the cluster can be used.

Minio installation and configuration tasks can be automated using Ansible role: [**ricsanfre.minio**](https://github.com/ricsanfre/ansible-role-minio). This role can be used to install Minio Server and Minio Client and automate the creation of S3 buckets, users and ACLs for securing the access.

## Minio installation (baremetal server)

Official [documentation](https://docs.min.io/minio/baremetal/installation/deploy-minio-standalone.html) can be used for installing stand-alone Minio Server in bare-metal environment.

-   Step 1. Create minio's UNIX user/group

    ```shell
    sudo groupadd minio
    sudo useradd minio -g minio
    ```
-   Step 2. Create minio's S3 storage directory

    ```shell
    sudo mkdir /storage/minio
    chown -R minio:minio /storage/minio
    chmod -R 750 /storage/minio
    ```

-   Step 3. Create minio's config directories

    ```shell
    sudo mkdir -p /etc/minio
    sudo mkdir -p /etc/minio/ssl
    sudo mkdir -p /etc/minio/policy
    chown -R minio:minio /etc/minio
    chmod -R 750 /etc/minio
    ```

-   Step 4. Download server binary (`minio`) and minio client (`mc`) and copy them to `/usr/local/bin`

    ```shell
    wget https://dl.min.io/server/minio/release/linux-${ARCH}/minio
    wget https://dl.minio.io/client/mc/release/linux-${ARCH}/mc
    chmod +x minio
    chmod +x mc
    sudo mv minio /usr/local/bin/minio
    sudo mv mc /usr/local/bin/mc
    ```
  where `${ARCH}` is amd64 or arm64 depending on the server architecture.

-   Step 5: Create minio Config file `/etc/minio/minio.conf`

    This file contains environment variables that will be used by minio server.

    ```
    # Minio local volumes.
    MINIO_VOLUMES="/storage/minio"

    # Minio options.
    MINIO_OPTS="--address :9091 --console-address :9092 --certs-dir /etc/minio/ssl"

    # Access Key of the server.
    MINIO_ROOT_USER="<admin_user>"
    # Secret key of the server.
    MINIO_ROOT_PASSWORD="<admin_user_passwd>"
    # Minio server region
    MINIO_SITE_REGION="eu-west-1"
    ```

    Minio is configured with the following parameters:

    -   Minio Server API Port 9091 (`MINIO_OPTS`="--address :9091")
    -   Minio Console Port: 9092 (`MINIO_OPTS`="--console-address :9092")
    -   Minio Storage data dir (`MINIO_VOLUMES`): `/storage/minio`
    -   Minio Site Region (`MINIO_SITE_REGION`): `eu-west-1`

-   Step 6. Create systemd minio service file `/etc/systemd/system/minio.service`

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

-   Step 7. Enable minio `systemd` service

    ```shell
    sudo systemctl enable minio.service
    ```

-   Step 8. Start minio service

    ```shell
    sudo systemctl start minio.service
    ```

-   Step 9: Check service is online and functional:

    ```shell
    sudo systemctl status minio.service
    journalctl -f -u minio.service
    ```

### Enable TLS

MinIO enables [Transport Layer Security (TLS)](https://min.io/docs/minio/linux/operations/network-encryption.html#minio-tls) 1.2+ automatically upon detecting a valid x.509 certificate (`.crt`) and private key (`.key`) in the MinIO  cert directory

#### Minio cert directory

By default  minio certs directory is `${HOME}/.minio/certs` directory.
Directory can be changed starting minio server with `--cert-dir` parameter
```shell
minio server --certs-dir /opt/minio/certs ...
```

#### Create Minio TLS certificate

##### Trusted Certificate with Let's Encrypt

In case you have your own domain, a valid TLS certificate signed by [Letsencrypt](https://letsencrypt.org/) can be obtained for Minio server, using [Certbot](https://certbot.eff.org/).

See certbot installation instructions and how to issue certificates in ["PiCluster - TLS Certificates (Certbot)"](/docs/certbot/).


##### Private PKI


If generating public trusted TLS certificate is not possible, selfsigned certificates with a custom CA can be used instead.

Follow this procedure for creating a self-signed certificate for Minio Server

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


#### Install Minio TLS certificate

Once the certificate is created, public certificate and private key need to be installed in Minio server following this procedure:


1. Update Minio config file `/etc/minio/minio.conf`

    ```
    # Minio options.
    MINIO_OPTS="--address :9091 --console-address :9092 --certs-dir /etc/minio/ssl"
    ```
    Adding `--certs-dir` option Minio will look for valid X.509 certificates in   `/etc/minio/ssl`.

2. Copy public certificate `minio.crt` as `/etc/minio/ssl/public.crt`

    ```shell
    sudo cp minio.crt /etc/minio/ssl/public.crt
    sudo chown minio:minio /etc/minio/ssl/public.crt
    ```
3. Copy private key `minio.key` as `/etc/minio/ssl/private.key`

    ```shell
    cp minio.key /etc/minio/ssl/private.key
    sudo chown minio:minio /etc/minio/ssl/private.key
    ```
4. Restart minio server.

    ```shell
    sudo systemctl restart minio.service
    ```

## Minio Configuration

### Install Minio client

Minio client can be installed in any server to perform management operations remotely

-   Step 1: Download `mc` binary

    ```shell
    cd tmp
    wget  https://dl.min.io/client/mc/release/linux-${ARCH}$/mc
    ```

    Where:
    -  `${ARCH}` is amd64 or amr64 depending on the architecture of the linux host


-   Step 2: Move binary to /usr/local/bin

    ```shell
    sudo mv /tmp/mc /usr/local/bin
    chmod +x /user/local/bin/mc
    ```

-   Step 4: Configure connection alias to minio server.

    ```shell
    mc alias set ${MINIO_ALIAS} ${MINIO_URL} ${ACCESS_KEY} ${SECRET_KEY}
    ```
    where

    -   `${MINIO_ALIAS}` is a connection alias assigned to the S3 server
    -   `${MINIO_URL}`: Containing URL of the service (i.e.: "https://${S3_FQDN}:9091", "https://s3.mydomain.com:9091")
    -   `${ACCESS_KEY}`: Contains Minio `root` user configured during installation
    -   `${SECRET_KEY}` : Contains minio `root` user password configured during installation

-   Step 5: Test client

    ```shell
    mc admin info ${MINIO_ALIAS}
    ```


### Buckets

Buckets can be created using Minio's CLI (`mc`)

```shell
mc mb ${MINIO_ALIAS}/${MINIO_BUCKET}
```
Where:

-   `${MINIO_ALIAS}` is the mc's alias connection to Minio Server created during Minio Client configuration
-   `${MINIO_BUCKET}` is the name of the bucket to be created

### Users and ACLs

Users can be created usinng Minio's CLI
```shell
mc admin user add ${MINIO_ALIAS} ${USER_NAME} ${USER_PASSWORD}
```
Where:

-   `${MINIO_ALIAS}` is the mc's alias connection to Minio Server created during Minio Client configuration
-   `${MINIO_USER}` is the name of the user to be created
-   `${MINIO_PASSWORD}` is the password assigned to the user

Access policies to the different buckets can be assigned to the different users using the command:

```shell
mc admin policy add ${MINIO_ALIAS} ${USER_NAME} user_policy.json
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
This policy grants read-write access to `bucket_name`. For each user a different json need to be created, granting access to dedicated bucket.

## Observability

### Metrics

Minio exposes Prometheus-based metrics

{{site.data.alerts.important}} v2 vs v3 metric endpoints

Starting with MinIO Server [RELEASE.2024-07-15T19-02-30Z](https://github.com/minio/minio/releases/tag/RELEASE.2024-07-15T19-02-30Z) and MinIO Client [RELEASE.2024-07-11T18-01-28Z](https://github.com/minio/mc/releases/tag/RELEASE.2024-07-11T18-01-28Z), metrics version 3 provides additional endpoints. MinIO recommends version 3 for new deployments.
-   Metrics v2 description[^1]
-   Metrics v3 description[^2]

Grafana dashboards only available for v2:
-   It seems Minio is not going to maintain a official dashboard for v3. See https://github.com/minio/minio/issues/20678
-   There is a community maintained v3 dashboard at  https://github.com/FedericoAntoniazzi/minio-grafana-dashboard-metrics-v3
{{site.data.alerts.end}}

For details see [Minio's documentation: "Collect MinIO Metrics Using Prometheus"](https://docs.min.io/minio/baremetal/monitoring/metrics-alerts/collect-minio-metrics-using-prometheus.html).

#### Prometheus Integration

By default, MinIO requires authentication to scrape the metrics endpoints. 

To generate the needed bearer tokens, use [`mc admin prometheus generate`](https://min.io/docs/minio/linux/reference/minio-mc-admin/mc-admin-prometheus-generate.html#command-mc.admin.prometheus.generate "mc.admin.prometheus.generate"). 

Authentication can also be disabled for metrics endpoint by setting [`MINIO_PROMETHEUS_AUTH_TYPE`](https://min.io/docs/minio/linux/reference/minio-server/settings/metrics-and-logging.html#envvar.MINIO_PROMETHEUS_AUTH_TYPE "envvar.MINIO_PROMETHEUS_AUTH_TYPE") to `public`.

1. Generate bearer token to be able to access to Minio Metrics

    ```shell
    mc admin prometheus generate <alias>
    ```

    Output is something like this:

    ```
    scrape_configs:
    - job_name: minio-job
    bearer_token: eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJleHAiOjQ3OTQ4Mjg4MTcsImlzcyI6InByb21ldGhldXMiLCJzdWIiOiJtaW5pb2FkbWluIn0.mPFKnj3p-sPflnvdrtrWawSZn3jTQUVw7VGxdBoEseZ3UvuAcbEKcT7tMtfAAqTjZ-dMzQEe1z2iBdbdqufgrA
    metrics_path: /minio/v2/metrics/cluster
    scheme: https
    static_configs:
    - targets: ['127.0.0.1:9091']
    ```

    Where:
    - `bearer_token` is the token to be used by Prometheus for authentication purposes 
    - `metrics_path` is the path to scrape the metrics on Minio server (TCP port 9091)

2. Generate Scrape configurations[^3] [`mc admin prometheus generate`](https://min.io/docs/minio/linux/reference/minio-mc-admin/mc-admin-prometheus-generate.html#command-mc.admin.prometheus.generate) command can be used to generate the scrape configuration to be used by Prometheus.

    -   Generate cluster metrics scrapping configuration

        ```shell
        mc admin prometheus generate <alias>
        ```

        Output is something like:

        ```shell
        scrape_configs:
        - job_name: minio-job
          bearer_token: eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJwcm9tZXRoZXVzIiwic3ViIjoicm9vdCIsImV4cCI6NDkwMDU2MzU1OH0.X06rEpJjwe-C9KHKKu08mZU3q5ZbXF9TKQtpgmnV93aBgJtMF5co-hwzcxymYdaYRTxxydMWxLTVwlr8rdLXZw
          metrics_path: /minio/v2/metrics/cluster
          scheme: https
          static_configs:
          - targets: ['127.0.0.1:9091']
        ```

    -   Generate node metrics scrapping configuration

        ```shell
        mc admin prometheus generate myminio node
        ```

        Output like:
        ```shell
        scrape_configs:
        - job_name: minio-job-node
          bearer_token: eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJwcm9tZXRoZXVzIiwic3ViIjoicm9vdCIsImV4cCI6NDkwMDU2MzU3Nn0.MSptk1y2vV-Ek_b3y9hU7I9WRwSCngCVq1gR_FuTXAHSSg2Pxd4p0TPlTY-_Z2SZEABwaati5Eaila3-Zi9iKg
          metrics_path: /minio/v2/metrics/node
          scheme: https
          static_configs:
          - targets: ['127.0.0.1:9091']
        ```

    -   Generate bucket metrics scrapping configuration

        ```shell
        mc admin prometheus generate myminio bucket
        ```

        Output like:

        ```shell
        scrape_configs:
        - job_name: minio-job-bucket
          bearer_token: eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJwcm9tZXRoZXVzIiwic3ViIjoicm9vdCIsImV4cCI6NDkwMDU2MzYxM30.7czrNI5DYC5gJqVlF3x77Sw0Gln1iJCUuzBBcA72kBL88QEjlBOuDqtbVaB8osoniQzRNDK8jYH0FwAAHKY9zw
          metrics_path: /minio/v2/metrics/bucket
          scheme: https
          static_configs:
          - targets: ['127.0.0.1:9091']
        ```

    -   Generate bucket metrics scrapping configuration

        ```shell
        mc admin prometheus generate myminio resource
        ```

        Output like:

        ```shell
        scrape_configs:
        - job_name: minio-job-resource
          bearer_token: eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJwcm9tZXRoZXVzIiwic3ViIjoicm9vdCIsImV4cCI6NDkwMDU2MzYzMX0.MCuM3w00Q25b4bWprij0OaMs53wdv9_IPSp5yKVW0IEQlpkFeaPrVTh0Vr5w3pYH2EquToXmWE594EUaRIogsw
          metrics_path: /minio/v2/metrics/resource
          scheme: https
          static_configs:
          - targets: ['127.0.0.1:9091']
        ```

#### Monitoring from Kube-Prometheus-Stack

In case Prometheus server is deployed in Kuberentes cluster using kube-prometheus-stack (i.e Prometheus Operator), Prometheus Operator CRD `ScrapeConfig` resource can be used to automatically add configuration for scrapping metrics from baremetal Minio.


-   Create Kubernetes secret containing bearer token generated before

    ```yaml
    apiVersion: v1
    kind: Secret
    type: Opaque
    metadata:
      name: minio-monitor-token
    data:
      token: < minio_bearer_token | b64encode >
    ```

-   Create Prometheus Operator ScrapeConfig resources

    ```yaml
    ---
    apiVersion: monitoring.coreos.com/v1alpha1
    kind: ScrapeConfig
    metadata:
      name: minio-job
    spec:
      jobName: minio-ext
      authorization:
        credentials:
          name: minio-monitor-token
          key: token
      metricsPath: /minio/v2/metrics/cluster
      scheme: HTTPS
      staticConfigs:
      - targets:
        - ${S3_BACKUP_SERVER}:9091
    ---
    apiVersion: monitoring.coreos.com/v1alpha1
    kind: ScrapeConfig
    metadata:
      name: minio-job-node
    spec:
      jobName: minio-ext
      authorization:
        credentials:
          name: minio-monitor-token
          key: token
      metricsPath: /minio/v2/metrics/node
      scheme: HTTPS
      staticConfigs:
      - targets:
        - ${S3_BACKUP_SERVER}:9091
    ---
    apiVersion: monitoring.coreos.com/v1alpha1
    kind: ScrapeConfig
    metadata:
      name: minio-job-bucket
    spec:
      jobName: minio-ext
      authorization:
        credentials:
          name: minio-monitor-token
          key: token
      metricsPath: /minio/v2/metrics/bucket
      scheme: HTTPS
      staticConfigs:
      - targets:
        - ${S3_BACKUP_SERVER}:9091
    ---
    apiVersion: monitoring.coreos.com/v1alpha1
    kind: ScrapeConfig
    metadata:
      name: minio-job-resource
    spec:
      jobName: minio-ext
      authorization:
        credentials:
          name: minio-monitor-token
          key: token
      metricsPath: /minio/v2/metrics/resource
      scheme: HTTPS
      staticConfigs:
      - targets:
        - ${S3_BACKUP_SERVER}:9091
    ```

    Where `${S3_BACKUP_SERVER}` should be replaced by DNS or IP address of the backup server.


#### Grafana Dashboards

MinIO provides Grafana Dashboards to display metrics collected by Prometheus.

There are 3 Dashboards available:

-   MinIO Server Metrics Dashboard: [Grafana dashboard id: 13502](https://grafana.com/grafana/dashboards/13502-minio-dashboard/)
-   MinIO Bucket Metrics Dashboard: [Grafana dashboard id: 19237](https://grafana.com/grafana/dashboards/19237-minio-bucket-dashboard/)
-   MinIO Node Metrics Dashboard: Available in MiniO GitHub Repo: [mino-node.json](https://raw.githubusercontent.com/minio/minio/master/docs/metrics/prometheus/grafana/node/minio-node.json)
-   MinIO Replication Metrics Dashboard: [Grafana dashbord Id 15305](https://grafana.com/grafana/dashboards/15305-minio-replication-dashboard/)

Dashboard can be automatically added using Grafana's dashboard providers configuration. See further details in ["PiCluster - Observability Visualization (Grafana): Automating installation of community dasbhoards](/docs/grafana/#automating-installation-of-grafana-community-dashboards)

Add following configuration to Grafana's helm chart values file, so a MinIO's dashboard provider can be created and dashboards can be automatically downloaded from GitHub repository

```yaml
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: minio
        orgId: 1
        folder: Minuo
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/minio-folder
# Dashboards
dashboards:
  minio:
    minio-server:
      # https://grafana.com/grafana/dashboards/13502-minio-dashboard/
      # renovate: depName="MinIO Dashboard"
      gnetId: 13502
      revision: 26
      datasource:
        - { name: DS_PROMETHEUS, value: Prometheus }
    minio-bucket:
      # https://grafana.com/grafana/dashboards/19237-minio-bucket-dashboard/
      # renovate: depName="MinIO Dashboard"
      gnetId: 19237
      revision: 2
      datasource:
        - { name: DS_PROMETHEUS, value: Prometheus }
    minio-node:
      url: https://raw.githubusercontent.com/minio/minio/master/docs/metrics/prometheus/grafana/node/minio-node.json
      datasource: Prometheus
    minio-replication:
      # https://grafana.com/grafana/dashboards/15305-minio-replication-dashboard/
      # renovate: depName="MinIO Dashboard"
      gnetId: 15305
      revision: 5
      datasource:
        - { name: DS_PROMETHEUS, value: Prometheus }
```

---

[^1]: [https://min.io/docs/minio/linux/operations/monitoring/metrics-v2.html](https://min.io/docs/minio/linux/operations/monitoring/metrics-v2.html)
[^2]: [https://min.io/docs/minio/linux/operations/monitoring/metrics-and-alerts.html](https://min.io/docs/minio/linux/operations/monitoring/metrics-and-alerts.html)
[^3]: [https://min.io/docs/minio/linux/operations/monitoring/collect-minio-metrics-using-prometheus.html#generate-the-scrape-configuration](https://min.io/docs/minio/linux/operations/monitoring/collect-minio-metrics-using-prometheus.html#generate-the-scrape-configuration)