---
title: Backup & Restore
permalink: /docs/backup/
description: How to deploy a backup solution based on Velero and Restic in our Raspberry Pi Kubernetes Cluster.
last_modified_at: "24-07-2024"
---

## Backup Architecture and Design

It is needed to implement a backup strategy for the K3S cluster. This backup strategy should, at least, contains a backup infrastructure, and backup and restore procedures for OS basic configuration files, K3S cluster configuration and PODs Persistent Volumes.

The backup architecture is the following:

![picluster-backup-architecture](/assets/img/pi-cluster-backup-architecture.png)

- OS filesystem backup

  Some OS configuration files should be backed up in order to being able to restore configuration at OS level.
  For doing so, [Restic](https://restic.net) can be used. Restic provides a fast and secure backup program that can be intregrated with different storage backends, including Cloud Service Provider Storage services (AWS S3, Google Cloud Storage, Microsoft Azure Blob Storage, etc). It also supports opensource S3 [Minio](https://min.io). 


- K3S cluster configuration backup and restore.

  This could be achieve backing up and restoring the etcd Kubernetes cluster database as official [documentation](https://rancher.com/docs/k3s/latest/en/backup-restore/) states. The supported backup procedure is only supported in case `etcd` database is deployed (by default K3S use a sqlite databse)

  As an alternative [Velero](https://velero.io), a CNCF project, can be used to backup and restore kubernetes cluster configuration. Velero is kubernetes-distribution agnostic since it uses Kubernetes API for extracting and restoring the configuration, instead relay on backups/restores of etcd database.

  Since for the backup and restore is using standard Kubernetes API, Velero can be used as a tool for migrating the configuration from one kubernetes cluster to another having a differnet kubernetes flavor. From K3S to K8S for example.

  Velero can be intregrated with different storage backends, including Cloud Service Provider Storage services (AWS S3, Google Cloud Storage, Microsoft Azure Blob Storage, etc). It also supports opensource S3 [Minio](https://min.io). 

  Since Velero is a most generic way to backup any Kuberentes cluster (not just K3S) it will be used to implement my cluster K3S backup.

- PODs Persistent Volumes backup and restore.

  Applications running in Kubernetes needs to be backed up in a consistent state. It means that before copying the filesystem is it required to freeze the application and make it flush all the pending changes to disk before making the copy. Once the backup is finished, the application can be unfreeze.
  1) Application Freeze and flush to disk
  2) Filesystem level backup
  3) Application unfreeze.

  Longhorn provides its own mechanisms for doing the backups and to take snapshots of the persistent volumes. See Longhorn [documentation](https://longhorn.io/docs/latest/snapshots-and-backups/).

  Longhorn does not currently support application consistent volumes snapshots/backups, see [longhorn open issue #2128](https://github.com/longhorn/longhorn/issues/2128).

  Longhorn does support, from release 1.2.4, [Kubernetes CSI snapshot API](https://kubernetes.io/docs/concepts/storage/volume-snapshots/) to take snapshots/backups programmatically. See Longhorn documentation: [CSI Snapshot Support](https://longhorn.io/docs/latest/snapshots-and-backups/csi-snapshot-support/).

  Wiht this functionality application-consistent backups can be orchestrated:

  ```shell
  # Freeze POD filesystem
  kubectl exec pod -- app_feeze_commandç
  # Take snapshot using CSI Snapshot CRDs
  kubectl apply -f volume_snapshot.yml
  # wait till snapshot finish
  # Unfreeze POD filesystem
  kubectl exec pod -- app_unfreeze_command
  ```

  Velero also support CSI snapshot API to take Persistent Volumes snapshots, through CSI provider, Longorn, when backing-up the PODs. See Velero [CSI snapshot support documentation](https://velero.io/docs/latest/csi/).

  Integrating Container Storage Interface (CSI) snapshot support into Velero and Longhorn enables Velero to backup and restore CSI-backed volumes using the [Kubernetes CSI Snapshot feature](https://kubernetes.io/docs/concepts/storage/volume-snapshots/).

  For orchestrating application-consistent backups, Velero supports the definition of [backup hooks](https://velero.io/docs/latest/backup-hooks/), commands to be executed before and after the backup, that can be configured at POD level through annotations.

  So Velero, with its buil-in functionality, CSI snapshot support and backup hooks, is able to perform the orchestration of application-consistent backups. Velero delegates the actual backup/restore of PV to the CSI provider, Longhorn.

  {{site.data.alerts.note}}

  Velero also supports, Persistent Volumes backup/restore procedures using [File System Backup (FSB shortly) or Pod Volume Backup](https://velero.io/docs/latest/file-system-backup/).  [restic](https://restic.net/) or [kopia](https://kopia.io/) can be used to transfer the data using the same S3 backend configured within Velero for backing up the cluster configuration. Velero node agent has to be installed to enable this functionality. FSB support is not enabled when deploying Velero, instead CSI snapshots will be used.

  {{site.data.alerts.end}}

- Minio as backup backend

  All the above mechanisms supports as backup backend, a S3-compliant storage infrastructure. For this reason, open-source project [Minio](https://min.io/) has been deployed for the Pi Cluster.

{{site.data.alerts.note}}

Minio S3 server installed as stand-alone service and configured as described in [Pi Cluster S3 Object Storage Service](/docs/s3-backup/) will be used as backup backend.

{{site.data.alerts.end}}

## OS Filesystem backup with Restic

OS filesystems from different nodes will be backed up using `restic`. As backend S3 Minio server will be used.

Restic installation and backup scheduling tasks have been automated with Ansible developing a role: **ricsanfre.backup**. This role installs restic and configure a systemd service and timer to schedule the backup execution.


### Minio Backupstore configuration

##### Install Minio backup server

See installation instructions in ["PiCluster - S3 Backup Backend (Minio)"](/docs/s3-backup).

##### Configure Restic bucket and user

| User | Bucket |
|:--- |:--- |
|restic | restic |
{: .table .table-white .border-dark }

-   Create bucket for storing Longhorn backups/snapshots

    ```shell
    mc mb ${MINIO_ALIAS}/restic
    ```

-   Add `restic` user using Minio's CLI
    ```shell
    mc admin user add ${MINIO_ALIAS} restic supersecret
    ```

-   Define user policy to grant `restic` user access to backups bucket
    Create file `restic_policy.json` file:

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
                "arn:aws:s3:::restic",
                "arn:aws:s3:::restic/*"
            ]
        }
      ]
    }
    ```

    This policy grants read-write access to `restic` bucket

-   Add access policy to `restic` user:
    ```shell
    mc admin policy add ${MINIO_ALIAS} resitc restic_policy.json
    ```

### Restic installation and backup scheduling configuration

Ubuntu has as part of its distribution a `restic` package that can be installed with `apt` command. restic version is an old one, so it is better to install the last version binary (0.16.5) from github repository

For doing the installation execute the following commands as root user
```shell
cd /tmp
wget https://github.com/restic/restic/releases/download/v0.16.5/restic_0.16.5_linux_[amd64/arm64].bz2
bzip2 -d /tmp/restic_0.16.5_linux_[amd64/arm64].bz2
cp /tmp/restic_0.16.5_linux_[amd64/arm64] /usr/local/bin/restic
chmod 755 /usr/local/bin/restic 
```
### Create restic environment variables files

restic repository info can be passed to `restic` command through environment variables instead of typing in as parameters with every command execution

- Step 1: Create a restic config directory
  
  ```shell
  sudo mkdir /etc/restic
  ```

- Step 2: Create `restic.conf` file containing repository information:

  ```shell
  RESTIC_REPOSITORY=s3:https://<minio_server>:9091/<restic_bucket>
  RESTIC_PASSWORD=<restic_repository_password>
  AWS_ACCESS_KEY_ID=<minio_restic_user>
  AWS_SECRET_ACCESS_KEY=<minio_restic_password>
  ```

- Step 3: Export as enviroment variables content of the file

  ```shell
  export $(grep -v '^#' /etc/restic/restic.conf | xargs -d '\n')
  ```  
  {{site.data.alerts.important}}
  This command need to be executed with any new SSH shell connection before executing any `restic` command. As an alternative that command can be added to the bash profile of the user.
  {{site.data.alerts.end}}

### Copy CA SSL certificates

In case Minio S3 server is using secure communications using a not valid certificate (self-signed or signed with custom CA), restic command must be used with `--cacert <path_to_CA.pem_file` option to let restic validate the server certificate.

Copy CA.pem, used to sign Minio SSL certificate into `/etc/restic/ssl/CA.pem` 

{{site.data.alerts.note}}

In case of self-signed certificates using a custom CA, all `restic` commands detailed below, need to be executed with the following additional argument: `--cacert /etc/restic/ssl/CA.pem`.

{{site.data.alerts.end}}

### Restic repository initialization

restic repository (stored within Minio's S3 bucket) need to be initialized before being used. It need to be done just once.

For initilizing the repo execute:

```shell
restic init
```
For checking whether the repo is initialized or not execute:

```shell
restic init cat config
```
That command shows the information about the repository (file `config` stored within the S3 bucket)

### Execute restic backup

For manually launch backup process, execute
```shell
restic backup <path_to_backup>
```
Backups snapshots can be displayed executing

```shell
restic snapshots
```
### Restic repository maintenance tasks

For checking repository inconsistencies and fixing them

```shell
restic check
```
For applying data retention policy (i.e.: maintain 30 days old snapshots)

```shell
restic forget --keep-within 30d
```
For purging repository old data:

```shell
restic prune
```
### Restic backup schedule and concurrent backups

- Scheduling backup processes

  A systemd service and timer or cron can be used to execute and schedule the backups.

  **ricsanfre.backup** ansible role uses a systemd service and timer to automatically execute the backups. List of directories to be backed up, the scheduling of the backup and the retention policy are passed as role parameters.

- Allowing concurrent backup processes

  A unique repository will be used (unique S3 bucket) to backing up configuration from all cluster servers. Restic maintenace tasks (`restic check`, `restic forget` and `restic prune` operations) acquires an exclusive-lock in the repository, so concurrent backup processes including those operations are mutually lock.

  To avoid this situation, retic repo maintenance tasks are scheduled separatedly from the backup process and executed just from one of the nodes: `gateway`


### Backups policies

The folling directories are backed-up from the cluster nodes

|Path | Exclude patterns|
|:----|:----|
| /etc/ | |
| /home/oss | .cache |
| /root | .cache |
| /home/ansible | .cache .ansible |
{: .table .table-white .border-dark }

Backup policies scheduling

- Daily backup at 03:00 (executed from all nodes)
- Daily restic repo maintenance at 06:00 (executed from `gateway` node)

## Kubernetes Backup with Velero

### Enabling CSI Snapshot support

Kubernetes CSI Snapshot API used by Velero to automate backup of POD's volumes need to be configured for Longhorn CSI.

See how to enable CSI Snapshot using Longhorn in [PiCluster- Longhorn - Configuring CSI Snapshot API](/docs/longhorn/#configuring_csi_snapshot_api)

### Velero installation and configuration

Velero defines a set of Kuberentes' CRDs (Custom Resource Definition) and Controllers that process those CRDs to perform backups and restores.

Velero as well provides a CLI to execute backup/restore commands using Kuberentes API. More details in official documentation, [How Velero works](https://velero.io/docs/latest/how-velero-works/)

The complete backup workflow is the following:

![velero-backup-process](/assets/img/velero-backup-process.png)

As storage provider, Minio will be used. See [Velero's installation documentation using Minio as backend](https://velero.io/docs/latest/contributions/minio/).


### Configuring Minio bucket and user for Velero

Velero requires an object storage bucket to store backups in.

In Minio a dedicated S3 bucket is created for Velero

| User | Bucket |
|:--- |:--- |
|velero | k3s-velero |
{: .table .table-white .border-dark }

-   Create bucket for storing Velero backups

    ```shell
    mc mb ${MINIO_ALIAS}/k3s-velero
    ```

-   Add `longhorn` user using Minio's CLI
    ```shell
    mc admin user add ${MINIO_ALIAS} velero supersecret
    ```

-   Define user policy to grant `velero` user access to backups bucket
    Create file `velero_policy.json` file:


    ```json
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "s3:DeleteObject",
                    "s3:GetObject",
                    "s3:ListMultipartUploadParts",
                    "s3:PutObject",
                    "s3:AbortMultipartUpload"
                ],
                "Resource": [
                    "arn:aws:s3:::k3s-velero/*"
                ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:ListBucket"
                ],
                "Resource": [
                    "arn:aws:s3:::k3s-velero"
                ]
            }
        ]
    }
    ```

    This policy grants read-write access to `k3s-velero` bucket

-   Add access policy to `velero` user:
    ```shell
    mc admin policy add ${MINIO_ALIAS} velero velero_policy.json

See more details in [Velero plugin for aws](https://github.com/vmware-tanzu/velero-plugin-for-aws).

### Installing Velero CLI

Velero CLI need to be installed joinly with kubectl. `velero` uses kubectl config file (`~/.kube/config`) to connect to Kuberentes API.

{{site.data.alerts.important}} k3s config file is located in `/etc/rancher/k3s/k3s.yaml` and it need to be copied into `$HOME/kube/config` in the server where `kubectl` and `velero` is going to be executed.
{{site.data.alerts.end}}

This will be installed in `pimaster`

- Step 1: Download latest stable velero release from https://github.com/vmware-tanzu/velero/releases

- Step 2: Download tar file corresponding to the latest stable version and the host architecture

  ```shell
  velero-<release>-linux-<arch>.tar.gz
  ```
- Step 3: unarchive

  ```shell
  tar -xvf <RELEASE-TARBALL-NAME>.tar.gz -C /dir/to/extract/to
  ```
- Step 4: Copy `velero` binary to `/usr/local/bin`

- Step 5: Customize namespace for operational commands

  CLI commands expects velero to be running in default namespace (`velero`). If namespace is different it must be specified with any execution of the command (--namespace option)

  Velero CLI can be configured to use a different namespace and avoid passing --namespace option with each execution
  ```shell
  velero client config set namespace=<velero_namespace>
  ```

### Installing Velero Kubernetes Service

Installation using `Helm` (Release 3):

- Step 1: Add the vmware-tanzu Helm repository:

  ```shell
  helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
  ```
- Step2: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```
- Step 3: Create namespace

  ```shell
  kubectl create namespace velero
  ```

- Step 4: Create values.yml for Velero helm chart deployment
  
  ```yml
  # AWS backend plugin configuration
  initContainers:
    - name: velero-plugin-for-aws
      image: velero/velero-plugin-for-aws:v1.12.1
      imagePullPolicy: IfNotPresent
      volumeMounts:
        - mountPath: /target
          name: plugins

  # Minio storage configuration
  configuration:
    backupStorageLocation:
      - provider: aws
        bucket: <velero_bucket>
        caCert: <ca.pem_base64> # cat CA.pem | base64 | tr -d "\n"
        config:
          region: eu-west-1
          s3ForcePathStyle: true
          s3Url: https://minio.example.com:9091
          insecureSkipTLSVerify: true
    # Enable CSI snapshot support
    features: EnableCSI
  credentials:
    secretContents:
      cloud: |
        [default]
        aws_access_key_id: <minio_velero_user> # Not encoded
        aws_secret_access_key: <minio_velero_pass> # Not encoded

  # Disable VolumeSnapshotLocation CRD. It is not needed for CSI integration
  snapshotsEnabled: false
  ```

- Step 5: Install Velero in the `velero` namespace with the overriden values

  ```shell
  helm install velero vmware-tanzu/velero --namespace velero -f values.yml
  ```
- Step 6: Confirm that the deployment succeeded, run:

  ```shell
  kubectl -n velero get pod
  ```

- Step 7: Configure VolumeSnapshotClass

  Create manifest file `volume_snapshotclass_velero.yml`

  ```yml
  # CSI VolumeSnapshot Associated With Longhorn Backup
  kind: VolumeSnapshotClass
  apiVersion: snapshot.storage.k8s.io/v1
  metadata:
    name: velero-longhorn-backup-vsc
    labels:
      velero.io/csi-volumesnapshot-class: "true"
  driver: driver.longhorn.io
  deletionPolicy: Retain
  parameters:
    type: bak
  ```
  This VolumeSnapshotClass will be used by Velero to create VolumeSnapshot objects when orchestrating PV backups. The VolumeSnapshotClass to be used, from all the configured in the system, is the one with the label "velero.io/csi-volumesnapshot-class".

  Setting a DeletionPolicy of Retain on the VolumeSnapshotClass will preserve the volume snapshot in the storage system for the lifetime of the Velero backup and will prevent the deletion of the volume snapshot, in the storage system, in the event of a disaster where the namespace with the VolumeSnapshot object may be lost.

  Apply manifest file

  ```shell
  kubectl apply -f volume_snapshotclass_velero.yml
  ```

### Velero chart configuration details

- Velero plugins installation

  The chart configuration deploys the following velero plugin as `initContainers`:
  - `velero-plugin-for-aws` to enable S3 Minio as backup backend.

  
  ```yml
  # AWS backend and CSI plugins configuration
  initContainers:
    - name: velero-plugin-for-aws
      image: velero/velero-plugin-for-aws:v1.12.1
      imagePullPolicy: IfNotPresent
      volumeMounts:
        - mountPath: /target
          name: plugins
  ```

- Enable Velero CSI Snapshots

  ```yml
  configuration:
     # Enable CSI snapshot support
    features: EnableCSI

  # Disable VolumeSnapshotLocation CRD. It is not needed for CSI integration
  snapshotsEnabled: false
  ```
  
- Configure Minio S3 server as backup backend

  ```yml
  # Minio storage configuration
  configuration:
    # Cloud provider being used
    provider: aws
    backupStorageLocation:
      provider: aws
      bucket: <velero_bucket>
      caCert: <ca.pem_base64> # cat CA.pem | base64 | tr -d "\n"
      config:
        region: eu-west-1
        s3ForcePathStyle: true
        s3Url: https://minio.example.com:9091
        insecureSkipTLSVerify: true
  credentials:
    secretContents:
      cloud: |
        [default]
        aws_access_key_id: <minio_velero_user> # Not encoded
        aws_secret_access_key: <minio_velero_pass> # Not encoded

  ```
  
  Minio server connection data (`configuration.backupStorageLocation.config`) ,minio credentials (`credentials.secretContents`), and bucket(`configuration.backupStorageLocation.bucket`) to be used.

  {{site.data.alerts.note}}
   In case of using a self-signed certificate for Minio server, custom CA certificate must be passed as `configuration.backupStorageLocation.caCert` parameter (base64 encoded and removing any '\n' character)
  {{site.data.alerts.end}}

#### GitOps installation

As alternative, for GitOps deployment, instead of putting minio credentials into helm values in plain text, a Secret can be used to store the credentials.

```yml
apiVersion: v1
kind: Secret
metadata:
  name: velero-secret
  namespace: velero
type: Opaque
data:
  cloud: <velero_secret_content | b64encode>
```
Where <velero_secret_content> is:

```
[default]
aws_access_key_id: <minio_velero_user> # Not encoded
aws_secret_access_key: <minio_velero_pass> # Not encoded
```

And the following helm values need to be provided, instead of `credentias.secretContent`

```yml
credentials:
  existingSecret: velero-secret
```

### Testing Velero installation

- Step 1: Deploy a testing application (nginx), which uses a Longhorn's Volume for storing its logs (`/var/logs/nginx`)

  1) Create manifest file: `nginx-example.yml`

  
  ```yml
  ---
  apiVersion: v1
  kind: Namespace
  metadata:
    name: nginx-example
    labels:
      app: nginx
  ---
  kind: PersistentVolumeClaim
  apiVersion: v1
  metadata:
    name: nginx-logs
    namespace: nginx-example
    labels:
      app: nginx
  spec:
    storageClassName: longhorn
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 50Mi
  ---
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: nginx-deployment
    namespace: nginx-example
  spec:
    replicas: 1
    selector:
      matchLabels:
        app: nginx
    template:
      metadata:
        labels:
            app: nginx
        annotations:
            pre.hook.backup.velero.io/container: fsfreeze
            pre.hook.backup.velero.io/command: '["/sbin/fsfreeze", "--freeze", "/var/log/nginx"]'
            post.hook.backup.velero.io/container: fsfreeze
            post.hook.backup.velero.io/command: '["/sbin/fsfreeze", "--unfreeze", "/var/log/nginx"]'
      spec:
        volumes:
          - name: nginx-logs
            persistentVolumeClaim:
              claimName: nginx-logs
        containers:
          - image: nginx:1.17.6
            name: nginx
            ports:
              - containerPort: 80
            volumeMounts:
              - mountPath: "/var/log/nginx"
                name: nginx-logs
                readOnly: false
          - image: ubuntu:bionic
            name: fsfreeze
            securityContext:
              privileged: true
            volumeMounts:
              - mountPath: "/var/log/nginx"
                name: nginx-logs
                readOnly: false
            command:
              - "/bin/bash"
              - "-c"
              - "sleep infinity"
  ---
  apiVersion: v1
  kind: Service
  metadata:
    labels:
        app: nginx
    name: my-nginx
    namespace: nginx-example
  spec:
    ports:
      - port: 80
        targetPort: 80
    selector:
      app: nginx
    type: LoadBalancer
  ```

  {{site.data.alerts.note}}
  Deployment template is annotated so, volume is included in the backup (`backup.velero.io/backup-volumes`) and before doing the backup the filesystem is freeze (`pre.hook.backup.velero.io` and `post.hook.backup.velero.io`)
  {{site.data.alerts.end}}

  2) Apply manifest file `nginx-example.yml`
   
  ```shell
  kubectl apply -f nginx-example.yml
  ```
  3) Connect to nginx pod and create manually a file within `/var/log/nginx`

  ```shell
  kubectl exec <nginx-pod> -n nginx-example -it -- /bin/sh
  # touch /var/log/nginx/testing
  ```

  4) Create a backup for any object included in nginx-example namespace:
  
  ```shell
  velero backup create nginx-backup --include-namespaces nginx-example --wait  
  ```

  5) Simulate a disaster:
  
  ```shell
  kubectl delete namespace nginx-example
  ```

  6) To check that the nginx deployment and service are gone, run:

  ```shell
  kubectl get deployments --namespace=nginx-example
  kubectl get services --namespace=nginx-example
  kubectl get namespace/nginx-example
  ```

  7) Run the restore

  ```shell
  velero restore create --from-backup nginx-backup
  ```
  
  8) Check the status of the restore:

  ```shell
  velero restore get
  ```

  After the restore finishes, the output looks like the following:
  ```
  NAME                          BACKUP         STATUS      STARTED                         COMPLETED                       ERRORS   WARNINGS   CREATED                         SELECTOR
  nginx-backup-20211220180613   nginx-backup   Completed   2021-12-20 18:06:13 +0100 CET   2021-12-20 18:06:50 +0100 CET   0        0          2021-12-20 18:06:13 +0100 CET   <none>
  ```

  9) Check nginx deployment and services are back
  
  ```shell
  kubectl get deployments --namespace=nginx-example
  kubectl get services --namespace=nginx-example
  kubectl get namespace/nginx-example
  ```

  10) Connect to the restored pod and check that `testing` file is in `/var/log/nginx`

### Schedule a periodic full backup

Set up daily full backup can be on with velero CLI

```shell
velero schedule create full --schedule "0 4 * * *"
```
Or creating a 'Schedule' [kubernetes resource](https://velero.io/docs/latest/api-types/schedule/):

```yml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: full
  namespace: velero
spec:
  schedule: 0 4 * * *
  template:
    hooks: {}
    includedNamespaces:
    - '*'
    includedResources:
    - '*'
    includeClusterResources: true
    metadata:
      labels:
        type: 'full'
        schedule: 'daily'
    ttl: 720h0m0s
```

### Observability

#### Integration with Kube-prom-stack


`ServiceMonitoring`, Prometheus Operator's CRD,  resource can be automatically created so Kube-Prometheus-Stack is able to automatically start collecting metrics from fluentf.

Add following to the helm chart values.yaml file,

```yaml
# Settings for Velero's prometheus metrics. Enabled by default.
metrics:
  enabled: true
  scrapeInterval: 30s
  scrapeTimeout: 10s
  serviceMonitor:
    enabled: true
  prometheusRule:
    enabled: true
```

Corresponding Prometheus Operator's resource, `ServiceMonitor` will be created, so Kube-Prometheus-Stack can automatically start scraping metrics endpoint.

#### Grafana Dashboards

Velero dashboard sample can be donwloaded from [grafana.com](https://grafana.com): [dashboard id: 11055](https://grafana.com/grafana/dashboards/11055)

The following configuration can be added to Grafana's Helm Chart so a MinIO's dashboard provider can be created and dashboards can be automatically downloaded from GitHub repository

```yaml
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: infrastructure
        orgId: 1
        folder: Infrastructure
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/infrastructure-folder
# Dashboards
dashboards:
  infrastructure:
    velero:
      # https://grafana.com/grafana/dashboards/11055-kubernetes-addons-velero-stats/
      # renovate: depName="Velero Dashboard"
      gnetId: 11055
      revision: 2
      datasource:
        - { name: DS_PROMETHEUS, value: Prometheus }


## References

- [K3S Backup/Restore official documentation](https://rancher.com/docs/k3s/latest/en/backup-restore/)
- [Longhorn Backup/Restore official documentation](https://longhorn.io/docs/latest/snapshots-and-backups/)
- [Bare metal Minio documentation](https://docs.min.io/minio/baremetal/)
- [Create a Multi-User MinIO Server for S3-Compatible Object Hosting](https://www.civo.com/learn/create-a-multi-user-minio-server-for-s3-compatible-object-hosting)
- [Backup Longhorn Volumes to a Minio S3 bucket](https://www.civo.com/learn/backup-longhorn-volumes-to-a-minio-s3-bucket)

