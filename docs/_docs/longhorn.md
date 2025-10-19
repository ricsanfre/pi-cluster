---
title: Distributed Block Storage (Longhorn)
permalink: /docs/longhorn/
description: How to deploy distributed block storage solution based on Longhorn in our Pi Kubernetes Cluster.
last_modified_at: "23-03-2025"
---

K3s comes with a default [Local Path Provisioner](https://rancher.com/docs/k3s/latest/en/storage/) that allows creating a PersistentVolumeClaim backed by host-based storage. This means the volume is using storage on the host where the pod is located. If the POD need to be started on a different node it won't be able to access the data.

A distributed block storage is needed to handle this issue. With distributed block storage, the storage is decouple from the pods, and the PersistentVolumeClaim can be mounted to the pod regardless of where the pod is running.

[Longhorn](https://longhorn.io/) is a distributed block storage system for Kubernetes. Lightweight, reliable and easy-to-use can be used as an alternative to Rook/Cephs. It is opensource software initially developed by Rancher Labs supporting AMD64 and ARM64 architectures that can be easily integrated with K3S.

## LongHorn Installation

### Installation requirements

#### Kubernetes version requirements
- A container runtime compatible with Kubernetes (Docker v1.13+, containerd v1.3.7+, etc.)
- Kubernetes >= v1.21
- Mount propagation must be supported[^2]

#### Installing open-iscsi

LongHorn requires that `open-iscsi` package has been installed on all the nodes of the Kubernetes cluster, and `iscsid` daemon is running on all the nodes.[^3]

Longhorn uses internally iSCSI to expose the block device presented by the Longhorn volume to the kuberentes pods. So the iSCSI initiator need to be setup on each node. Longhorn, acting as iSCSI Target, exposes Longhorn Volumes that are discovered by the iSCSI Initiator running on the node as `/dev/longhorn/` block devices. For implementation details see [Longhorn engine document](https://github.com/longhorn/longhorn-engine).

![longhorn](https://github.com/longhorn/longhorn-engine/raw/master/overview.png)


Check than  `open-iscsi` is installed, and the `iscsid` daemon is running on all the nodes. This is necessary, since Longhorn relies on `iscsiadm` on the host to provide persistent volumes to Kubernetes.

- Install open-iscsi package

  ```shell
  sudo apt get install open-iscsi
  ```

- Ensure `iscsid` daemon is up and running and is started on boot

  ```shell
  sudo systemclt start iscsid
  sudo systemctl enable iscsid
  ```


#### Installing NFSv4 Client
In Longhorn system, backup feature requires NFSv4, v4.1 or v4.2, and ReadWriteMany (RWX) volume feature requires NFSv4.1.[^4]

Make sure the client kernel support is enabled on each Longhorn node.

- Check `NFSv4.1` support is enabled in kernel
    
  ```shell
  cat /boot/config-`uname -r`| grep CONFIG_NFS_V4_1
  ```
    
- Check `NFSv4.2` support is enabled in kernel
    
  ```shell
  cat /boot/config-`uname -r`| grep CONFIG_NFS_V4_2
  ```

- Installl NFSv4 client in all nodes

  ```shell
  sudo apt install nfs-common
  ```


#### Installing Cryptsetup and LUKS

Longhorn supports Volume encryption.

[Cryptsetup](https://gitlab.com/cryptsetup/cryptsetup) is an open-source utility used to conveniently set up `dm-crypt` based device-mapper targets and Longhorn uses [LUKS2](https://gitlab.com/cryptsetup/cryptsetup#luks-design) (Linux Unified Key Setup) format that is the standard for Linux disk encryption to support volume encryption.

To use encrypted volumes, `dm_crypt` kernel module has to be loaded and that `cryptsetup` is installed on all worker nodes.[^5]

- Install `cryptsetup` package
  ```shell
  sudo apt install cryptsetup 
  ```

- Load `dm_crypt` kernel module

  ```shell
  sudo modprobe -v dm_crypt 
  ```

  Make that change persisent across reboots

  ```shell
  echo "dm_crypt" | sudo tee /etc/modules-load.d/dm_crypt.conf
  ```


#### Installing Device Mapper Userspace Tool

The device mapper is a framework provided by the Linux kernel for mapping physical block devices onto higher-level virtual block devices. It forms the foundation of the `dm-crypt` disk encryption and provides the linear dm device on the top of v2 volume.[^6]

Ubuntu 24.04 sever includes this package by default.

To install the package:

```shell
sudo apt install dmsetup
```

#### Longhorn issues with Multipath

Multipath running on the storage nodes might cause problems when starting Pods using Longhorn volumes ("Error messages of type: volume already mounted").

To prevent the multipath daemon from adding additional block devices created by Longhorn, Longhorn devices must be blacklisted in multipath configuration. See Longhorn documentation related to this [issue](https://longhorn.io/kb/troubleshooting-volume-with-multipath/).

Include in `/etc/multipath.conf` the following configuration:

```
blacklist {
  devnode "^sd[a-z0-9]+"
}
```

Restart multipathd service
```shell
systemctl restart multipathd
```

### Installation procedure using Helm

Installation using `Helm` (Release 3):

- Step 1: Add the Longhorn Helm repository:

  ```shell
  helm repo add longhorn https://charts.longhorn.io
  ```
- Step2: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```
- Step 3: Create namespace

  ```shell
  kubectl create namespace longhorn-system
  ```

- Step 4: Prepare longhorn-values.yml file

  ```yml
  defaultSettings:
    defaultDataPath: "/storage"

  # Ingress Resource. Longhorn dashboard.
  ingress:
    ## Enable creation of ingress resource
    enabled: true
    ## Add ingressClassName to the Ingress
    ingressClassName: nginx

    # ingress host
    host: longhorn.${CLUSTER_DOMAIN}

    ## Set this to true in order to enable TLS on the ingress record
    tls: true

    ## TLS Secret Name
    tlsSecret: longhorn-tls

    ## Default ingress path
    path: /

    ## Ingress annotations
    annotations:
      # Enable basic auth
      nginx.ingress.kubernetes.io/auth-type: basic
      # Secret defined in nginx namespace
      nginx.ingress.kubernetes.io/auth-secret: nginx/basic-auth-secret
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      # Possible Cluster-Issuer values: 
      #   * 'letsencrypt-issuer' (valid TLS certificate using IONOS API) 
      #   * 'ca-issuer' (CA-signed certificate, not valid)
      cert-manager.io/cluster-issuer: letsencrypt-issuer
      cert-manager.io/common-name: longhorn.${CLUSTER_DOMAIN}
  ```
  {{site.data.alerts.note}}

  Substitute variables (`${var}`) in the above yaml file before deploying helm chart.
  -   Replace `${CLUSTER_DOMAIN}` by  the domain name used in the cluster. For example: `homelab.ricsanfre.com`
      FQDN must be mapped, in cluster DNS server configuration, to NGINX Ingress Controller's Load Balancer service external IP.
      External-DNS can be configured to automatically add that entry in your DNS service.
  {{site.data.alerts.end}}

  With this configuration:

  - Longhorn is configured to use `/storage` as default path for storing data (`defaultSettings.defaultDataPath`)

  - Ingress resource is created to make Longhorn front-end available through the URL `longhorn.${CLUSTER_DOMAIN}`. Ingress resource for NGINX (`ingress`) is annotated so, basic authentication is used and a Valid TLS certificate is generated using Cert-Manager for `longhorn.${CLUSTER_DOMAIN}` host

- Step 5: Install Longhorn in the longhorn-system namespace, using Helm:

  ```shell
  helm install longhorn longhorn/longhorn --namespace longhorn-system -f longhorn-values.yml
  ```

  {{site.data.alerts.note}}

  To enable backup to S3 storage server, a backup target need to be configured and other parameters need to be passed to helm chart. See [Backup documentation](/docs/backup/) to know how to configure Longhorn backup.

  {{site.data.alerts.end}}

- Step 6: Confirm that the deployment succeeded, run:

  ```shell
  kubectl -n longhorn-system get pod
  ```

### Longhorn CLI

`longhornctl` is a Command line interface (CLI) for Longhorn operations and troubleshooting.

-   Step 1: Download binary

    ```shell
    curl -LO "https://github.com/longhorn/cli/releases/download/${VERSION}/longhornctl-linux-${ARCH}"
    ```

-   Step 2: Install binary

    ```shell
    sudo install longhornctl-linux-${ARCH} /usr/local/bin/longhornctl
    ```
-   Step 3: Verify Installation

    ```shell
    longhornctl version
    ```

See available commands in longhorn reporistory:[https://github.com/longhorn/cli/blob/master/docs/longhornctl.md](https://github.com/longhorn/cli/blob/master/docs/longhornctl.md)



## Testing Longhorn

For testing longorn storage, create a specification for a `PersistentVolumeClaim` and use the `storageClassName` of `longhorn` and a POD making use of that volume claim.

{{site.data.alerts.note}}
Ansible playbook has been developed for automatically create this testing POD `roles\longhorn\test_longhorn.yml`
{{site.data.alerts.end}}

- Step 1. Create testing namespace

  ```shell
  kubectl create namespace testing-longhorn
  ```

- Step 2. Create manifest file `longhorn_test.yml`
  
  ```yml
  ---
  apiVersion: v1
  kind: PersistentVolumeClaim
  metadata:
    name: longhorn-pvc
    namespace: testing-longhorn
  spec:
    accessModes:
    - ReadWriteOnce
    storageClassName: longhorn
    resources:
      requests:
        storage: 1Gi
  ---
  apiVersion: v1
  kind: Pod
  metadata:
    name: longhorn-test
    namespace: testing-longhorn
  spec:
    containers:
    - name: longhorn-test
      image: nginx:stable-alpine
      imagePullPolicy: IfNotPresent
      volumeMounts:
      - name: longhorn-pvc
        mountPath: /data
      ports:
      - containerPort: 80
    volumes:
    - name: longhorn-pvc
      persistentVolumeClaim:
        claimName: longhorn-pvc
  ```
- Step 2. Apply the manifest file

  ```shell
  kubectl apply -f longhorn_test.yml
  ```

- Step 3. Check created POD has been started

  ```shell
  kubectl get pods -o wide -n testing-longhorn
  ```

- Step 4. Check pv and pvc have been created

  ```shell
  kubectl get pv -n testing-longhorn
  kubectl get pvc -n testing-longhorn
  ```
- Step 5. Connect to the POD and make use of the created volume

  Get a shell to the container and create a file on the persistent volume:

  ```shell
  kubectl exec -n testing-longhorn -it longhorn-test -- sh
  echo "testing" > /data/test.txt
  ```

- Step 6. Check in the longhorn-UI the created volumes and the replicas.

![longhorn-ui-volume](/assets/img/longhorn_volume_test.png)

![longhorn-ui-replica](/assets/img/longhorn_volume_test_replicas.png)


## LongHorn Configuration

### Setting Longhorn as default Kubernetes StorageClass


{{site.data.alerts.note}}

This step is not needed if K3s is installed disabling Local Path Provisioner (installation option: `--disable local-storage`).

In case that this parameter is not configured the following procedure need to be applied.

{{site.data.alerts.end}}

By default K3S comes with Rancher’s Local Path Provisioner and this enables the ability to create persistent volume claims out of the box using local storage on the respective node.

In order to use Longhorn as default storageClass whenever a new Helm is installed, Local Path Provisioner need to be removed from default storage class.

After longhorn installation check default storage classes with command:

```shell
kubectl get storageclass
```

```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  10m
longhorn (default)     driver.longhorn.io      Delete          Immediate              true                   3m27s
```

Both Local-Path and longhorn are defined as default storage classes:

Remove Local path from default storage classes with the command:

```shell
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

Procedure is explained in kubernetes documentation: ["Change default Storage Class"](https://kubernetes.io/docs/tasks/administer-cluster/change-default-storage-class/).

### Longhorn backup configuration

Longhorn support snapshot capability. Snapshot in Longhorn is an object that represents content of a Longhorn volume at a particular moment. It is stored inside the cluster. A snapshot[^1] in Longhorn captures the state of a volume at the time the snapshot is created. Each snapshot only captures changes that overwrite data from earlier snapshots, so a sequence of snapshots is needed to fully represent the full state of the volume. Volumes can be restored from a snapshot.

Snapshots are stored locally, as a part of each replica of a volume. They are stored on the disk of the nodes within the Kubernetes cluster. Snapshots are stored in the same location as the volume data on the host’s physical disk.

Longhorn can also backup the Volume content to backupstore  (NFS or S3). A backup[^9] in longhorn is an object that represent the content of a Longhorn volume at a particular time but stored in a external storage (NFS or S3).

Longhorn support two types of backup: incremental and full-backup

-   Incremental backup: A backup of a snapshot is copied to the backupstore. With incremental backup, Longhorn backs up only data that was changed since the last backup. (delta backup)
-   Full backup: Longhorn can perform full backups that upload all data blocks in the volume and overwrite existing data blocks in the backupstore.

#### Minio as S3 Backupstore

For configuring Longhorn's backup capability, it is needed to define a *backup target*, external storage system where longhorn volumes are backed to and restore from. Longhorn support NFS and S3 based backup targets.

[Minio](https://min.io) can be used as S3-compliant backend. See further details about installing external Minio Server for the cluster in: ["PiCluster - S3 Backup Backend (Minio)"](/docs/s3-backup/)

##### Install Minio backup server

See installation instructions in ["PiCluster - S3 Backup Backend (Minio)"](/docs/s3-backup/).

##### Configure Longhorn bucket and user

| User | Bucket |
|:--- |:--- |
|longhorn | k3s-longhorn |
{: .table .table-white .border-dark }

-   Create bucket for storing Longhorn backups/snapshots

    ```shell
    mc mb ${MINIO_ALIAS}/k3s-longhorn
    ```

-   Add `longhorn` user using Minio's CLI
    ```shell
    mc admin user add ${MINIO_ALIAS} longhorn supersecret
    ```

-   Define user policy to grant `longhorn` user access to backups bucket
    Create file `longhorn_policy.json` file:

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
                "arn:aws:s3:::k3s-longhorn",
                "arn:aws:s3:::k3s-longhorn/*"
            ]
        }
      ]
    }
    ```

    This policy grants read-write access to `k3s-longhorn` bucket

-   Add access policy to `longhorn` user:
    ```shell
    mc admin policy add ${MINIO_ALIAS} longhorn longhorn_policy.json
    ```


#### Configure Longhorn backup target

-   Create kuberentes `Secret` resource containing Minio end-point access information and credentials: `longhorn-minio-secret.yml`

    ```yaml
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

    {{site.data.alerts.note}}

    `AWS_CERT` parameter is only needed in case of using a self-signed certificate.

    {{site.data.alerts.end}}

    For encoding the different access paramenters the following commands can be used:

    ```shell
    echo -n minio_url | base64
    echo -n minio_access_key_id | base64
    echo -n minio_secret_access_key | base64
    cat minio-ssl.pem ca.pem | base64 | tr -d "\n"
    ```

    {{site.data.alerts.important}}
    As the command shows, SSL certificates in the validation chain must be concatenated and `\n` characters from the base64 encoded SSL pem must be removed.
    {{site.data.alerts.end}}

-   Apply manifest file

    ```shell
    kubectl apply -f longhorn-s3-secret.yml
    ```

-   Go to the Longhorn UI. In the top navigation bar, click `Settings`. In the Backup section, set `Backup Target` to:

    ```
    s3://<bucket-name>@<minio-s3-region>/
    ```

    {{site.data.alerts.important}}
    Make sure that you have `/` at the end, otherwise you will get an error.
    {{site.data.alerts.end}}

    In the Backup section set `Backup Target Credential Secret` to the secret resource created before

    ```
    minio-secret
    ```

    ![longhorn-backup-settings](/assets/img/longhorn_backup_settings.png)

    Backup Target can be automatically configured when deploying longhorn using helm chart

    Additional values need to be provided to `values.yaml` to configure S3 target.

    ```yaml
    defaultSettings:
      backupTarget: s3://longhorn@eu-west-1/
      backupTargetCredentialSecret: minio-secret
    ```

#### Scheduling longhorn volumes backup

A Longhorn recurring job can be created for scheduling periodic backups/snapshots of volumes.
See details in [Longhorn - Scheduling backups and snapshots](https://longhorn.io/docs/latest/snapshots-and-backups/scheduling-backups-and-snapshots/).

{{site.data.alerts.note}} **About Velero Integration**

If Velero is used to perform full cluster backup, including Longhorn's Persistent Volumes using CSI Snapshots, configuring this job is not needed.

See details about Velero installation and configuration in ["Pi Cluster - Backup and Restore with Velero"](/docs/backup/)

{{site.data.alerts.end}}

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

  ```shell
  kubectl apply -f recurring_job.yml
  ```

#### Configuring CSI Snapshot API

Longhorn supports creating and restoring Longhorn snapshots/backups via the Kubernetes CSI snapshot mechanism.

Longhorn does support, [Kubernetes CSI snapshot API](https://kubernetes.io/docs/concepts/storage/volume-snapshots/) to take snapshots/backups programmatically. See Longhorn documentation: [CSI Snapshot Support](https://longhorn.io/docs/latest/snapshots-and-backups/csi-snapshot-support/).

##### Enable CSI snapshots support in K3S

K3S distribution currently does not come with a preintegrated Snapshot Controller that is needed to enable CSI Snapshot feature. An external snapshot controller need to be deployed. K3S can be configured to use [kubernetes-csi/external-snapshotter](https://github.com/kubernetes-csi/external-snapshotter).

To enable this feature, follow instructions in [Longhorn documentation - Enable CSI Snapshot Support](https://longhorn.io/docs/latest/snapshots-and-backups/csi-snapshot-support/enable-csi-snapshot-support/).

{{site.data.alerts.note}}

Each release of Longhorn is compatible with a specific version external-snapshotter. Do not install latest available version.

For example, in Longhorn 1.9.0, CSI Snapshots support is compatible with [kubernetes-csi/external-snapshotter](https://github.com/kubernetes-csi/external-snapshotter) release v8.2.0.

Check which version to use in [Longhorn documentation - Enable CSI Snapshot Support](https://longhorn.io/docs/latest/snapshots-and-backups/csi-snapshot-support/enable-csi-snapshot-support/).

{{site.data.alerts.end}}

-   Step 1. Prepare kustomization yaml file to install external csi snaphotter (setting namespace to `kube-system`)

    `tmp/kustomization.yaml`

    ```yml
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    namespace: kube-system
    resources:
    - https://github.com/kubernetes-csi/external-snapshotter/client/config/crd/?ref=v8.2.0
    - https://github.com/kubernetes-csi/external-snapshotter/deploy/kubernetes/snapshot-controller/?ref=v8.2.0
    ```

-   Step 2. Deploy Snapshot-Controller

    ```shell
    kubectl apply -k ./tmp
    ```


##### Configure Longhorn CSI Snapshots

`VolumeSnapshotClass` objects from CSI Snapshot API need to be configured

-   Create `VolumeSnapshotClass` to create Longhorn snapshots (in-cluster snapshots, not backed up to S3 backend), `volume_snapshotclass_snap.yml`

    ```yml
    # CSI VolumeSnapshot Associated With Longhorn Snapshot
    kind: VolumeSnapshotClass
    apiVersion: snapshot.storage.k8s.io/v1
    metadata:
      name: longhorn-snapshot-vsc
    driver: driver.longhorn.io
    deletionPolicy: Delete
    parameters:
      type: snap
    ```

-   Create `VolumeSnapshotClass` to create Longhorn backups (backed up to S3 backend), `volume_snapshotclass_bak.yml`

    ```yml
    # CSI VolumeSnapshot Associated With Longhorn Backup
    kind: VolumeSnapshotClass
    apiVersion: snapshot.storage.k8s.io/v1
    metadata:
      name: longhorn-backup-vsc
    driver: driver.longhorn.io
    deletionPolicy: Delete
    parameters:
      type: bak
    ```

-   Apply manifest file

    ```shell
    kubectl apply -f volume_snapshotclass_snap.yml volume_snapshotclass_bak.yml
    ```

##### Testing CSI

-   Create a Longhorn Snapshot creation request

    VolumeSnapshot can be requested applying following manifest file

    ```yaml
    apiVersion: snapshot.storage.k8s.io/v1
    kind: VolumeSnapshot
    metadata:
      name: test-csi-volume-snapshot-longhorn-snapshot
    spec:
      volumeSnapshotClassName: longhorn-snapshot-vsc
      source:
        persistentVolumeClaimName: test-vol
    ```
    A Longhorn snapshot is created. The `VolumeSnapshot` object creation leads to the creation of a `VolumeSnapshotContent` Kubernetes object. The VolumeSnapshotContent refers to a Longhorn snapshot in its `VolumeSnapshotContent.snapshotHandle` field with the name `snap://volume-name/snapshot-name`

-   Create a Longhorn Backup creation request

    ```yaml
    apiVersion: snapshot.storage.k8s.io/v1
    kind: VolumeSnapshot
    metadata:
      name: test-csi-volume-snapshot-longhorn-backup
    spec:
      volumeSnapshotClassName: longhorn-backup-vsc
      source:
        persistentVolumeClaimName: test-vol
    ```
    A Longhorn backup is created. The `VolumeSnapshot` object creation leads to the creation of a `VolumeSnapshotContent` Kubernetes object. The `VolumeSnapshotContent` refers to a Longhorn backup in its `VolumeSnapshotContent.snapshotHandle` field with the name `bak://backup-volume/backup-name`


## Observability

### Metrics

As stated by official documentation[^7], Longhorn natively exposes metrics in Prometheus text format[^8] at a REST endpoint `http://LONGHORN_MANAGER_IP:PORT/metrics`.

Longhorn Backend kubernetes service is pointing to the set of Longhorn manager pods. Longhorn’s metrics are exposed in Longhorn manager pods at the endpoint `http://LONGHORN_MANAGER_IP:PORT/metrics`

Backend endpoint is already exposing Prometheus metrics.

#### Prometheus Integration

`ServiceMonitoring`, Prometheus Operator's CRD,  resource can be automatically created so Kube-Prometheus-Stack is able to automatically start collecting metrics from Longhorn

```yaml
metrics:
  serviceMonitor:
    enabled: true
```

#### Grafana Dashboards

Longhorn dashboard sample can be donwloaded from [grafana.com](https://grafana.com): [dashboard id: 13032](https://grafana.com/grafana/dashboards/13032).

Dashboard can be automatically added using Grafana's dashboard providers configuration. See further details in ["PiCluster - Observability Visualization (Grafana): Automating installation of community dasbhoards](/docs/grafana/#automating-installation-of-grafana-community-dashboards)

Add following configuration to Grafana's helm chart values file:

```yaml
# Configure default Dashboard Provider
# https://grafana.com/docs/grafana/latest/administration/provisioning/#dashboards
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: infrastructure
        orgId: 1
        folder: "Infrastructure"
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/infrastructure-folder

# Add dashboard
# Dashboards
dashboards:
  infrastructure:
    longhorn:
      # https://grafana.com/grafana/dashboards/16888-longhorn/
      gnetId: 16888
      revision: 9
      datasource:
        - { name: DS_PROMETHEUS, value: Prometheus }
```


---

[^2]: [Mount Propagation](https://kubernetes.io/docs/concepts/storage/volumes/#mount-propagation) is a feature activated by defult since Kubernetes v1.14
[^3]: [Longorn Requirements- Installing open-iscsi](https://longhorn.io/docs/latest/deploy/install/#installing-open-iscsi)
[^4]: [Longorn Requirements- Installing NFSv4 Client](https://longhorn.io/docs/latest/deploy/install/#installing-nfsv4-client)
[^5]: [Longorn Requirements- Installing Cryptsetup and Luks](https://longhorn.io/docs/latest/deploy/install/#installing-cryptsetup-and-luks)
[^6]: [Longorn Requirements- Installing Device Mapper](https://longhorn.io/docs/latest/deploy/install/#installing-device-mapper-userspace-tool)
[^1]: [Longhorn Concepts - Snapshots](https://longhorn.io/docs/latest/concepts/#24-snapshots)
[^7]: [Longorn Monitoring- Prometheus and Grafana setup](https://longhorn.io/docs/1.8.0/monitoring/prometheus-and-grafana-setup/)
[^8]: [Prometheus - Instrumenting - Exposition formats: Test-based-format](https://prometheus.io/docs/instrumenting/exposition_formats/#text-based-format)
[^9]: [Longhorn Concepts - Backups](https://longhorn.io/docs/1.9.0/concepts/#3-backups-and-secondary-storage)