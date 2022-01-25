---
title: Backup & Restore
permalink: /docs/backup/
redirect_from: /docs/backup.md
---

## Backup Architecture and Design

It is needed to implement a backup strategy for the K3S cluster. This backup strategy should, at least, contains a backup infrastructure, and backup and restore procedures for OS basic configuration files, K3S cluster configuration and PODs Persistent Volumes.

The backup architecture is the following:

![picluster-backup-architecture](/assets/img/pi-cluster-backup-architecture.png)

- OS filesystem backup

    Some OS configuration files should be backed up in order to being able to restore configuration at OS level.
    For doing so, [Restic](restic.net) can be used. Restic provides a fast and secure backup program that can be intregrated with different storage backends, including Cloud Service Provider Storage services (AWS S3, Google Cloud Storage, Microsoft Azure Blob Storage, etc). It also supports opensource S3 [Minio](min.io). 


- K3S cluster configuration backup and restore.

    This could be achieve backing up and restoring the etcd Kubernetes cluster database as official [documentation](https://rancher.com/docs/k3s/latest/en/backup-restore/) states. The supported backup procedure is only supported in case `etcd` database is deployed (by default K3S use a sqlite databse)

    As an alternative [Velero](velero.io), a CNCF project, can be used to backup and restore kubernetes cluster configuration. Velero is kubernetes-distribution agnostic since it uses Kubernetes API for extracting and restoring the configuration, instead relay on backups/restores of etcd database.

    Since for the backup and restore is using standard Kubernetes API, Velero can be used as a tool for migrating the configuration from one kubernetes cluster to another having a differnet kubernetes flavor. From K3S to K8S for example.

    Velero can be intregrated with different storage backends, including Cloud Service Provider Storage services (AWS S3, Google Cloud Storage, Microsoft Azure Blob Storage, etc). It also supports opensource S3 [Minio](min.io). 

    Since Velero is a most generic way to backup any Kuberentes cluster (not just K3S) it will be used to implement my cluster K3S backup.

- PODs Persistent Volumes backup and restore.

    Velero supports, Persistent Volumes backup/restore procedures using `restic` as backup engine (https://velero.io/docs/v1.7/restic/) using the same S3 backend configured within Velero for backing up the cluster configuration. 

    Longhorn also provides its own mechanisms for doing the backups and to take snapshots of the persistent volumes. See Longhorn [documentation](https://longhorn.io/docs/1.2.2/snapshots-and-backups/). For configuring the backup in Longhorn is needed to define a backup target, external storage system where longhorn volumes are backed to and restore from. Longhorn support NFS and S3 based backup targets. [Minio](min.io) can be used as backend.

    Applications running in Kubernetes needs to be backed up in a consistent state. It means that before copying the filesystem is it required to freeze the application and make it flush all the pending changes to disk before making the copy. Once the backup is finished, the application can be unfreeze.
      1) Application Freeze and flush to disk
      2) Filesystem level backup
      3) Application unfreeze.

    Velero supports the definition of [backup hooks](https://velero.io/docs/v1.7/backup-hooks/), commands to be executed before and after the backup, that can be configured at POD level through annotations, 

    Longhorn does not currently support application consistent volumes snapshots/backups, see open [issue](https://github.com/longhorn/longhorn/issues/2128). 
    Enabling within K3S cluster the new Kubernetes CSI feature: [Volume Snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/) allows to programmatically create backups and so orchestrate consistent backups:

       kubectl exec pod -- app_feeze_command
       kubectl apply -f volume_snapshot.yml
       # wait till snapshot finish
       kubectl exec pod -- app_unfreeze_command

    This CSI feature is supported by Longhorn. See Longhorn documentation: [CSI Snapshot Support](https://longhorn.io/docs/1.2.2/snapshots-and-backups/csi-snapshot-support/create-a-backup-via-csi/). K3S currently does not come with a preintegrated Snapshot Controller, but external controller could be used (https://github.com/kubernetes-csi/external-snapshotter).

    > NOTE: CSI Snaphot Support is not yet supported in current pi-cluster release. To be implemented and tested in the future 

    Both mechanism for backing up Persistent Volumes (Velero and Longhorn) will be enabled in my cluster.

All the above mechanisms supports as backup backend, a S3-compliant storage infrastructure. For this reason, open-source project [Minio](https://min.io/) will be deployed.

## Backup server hardware infrastructure

For installing Minio S3 storage server, `node1` will be used. `node1` has attached a SSD Disk of 480 GB that is not being used by Longhorn Distributed Storage solution. Longhorn storage solution is not deployed in k3s master node and thus storage replicas are only using storage resources of `node2`, `node3` and `node4`.

## Minio S3 Object Storage Server

Official [documentation](https://docs.min.io/minio/baremetal/installation/deploy-minio-standalone.html) can be used for installing stand-alone Minio Server in bare-metal environment. 

Minio can be also installed as a Kuberentes service, to offer S3 storage service to Cluster users. Since I want to use Minio Server for backing-up/restoring the cluster itself, I will go with a bare-metal installation.

For a more secured and multi-user Minio installation the instructions of this [post](https://www.civo.com/learn/create-a-multi-user-minio-server-for-s3-compatible-object-hosting) can be used

Minio installation and configuration tasks have been automated with Ansible developing a role: **ricsanfre.minio**. This role, installs Minio Server and Minio Client and automatically create S3 buckets, and configure users and ACLs for securing the access.

### Minio Configuration

- Minio Server configuration parameters:
    - Minio Server API Port: 9091
    - Minio Console Port: 9092
    - Minio Storage data dir: `/storage/minio`
    - Minio Site Region: `eu-west-1`
    - SSL certificates stored in /etc/minio/ssl.

    Minio Enviroment variables stored in `/etc/minio/minio.conf` file:
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
    ```

    Minio server start-up command is:

        /usr/local/minio server $MINIO_OPTS $MINIO_VOLUMES

- Minio SSL certificates

  `restic` backup to a S3 Object Storage backend using self-signed certificates does not work (See issue [#26](https://github.com/ricsanfre/pi-cluster/issues/26)). However, it works if SSL certificates are signed using a custom CA.

  1) Create a self-signed CA key and self-signed certificate
  2) Create a SSL certificate for Minio server signed using the custom CA
  3) Copy public certificate as `/etc/minio/ssl/public.crt`
  4) Copy private key as `/etc/minio/ssl/private.key`
  5) Restart minio server.

> NOTE: Certificates creation has been automated with Ansible using openssl module.

- Minio Buckets
    - Longhorn Backup: `k3s-longhorn`
    - Velero Backup: `k3s-velero`
    - OS backup: `restic`

  Buckets can be created using Minio's CLI (`mc`)
  
      mc mb <minio_alias>/<bucket_name> 

  Where: <minio_alias> is the mc's alias connection to Minio Server using admin user credentials

      mc alias set minio_alias <minio_url> <minio_root_user> <minio_root_password>


- Minio Users and ACLs
    - `longhorn` with read-write access to `k3s-longhorn` bucket.
    - `velero` with read-write access to `k3s-velero` bucket. 
    - `restic` with read-write access to `restic` bucket
  
  Users can be created usinng Minio's CLI

      mc admin user add <minio_alias> <user_name> <user_password>

  Access policies to the different buckets can be assigned to the different users using the command:

      mc admin policy add <minio_alias> <user_name> user_policy.json

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
  granting read-write access to `bucket_name`

## OS Filesystem backup with Restic

OS filesystems from different nodes will be backed up using `restic`. As backend S3 Minio server will be used.

Restic installation and backup scheduling tasks have been automated with Ansible developing a role: **ricsanfre.backup**. This role installs restic and configure a systemd service and timer to schedule the backup execution.

### Restic installation and backup scheduling configuration

Ubuntu has as part of its distribution a `restic` package that can be installed with `apt` command. restic version is an old one (0.9), so it is better to install the last version binary (0.12.1) from github repository

For doing the installation execute the following commands as root user
   ```
   cd /tmp
   wget https://github.com/restic/restic/releases/download/v0.12.1/restic_0.12.1_linux_arm64.bz2
   bzip2 -d /tmp/restic_0.12.1_linux_arm64.bz2
   cp /tmp/restic_0.12.1_linux_arm64 /usr/local/bin/restic
   chmod 755 /usr/local/bin/restic 
   ```
### Create restic environment variables files

restic repository info can be passed to `restic` command through environment variables instead of typing in as parameters with every command execution

- Step 1: Create a restic config directory
  
  ```
  sudo mkdir /etc/restic
  ```

- Step 2: Create `restic.conf` file containing repository information:

  ```
  RESTIC_REPOSITORY=s3:https://<minio_server>:9091/<restic_bucket>
  RESTIC_PASSWORD=<restic_repository_password>
  AWS_ACCESS_KEY_ID=<minio_restic_user>
  AWS_SECRET_ACCESS_KEY=<minio_restic_password>
  ```

- Step 3: Export as enviroment variables content of the file

  ```
  export $(grep -v '^#' /etc/restic/restic.conf | xargs -d '\n')
  ```  

  > NOTE: This command need to be executed with any new SSH shell connection before executing any `restic` command. As an alternative that command can be added to the bash profile of the user.

### Copy CA SSL certificates

In case Minio S3 server is using secure communications using a not valid certificate (self-signed or signed with custom CA), restic command must be used with `--cacert <path_to_CA.pem_file` option to let restic validate the server certificate. 

Copy CA.pem, used to sign Minio SSL certificate into `/etc/restic/ssl/CA.pem` 

### Restic repository initialization

restic repository (stored within Minio's S3 bucket) need to be initialized before being used. It need to be done just once.

For initilizing the repo execute:

    restic --cacert /etc/restic/ssl/CA.pem init

For checking whether the repo is initialized or not execute:

    restic --cacert /etc/restic/ssl/CA.pem init cat config

That command shows the information about the repository (file `config` stored within the S3 bucket)

### Execute restic backup

For manually launch backup process, execute

    restic --cacert /etc/restic/ssl/CA.pem backup <path_to_backup>

Backups snapshots can be displayed executing

    restic --cacert /etc/restic/ssl/CA.pem snapshots

### Restic repository maintenance tasks

For checking repository inconsistencies and fixing them

    restic --cacert /etc/restic/ssl/CA.pem check

For applying data retention policy (i.e.: maintain 30 days old snapshots)

    restic --cacert /etc/restic/ssl/CA.pem forget --keep-within 30d

For purging repository old data:

    restic --cacert /etc/restic/ssl/CA.pem prune

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
|----|----|
| /etc/ | |
| /home/oss | .cache |
| /root | .cache |
| /home/ansible | .cache .ansible |
{: .table }

Backup policies scheduling

- Daily backup at 03:00 (executed from all nodes)
- Daily restic repo maintenance at 06:00 (executed from `gateway` node)

## Kubernetes Backup with Velero

### Velero installation and configuration

Velero defines a set of Kuberentes' CRDs (Custom Resource Definition) and Controllers that process those CRDs to perform backups and restores.

Velero as well provides a CLI to execute backup/restore commands using Kuberentes API. More details in official [documentation](https://velero.io/docs/v1.7/how-velero-works/)

The complete backup workflow is the following:

![velero-backup-process](/assets/img/velero-backup-process.png)

As storage provider, Minio will be used. See specific installation documentation using Minio as backend [here](https://velero.io/docs/v1.7/contributions/minio/).


### Configuring Minio bucket and user for Velero

elero requires an object storage bucket to store backups in. In Minio a dedicated S3 bucket is created for Velero (name: `k3s-velero`) 

A specific Minio user `velero` is configured with specic access policy to grant the user access to the bucket.

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

See more details in Velero's documentation about [aws plugin](https://github.com/vmware-tanzu/velero-plugin-for-aws)


### Installing Velero CLI

Velero CLI need to be installed joinly with kubectl. `velero` uses kubectl config file (`~/.kube/config`) to connect to Kuberentes API.

> NOTE: k3s config file is located in `/etc/rancher/k3s/k3s.yaml` and it need to be copied into `$HOME/kube/config` int the server where `kubectl` and `velero` is going to be executed.

This will be installed in `node1`

- Step 1: Download latest stable velero release from https://github.com/vmware-tanzu/velero/releases

- Step 2: Download tar file corresponding to the latest stable version and the host architecture

    velero-<release>-linux-<arch>.tar.gz

- Step 3: unarchive

    tar -xvf <RELEASE-TARBALL-NAME>.tar.gz -C /dir/to/extract/to

- Step 4: Copy `velero` binary to `/usr/local/bin`

- Step 5: Customize namespace for operational commands

  CLI commands expects velero to be running in default namespace (`velero`). If namespace is different it must be specified with any execution of the command (--namespace option)

  Velero CLI can be configured to use a different namespace and avoid passing --namespace option with each execution

    velero client config set namespace=<velero_namespace>

### Installing Velero Kubernetes Service

Installation using `Helm` (Release 3):

- Step 1: Add the vmware-tanzu Helm repository:
    ```
    helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
    ```
- Step2: Fetch the latest charts from the repository:
    ```
    helm repo update
    ```
- Step 3: Create namespace
    ```
    kubectl create namespace velero-system
    ```
- Step 4: Create values.yml for Velero helm chart deployment
  
    ```yml
    initContainers:
        - name: velero-plugin-for-aws
          image: velero/velero-plugin-for-aws:v1.3.0
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - mountPath: /target
              name: plugins
      # Upgrading CRDs is causing issues
      upgradeCRDs: false
      # Use a kubectl image supporting ARM64
      # bitnami default is not suppporting it
      # kubectl:
      #   image:
      #     repository: rancher/kubectl
      #     tag: v1.21.5
      # Disable volume snapshots. Longhorn deals with them
      snapshotsEnabled: false
      # Deploy restic for backing up volumes
      deployRestic: true
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

> NOTE 1: UpgradeCRDs option causes installation problems, since the job created for upgrading the CRDs uses kubectl docker image from bitnami. Bitnami is not supporting ARM64 docker images. See bitnami's repository open [issue](https://github.com/bitnami/bitnami-docker-kubectl/issues/22).
Changing it to a ARM64 docker image (i.e Rancher) does not solve the issue either.

> NOTE 2: Custom CA certificate must be passed as `caCert` parameter (base64 encoded and removing any '\n' character)

 
- Step 5: Install Veleor in the velero-system namespace with the overriden values
    ```
    helm install velero vmware-tanzu/velero --namespace velero-system -f values.yml
    
    ```
- Step 6: Confirm that the deployment succeeded, run:
    ```
    kubectl -n velero-system get pod
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
            backup.velero.io/backup-volumes: nginx-logs
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

   > NOTE: Deployment template is annotated so, volume is included in the backup (`backup.velero.io/backup-volumes`) and before doing the backup the filesystem is freeze (`pre.hook.backup.velero.io` and `post.hook.backup.velero.io`)
   

  2) Apply manifest file `nginx-example.yml`

    kubectl apply -f nginx-example.yml

  3) Connect to nginx pod and create manually a file within `/var/log/nginx`

    kubectl exec <nginx-pod> -n nginx-example -it -- /bin/sh

    # touch /var/log/nginx/testing
  
  4) Create a backup for any object that matches the app=nginx label selector:

    velero backup create nginx-backup --selector app=nginx 

  5) Simulate a disaster:

    kubectl delete namespace nginx-example

  6) To check that the nginx deployment and service are gone, run:

    kubectl get deployments --namespace=nginx-example
    kubectl get services --namespace=nginx-example
    kubectl get namespace/nginx-example

  7) Run the restore

    velero restore create --from-backup nginx-backup
   
  8) Check the status of the restore:

    velero restore get

  After the restore finishes, the output looks like the following:
  ```
  NAME                          BACKUP         STATUS      STARTED                         COMPLETED                       ERRORS   WARNINGS   CREATED                         SELECTOR
  nginx-backup-20211220180613   nginx-backup   Completed   2021-12-20 18:06:13 +0100 CET   2021-12-20 18:06:50 +0100 CET   0        0          2021-12-20 18:06:13 +0100 CET   <none>
  ```

  9) Check nginx deployment and services are back

    kubectl get deployments --namespace=nginx-example
    kubectl get services --namespace=nginx-example
    kubectl get namespace/nginx-example

  10) Connect to the restored pod and check that `testing` file is in `/var/log/nginx`

### Schedule a periodic full backup

Set up daily full backup can be on with velero CLI

    velero schedule create full --schedule "0 4 * * *"

Or creating a 'Schedule' kubernetes resource (https://velero.io/docs/v1.7/api-types/schedule/):

```yml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: full
  namespace: velero-system
spec:
  schedule: 0 4 * * *
  template:
    hooks: {}
    includedNamespaces:
    - '*'
    included_resources:
    - '*'
    includeClusterResources: true
    metadata:
      labels:
        type: 'full'
        schedule: 'daily'
    ttl: 720h0m0s
```

## Longhorn backup configuration


### Minio end-point credentials

Create kuberentes secret resource containing Minio end-point access information and credentials

- Create manifest file `longhorn-minio-secret.yml`

  ```yml

    apiVersion: v1
    kind: Secret
    metadata:
    name: minio-secret
    namespace: longhorn-system
    type: Opaque
    data:
    AWS_ACCESS_KEY_ID: <base64_encoded_longhorn-minio-access-key> # longhorn
    AWS_SECRET_ACCESS_KEY: <base64_encoded_longhorn-minio-secret-key> # longhornpass
    AWS_ENDPOINTS: <base64_encoded_mino-end-point> # https://minio-service.default:9000
    AWS_CERT: <base64_encoded_minio_ssl_pem> # minio_ssl_certificate, containing complete chain, including CA
  ```
  For encoding the different access paramenters the following commands can be used:

    echo -n minio_url | base64
    echo -n minio_access_key_id | base64
    echo -n minio_secret_access_key | base64
    cat minio-ssl.pem ca.pem | base64 | tr -d "\n"

> NOTE 1: As the command shows, SSL certificates in the validation chain must be concatenated and "\n" characters from the base64 encoded SSL pem must be removed.

- Apply manifest file

   kubectl apply -f longhorn-s3-secret.yml

### Configure Longhorn backup target

Go to the Longhorn UI. In the top navigation bar, click Settings. In the Backup section, set Backup Target to:

    s3://<bucket-name>@<minio-s3-region>/
    

> NOTE: Make sure that you have / at the end, otherwise you will get an error.

In the Backup section set Backup Target Credential Secret to the secret resource created before

    minio-secret

![longhorn-backup-settings](/assets/img/longhorn_backup_settings.png)

## Target can be automatically configured when deploying helm chart

Additional overriden values can be provided to helm chart deployment to configure S3 target.

```yml
defaultSettings:
  backupTarget: s3://longhorn@eu-west-1/
  backupTargetCredentialSecret: minio-secret
```

## Scheduling longhorn volumes backup

A Longhorn recurring job can be created for scheduling periodic backups/snapshots of volumes.
See details in [documentation](https://longhorn.io/docs/1.2.3/snapshots-and-backups/scheduling-backups-and-snapshots/).

- Create `RecurringJob` manifest resource

  ```yml
  ---
  apiVersion: longhorn.io/v1beta1
  kind: RecurringJob
  metadata:
    name: backup
    namespace: longhorn-system
  spec:
    cron: "0 5 * * *"
    task: "backup"
    groups:
    - default
    retain: 2
    concurrency: 2
    labels:
      type: 'full'
      schedule: 'daily'
  ```

  This will create  recurring backup job for `default`. Longhorn will automatically add a volume to the default group when the volume has no recurring job.

- Apply manifest file
    
      kubectl apply -f recurring_job.yml

## References

[1] K3S Backup/Restore official documentation (https://rancher.com/docs/k3s/latest/en/backup-restore/)
[2] Longhorn Backup/Restore official documentation (https://longhorn.io/docs/1.2.3/snapshots-and-backups/)
[3] Bare metal Minio documentation (https://docs.min.io/minio/baremetal/)
[4] Create a Multi-User MinIO Server for S3-Compatible Object Hosting (https://www.civo.com/learn/create-a-multi-user-minio-server-for-s3-compatible-object-hosting)
[5] Backup Longhorn Volumes to a Minio S3 bucket (https://www.civo.com/learn/backup-longhorn-volumes-to-a-minio-s3-bucket)

