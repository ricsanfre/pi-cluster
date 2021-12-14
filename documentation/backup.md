# Cluster Backup

It is needed to implement a backup strategy for the K3S cluster. This backup strategy should, at least, contain a backup infrastructure, and backup and restore procedures for OS basic configuration files, K3S cluster configuration and Longhorn Persistent Volumes.

- OS configuration files backup

    Some OS configuration files should be backed up in order to being able to restore configuration at OS level.
    For doing so, [Restic](restic.net) can be used. Restic provides a fast and secure backup program that can be intregrated with different storage backends, including Cloud Service Provider Storage services (AWS S3, Google Cloud Storage, Microsoft Azure Blob Storage, etc). It also supports opensource S3 [Minio](min.io). 


- K3S cluster configuration backup and restore.

    This could be achieve backing up and restoring the etcd Kubernetes cluster database as official [documentation](https://rancher.com/docs/k3s/latest/en/backup-restore/) states. The supported backup procedure is only supported in case `etcd` database is deployed (by default K3S use a sqlite databse)

    As an alternative [Velero](velero.io), a CNCF project, can be used to backup and restore kubernetes cluster configuration. Velero is kubernetes-distribution agnostic since it uses Kubernetes API for extracting and restoring the configuration, instead relay on backups/restores of etcd database.

    Since for the backup and restore is using standard Kubernetes API, Velero can be used as a tool for migrating the configuration from one kubernetes cluster to another having a differnet kubernetes flavor. From K3S to K8S for example.

    Velero can be intregrated with different storage backends, including Cloud Service Provider Storage services (AWS S3, Google Cloud Storage, Microsoft Azure Blob Storage, etc). It also supports opensource S3 [Minio](min.io). 

    Since Velero is a most generic way to backup any Kuberentes cluster (not just K3S) it will be used to implement my cluster K3S backup.

- Longhorn Persistent Volumes backup and restore.

    Velero supports, Persistent Volumes backup/restore procedures using `restic` (https://velero.io/docs/v1.7/restic/), but it is a beta feature.

    Longhorn provides its own mechanisms for doing the backups and to take snapshots of the persistent volumes. See Longhorn [documentation](https://longhorn.io/docs/1.2.2/snapshots-and-backups/).

    For implementing the backup is needed to define a backup target, external storage system where longhorn volumes are backed to and restore from. Longhorn support NFS and S3 based backup targets. [Minio](min.io) can be used as backend.


All the above mechanisms supports as backup backend, a S3-compliant storage infrastructure. For this reason, open-source project [Minio](https://min.io/)


The backup architecture is the following

[TBD: Image Backup architecture: Minio, Velero, etc]

## Backup Infrastructure

For installing Minio S3 storage server, `node1` will be used. `node1` has attached a SSD Disk of 480 GB that is not being used by Longhorn Distributed Storage solution. Longhorn storage solution is not deployed in k3s master node and thus storage replicas are only using storage resources of `node2`, `node3` and `node4`.

## Installation of S3 Storage Server (Minio)

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
    - Self-signed SSL certificates stored in /etc/minio/ssl.

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


- Minio Buckets
    - Longhorn Backup: `longhorn`

- Minio Users and ACLs
    - `longhorn` with read-write access to `longhorn` bucket.



## Longhorn backup


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
    AWS_CERT: <base64_encoded_minio_ssl_pem> # minio_ssl_certificate
  ```
  For encoding the different access paramenters the following commands can be used:

    echo -n minio_url | base64
    echo -n minio_access_key_id | base64
    echo -n minio_secret_access_key | base64
    cat minio-ssl.pem | base64

- Apply manifest file

   kubectl apply -f longhorn-s3-secret.yml

### Configure Longhorn backup target

Go to the Longhorn UI. In the top navigation bar, click Settings. In the Backup section, set Backup Target to:

    s3://<bucket-name>@<minio-s3-region>/

Following my configuration it should be:

    s3//longhorn@eu-west-1/

> NOTE: Make sure that you have / at the end, otherwise you will get an error.


In the Backup section set Backup Target Credential Secret to the secret resource created before

    minio-secret

## Target can be automatically configured when deploying helm chart

Additional overriden values can be provided to helm chart deployment to configure S3 target.

```yml
defaultSettings:
  backupTarget: s3://longhorn@eu-west-1/
  backupTargetCredentialSecret: minio-secret
```
## References

[1] K3S Backup/Restore official documentation (https://rancher.com/docs/k3s/latest/en/backup-restore/)
[2] Longhorn Backup/Restore official documentation (https://longhorn.io/docs/1.2.2/snapshots-and-backups/)
[3] Bare metal Minio documentation (https://docs.min.io/minio/baremetal/)
[4] Create a Multi-User MinIO Server for S3-Compatible Object Hosting (https://www.civo.com/learn/create-a-multi-user-minio-server-for-s3-compatible-object-hosting)
[5] Backup Longhorn Volumes to a Minio S3 bucket (https://www.civo.com/learn/backup-longhorn-volumes-to-a-minio-s3-bucket)
