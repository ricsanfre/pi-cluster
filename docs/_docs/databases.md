---
title: Databases
permalink: /docs/databases/
description: How to deploy databases in Kubernetes cluster. Leveraging cloud-native operators such as CloudNative-PG or MongoDB
last_modified_at: "07-07-2024"

---


## CloudNative-PG

[CloudNative-PG](https://cloudnative-pg.io/) is the Kubernetes operator that covers the full lifecycle of a highly available PostgreSQL database cluster with a primary/standby architecture, using native streaming replication.

It is open source under Apache License 2.0 and submitted for CNCF Sandbox in April 2022

{{site.data.alerts.note}}

See further details in ["Recommended architecutes for PosgreSQL in Kubernetes"](https://www.cncf.io/blog/2023/09/29/recommended-architectures-for-postgresql-in-kubernetes/)

{{site.data.alerts.end}}

CloudNative-PG offers a declarative way of deploying PostgreSQL databases, supporting the following main features:

- DB Bootstrap
  - Support automatic initialization of the database. See details in [CloudNative-PG Bootstrap](https://cloudnative-pg.io/documentation/1.23/bootstrap/)
  - It also includes automatic import from an external database or backup
- HA support using database replicas
  - Data replication from rw instance to read-only instances. See details in [CloudNative-PG Replication](https://cloudnative-pg.io/documentation/1.23/replication/) 
- Backup and restore
  - Support backup and restore to/from S3 Object Storage like Minio/AWS. See details in [CloudNative-PG Backup on Object Stores](https://cloudnative-pg.io/documentation/1.23/backup_barmanobjectstore/)
  - The operator can orchestrate a continuous backup infrastructure that is based on the [Barman Cloud](https://pgbarman.org/) tool. 
- Monitoring:
  - For each PostgreSQL instance, the operator provides an exporter of metrics for [Prometheus](https://prometheus.io/) via HTTP, on port 9187, named `metrics`. See detaisl in [CloudNative-PG Montiroring](https://cloudnative-pg.io/documentation/1.23/monitoring/)


### CloudNative-PG operator installation

CloudNative-PG can be installed following different procedures. See [CloudNative-PG installation](https://cloudnative-pg.io/documentation/1.23/installation_upgrade/). Helm installation procedure will be described here:

Installation using `Helm` (Release 3):

- Step 1: Add the CloudNative-PG Helm repository:

  ```shell
  helm repo add cnpg https://cloudnative-pg.github.io/charts
  ```
- Step2: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```
- Step 3: Create namespace

  ```shell
  kubectl create namespace databases
  ```

- Step 4: Create helm values file `cloudnative-pg-values.yml`

  ```yml
  # Install operator CRDs
  crds:
    create: true
 
  monitoring:
    # Disabling podMonitoring by default. 
    # It could be enabled per PosgreSQL Cluster resource.
    # Enabling it requires Prometheus Operator CRDs.
    podMonitorEnabled: false
    # Create Grafana dashboard configmap that can be automatically loaded by Grafana.
    grafanaDashboard:
      create: true  
  ```

- Step 5: Install CloudNative-PG operator

  ```shell
  helm install cloudnative-pg cnpg/cloudnative-pg -f cloudnative-pg-values.yml --namespace databases 
  ```
- Step 6: Confirm that the deployment succeeded, run:

  ```shell
  kubectl -n databases get pod
  ```

### Deploy PosgreSQL database

Using CloudNative-PG operator build PosgreSQL Cluster CRD.


#### Creating simple PosgreSQL Cluster

Create and apply the following manifest file

```yml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: mydatabase
  namespace: databases
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:16.3-4
  storage:
    size: 1Gi
    storageClass: longhorn
  # Enabling monitoring
  monitoring:
    enablePodMonitor: true
  # Init database
  bootstrap:
    initdb:
      database: mydatabase
      owner: myuser
```
  
- It will create and bootstrap a 3 nodes database, 16.3-4 version.
- Bootstrap will create a database named, `mydatabase` and a user, `myuser` which is the owner of that database
- It will create automatically a secret containig all credentials to access the database

#### Auto-generated secrets

Bootstraping without specifying any secret, like in the previous example, cloudnative-pg generates a couple of secrets. 

- `[cluster name]-app` (unless you have provided an existing secret through .spec.bootstrap.initdb.secret.name)
- `[cluster name]-superuser` (if .spec.enableSuperuserAccess is set to true and you have not specified a different secret using .spec.superuserSecret)

Each secret contain the following data:

- username
- password
- hostname to the RW service
- port number
- database name
- a working [.pgpass](https://www.postgresql.org/docs/current/libpq-pgpass.html) file
- uri
- jdbc-uri

See further details in [Connected from applications - Secrets](https://cloudnative-pg.io/documentation/1.23/applications/#secrets).


The secret generated can be automatically decoded using the following command:

```shell
kubectl get secret mydatabase-db-app -o json -n databases | jq '.data | map_values(@base64d)'
{
  "dbname": "mydatabase",
  "host": "mydatabase-db-rw",
  "jdbc-uri": "jdbc:postgresql://mydatabase-db-rw.databases:5432/mydatabase?password=Vq8d5Ojh9v4rLNCCRgeluEYOD4c8se4ioyaJOHiymT9zFFSNAWpy34TdTkVeoMaq&user=keycloak",
  "password": "Vq8d5Ojh9v4rLNCCRgeluEYOD4c8se4ioyaJOHiymT9zFFSNAWpy34TdTkVeoMaq",
  "pgpass": "mydatabase-db-rw:5432:mydatabase:myuser:Vq8d5Ojh9v4rLNCCRgeluEYOD4c8se4ioyaJOHiymT9zFFSNAWpy34TdTkVeoMaq\n",
  "port": "5432",
  "uri": "postgresql://myuser:Vq8d5Ojh9v4rLNCCRgeluEYOD4c8se4ioyaJOHiymT9zFFSNAWpy34TdTkVeoMaq@mydatabase-db-rw.databases:5432/keycloak",
  "user": "myuser",
  "username": "myuser"
}
```

#### Specifying secrets

During database bootstrap secrets for the database user can be specified:

- Step 1. Create a secret of type `kubernetes.io/basic-auth`

  ```yaml
  apiVersion: v1
  kind: Secret
  type: kubernetes.io/basic-auth
  metadata:
    name: mydatabase-db-secret
    namespace: database
    labels:
      cnpg.io/reload: "true"
  stringData:
    username: "myuser"
    password: "supersecret"  
  ```
  
  {{site.data.alerts.note}}

  `cnpg.io/reload: "true"` label added to ConfigMaps and Secrets to be automatically reloaded by cluster instances.

  {{site.data.alerts.end}}


- Step 2. Create Cluster database specifying the secret:

  ```yaml
  apiVersion: postgresql.cnpg.io/v1
  kind: Cluster
  metadata:
    name: mydatabase
    namespace: databases
  spec:
    instances: 3
    imageName: ghcr.io/cloudnative-pg/postgresql:16.3-4
    storage:
      size: 1Gi
      storageClass: longhorn
    monitoring:
      enablePodMonitor: true
    bootstrap:
      initdb:
        database: mydatabase
        owner: myuser
        secret:
          name: mydatabase-db-secret  
  ```


### Accesing Database

#### Database Kubernetes services

3 Kubernetes services are created automatically to access the database:

- `[cluster name]-rw` : Always points to the Primary node (read-write replica)
- `[cluster name]-ro`:  Points to only Replica nodes, chosen by round-robin (Accees only to read-only replicas)
- `[cluster name]-r` : Points to any node in the cluster, chosen by round-robin 

```shell
kubectl get svc -n databases
NAME                   TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
mydatabase-db-r          ClusterIP   10.43.62.218   <none>        5432/TCP   33m
mydatabase-db-ro         ClusterIP   10.43.242.78   <none>        5432/TCP   33m
mydatabase-db-rw         ClusterIP   10.43.133.46   <none>        5432/TCP   33m

```

#### Testing remote access to the database

Once the database is up and running, remote access can be tested deploying a test pod

```shell
kubectl run -i --tty postgres --image=postgres --restart=Never -- sh

psql -U myuser -h mydatabase-db-rw.databases -d mydatabase
```

Password to be provided need to be extracted from the database secret.


### Configuring backup to external Object Store

S3, storage server, like Minio need to be configured.

- A bucket, `cloudnative-pg` and an specific user with read-write access need to be configured

  See details on how to configure external Minio server for perfoming backups in ["S3 Backup Backend (Minio)"](/docs/s3-backup/)

- Step 1. Create secret containing Minio credentials

  ```yaml
  apiVersion: v1
  kind: Secret
  metadata:
    name: cnpg-minio-secret
    namespace: database
  stringData:
    AWS_ACCESS_KEY_ID: "myuser"
    AWS_SECRET_ACCESS_KEY: "supersecret" 

  ```

- Step 2. Create Cluster with automated backup


  ```yaml
  apiVersion: postgresql.cnpg.io/v1
  kind: Cluster
  metadata:
    name: mydatabase
  spec:
    instances: 3
    imageName: ghcr.io/cloudnative-pg/postgresql:16.3-4
    storage:
      size: 10Gi
      storageClass: longhorn
    monitoring:
      enablePodMonitor: true
    bootstrap:
      initdb:
        database: mydatabase
        owner: mydatabase
        secret:
          name: mydatabase-db-secret
    backup:
      barmanObjectStore:
        data:
          compression: bzip2
        wal:
          compression: bzip2
          maxParallel: 8
        destinationPath: s3://cloudnative-pg/backup
        endpointURL: https://s3.ricsanfre.com:9091
        s3Credentials:
          accessKeyId:
            name: cnpg-minio-secret
            key: AWS_ACCESS_KEY_ID
          secretAccessKey:
            name: cnpg-minio-secret
            key: AWS_SECRET_ACCESS_KEY
      retentionPolicy: "30d"
  ```
