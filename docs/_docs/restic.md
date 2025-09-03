---
title: OS Filesystem Backup (Restic)
permalink: /docs/restic/
description: How to implement backup and restore of OS filesystem in Kubernetes PI Cluster.
last_modified_at: "25-06-2025"
---



Operating System configuration files should be backed up so configuration at OS level can be restored.

[Restic](https://restic.net) can be used to perform this OS filesystem backup. Restic provides a fast and secure backup program that can be intregrated with different storage backends, including Cloud Service Provider Storage services (AWS S3, Google Cloud Storage, Microsoft Azure Blob Storage, etc). It also supports opensource S3 [Minio](https://min.io).

OS filesystems from different nodes of the cluster will be backed up using `restic`. As backend S3 Minio server will be used.


![restic-architecture](/assets/img/restic-architecture.png)


Restic installation and backup scheduling tasks can be automated with Ansible using [**ricsanfre.backup**](https://github.com/ricsanfre/ansible-role-backup). This role installs `restic` and configure a `systemd` service and timer to schedule the backup execution. Also a backup policy indicating which file paths to include in the backup can be specified.


## Minio Backupstore configuration

First S3 backupstore need to be configured

### Install Minio backup server

See installation instructions in ["PiCluster - S3 Backup Backend (Minio)"](/docs/s3-backup/).

### Configure Restic bucket and user

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
    mc admin policy add ${MINIO_ALIAS} restic restic_policy.json
    ```

## Restic Installation

### Binary installation

Ubuntu has as part of its distribution a `restic` package that can be installed with `apt` command. restic version is an old one, so it is better to install the latest version binary from github repository.


-   Step 1. Download and install binary
    ```shell
    cd /tmp
    wget https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_0.16.5_linux_${ARCH}.bz2
    bzip2 -d /tmp/restic_${RESTIC_VERSION}_linux_${ARCH}.bz2
    sudo cp /tmp/restic_${RESTIC_VERSION}_linux_${ARCH} /usr/local/bin/restic
    sudo chmod 755 /usr/local/bin/restic 
    ```
    where:
    -   `${ARCH}` is `amd64` or `amr64` depending on the server architecture.
    -   `${RESTIC_VERSION}` is the version to be donwloaded


### Create restic environment variables files

`restic` repository info can be passed to `restic` command through environment variables instead of typing in as parameters with every command execution

-   Step 1: Create a restic config directory

    ```shell
    sudo mkdir /etc/restic
    ```

-   Step 2: Create `restic.conf` file containing repository information:

    ```shell
    RESTIC_REPOSITORY=s3:https://${MINIO_SERVER}:9091/restic
    RESTIC_PASSWORD=${RESTIC_REPOSITORY_PASSWORD}
    AWS_ACCESS_KEY_ID=S{MINIO_RESTIC_USER}
    AWS_SECRET_ACCESS_KEY=S{MINIO_RESTIC_PASSWORD}
    ```
  
    In the previos file the following variables (${var}) need to be replaced by actual values:

    -   `${MINIO_SERVER}` FQDN of the Minio Server
    -   `${RESTIC_REPOSITORY_PASSWORD}`: repository password to initialize and access the restic repository

-   Step 3: Export as enviroment variables, the content of the file

    ```shell
    export $(grep -v '^#' /etc/restic/restic.conf | xargs -d '\n')
    ```  
    {{site.data.alerts.important}}
    This command need to be executed with any new SSH shell connection to the server before executing any `restic` command. As an alternative that command can be added to the bash profile of the user.
    {{site.data.alerts.end}}

### Copy CA SSL certificates

In case Minio S3 server is using secure communications using a not trusted certificate (self-signed or signed with custom CA), restic command must be used with `--cacert <path_to_CA.pem_file` option to let restic validate the server certificate.

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

## Restic Operation

### Execute restic backup

For manually launch backup process, execute
```shell
restic backup ${FILESYSTEM_PATH} --exclude ${EXCLUDE_PATTERN}
```
where:

-   `${FILESYSTEM_PATH}` is the filesystem path to backup
-   `${EXCLUDE_PATTERN}` contains a regular expression matching the files that need to be excluded from the backup


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
