---
title: Databases
permalink: /docs/databases/
description: How to deploy databases in Kubernetes cluster. Leveraging cloud-native operators such as CloudNative-PG, MongoDB, and Valkey
last_modified_at: "22-06-2026"

---


## CloudNative-PG

[CloudNative-PG](https://cloudnative-pg.io/) is the Kubernetes operator that covers the full lifecycle of a highly available PostgreSQL database cluster with a primary/standby architecture, using native streaming replication.

It is open source under Apache License 2.0 and submitted for CNCF Sandbox in April 2022

{{site.data.alerts.note}}

See further details in ["Recommended architectures for PostgreSQL in Kubernetes"](https://www.cncf.io/blog/2023/09/29/recommended-architectures-for-postgresql-in-kubernetes/)

{{site.data.alerts.end}}

CloudNative-PG offers a declarative way of deploying PostgreSQL databases, supporting the following main features:

- DB Bootstrap
  - Support automatic initialization of the database. See details in [CloudNative-PG Bootstrap](https://cloudnative-pg.io/documentation/current/bootstrap/)
  - It also includes automatic import from an external database or backup (see [Bootstrap from Backup](#bootstrapping-from-an-existing-backup))
- HA support using database replicas
  - Data replication from rw instance to read-only instances. See details in [CloudNative-PG Replication](https://cloudnative-pg.io/documentation/current/replication/)
- Backup and restore
  - Support backup and restore to/from S3 Object Storage like Minio/AWS. See details in [CloudNative-PG Backup on Object Stores](https://cloudnative-pg.io/documentation/current/backup_barmanobjectstore/)
  - The operator can orchestrate a continuous backup infrastructure that is based on the [Barman Cloud](https://pgbarman.org/) tool.
  - Scheduled backups via the `ScheduledBackup` CRD (see [Scheduled Backups](#scheduled-backups))
- Monitoring:
  - For each PostgreSQL instance, the operator provides an exporter of metrics for [Prometheus](https://prometheus.io/) via HTTP, on port 9187, named `metrics`. See details in [CloudNative-PG Monitoring](https://cloudnative-pg.io/documentation/current/monitoring/)
- Managed services:
  - The operator can create additional Kubernetes Services for specific use cases (read-only replicas, connection pooling) via the `managed.services` feature. See [CloudNative-PG Managed Services](https://cloudnative-pg.io/documentation/current/service_management/)


### CloudNative-PG operator installation

CloudNative-PG can be installed following different procedures. See [CloudNative-PG installation](https://cloudnative-pg.io/documentation/current/installation_upgrade/). Helm installation procedure will be described here:

Installation using `Helm` (Release 3):

- Step 1: Add the CloudNative-PG Helm repository:

  ```shell
  helm repo add cnpg https://cloudnative-pg.github.io/charts
  ```
- Step 2: Fetch the latest charts from the repository:

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
    # It could be enabled per PostgreSQL Cluster resource.
    # Enabling it requires Prometheus Operator CRDs.
    podMonitorEnabled: false
    # Create Grafana dashboard configmap that can be automatically loaded by Grafana.
    grafanaDashboard:
      create: true  
  ```

- Step 5: Install CloudNative-PG operator (pinning a specific version is recommended for production):

  ```shell
  helm install cloudnative-pg cnpg/cloudnative-pg -f cloudnative-pg-values.yml --namespace databases --version 0.28.3
  ```
- Step 6: Confirm that the deployment succeeded, run:

  ```shell
  kubectl -n databases get pod
  ```

### Deploy PostgreSQL database

Using CloudNative-PG operator, create a PostgreSQL Cluster CRD resource.


#### Creating a simple PostgreSQL Cluster

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
  # Resource limits (recommended for production)
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2048Mi
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

- It will create and bootstrap a 3-node PostgreSQL database cluster, version 16.3.
- Bootstrap will create a database named `mydatabase` and a user `myuser`, which is the owner of that database.
- It will create automatically a secret containing all credentials to access the database.
- `storageClass: longhorn` uses Longhorn distributed block storage. Change this to match your cluster's available storage classes (check with `kubectl get storageclass`).

#### Auto-generated secrets

Bootstrapping without specifying any secret, like in the previous example, cloudnative-pg generates a couple of secrets. 

- `[cluster name]-app` (unless you have provided an existing secret through .spec.bootstrap.initdb.secret.name)
- `[cluster name]-superuser` (if .spec.enableSuperuserAccess is set to true and you have not specified a different secret using .spec.superuserSecret)

Each secret contains the following data:

- username
- password
- hostname to the RW service
- port number
- database name
- a working [.pgpass](https://www.postgresql.org/docs/current/libpq-pgpass.html) file
- uri
- jdbc-uri

See further details in [Connecting from applications - Secrets](https://cloudnative-pg.io/documentation/current/applications/#secrets).


The secret generated can be automatically decoded using the following command:

```shell
kubectl get secret mydatabase-app -o json -n databases | jq '.data | map_values(@base64d)'
{
  "dbname": "mydatabase",
  "host": "mydatabase-rw",
  "jdbc-uri": "jdbc:postgresql://mydatabase-rw.databases:5432/mydatabase?password=Vq8d5Ojh9v4rLNCCRgeluEYOD4c8se4ioyaJOHiymT9zFFSNAWpy34TdTkVeoMaq&user=myuser",
  "password": "Vq8d5Ojh9v4rLNCCRgeluEYOD4c8se4ioyaJOHiymT9zFFSNAWpy34TdTkVeoMaq",
  "pgpass": "mydatabase-rw:5432:mydatabase:myuser:Vq8d5Ojh9v4rLNCCRgeluEYOD4c8se4ioyaJOHiymT9zFFSNAWpy34TdTkVeoMaq\n",
  "port": "5432",
  "uri": "postgresql://myuser:Vq8d5Ojh9v4rLNCCRgeluEYOD4c8se4ioyaJOHiymT9zFFSNAWpy34TdTkVeoMaq@mydatabase-rw.databases:5432/mydatabase",
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
    namespace: databases
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


### Creating multiple databases with the Database CRD

CloudNative-PG provides a `Database` custom resource that allows you to declaratively create and manage multiple databases within a single PostgreSQL cluster — each owned by a separate role. This is especially useful for microservice architectures where each service gets its own logical database, avoiding shared schemas while reusing the same underlying PostgreSQL cluster.

The typical pattern involves three steps:

1. **Define the roles** on the `Cluster` resource via `spec.managed.roles`
2. **Create the databases** using the `Database` CRD, each referencing an owner role
3. **Supply role passwords** via Kubernetes Secrets (optionally managed by ExternalSecrets)

#### Step 1 — Cluster with managed roles

Define a `Cluster` that declares roles but does not create a default database (`initdb: {}`):

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-ecommerce
  namespace: databases
spec:
  instances: 2
  imageName: ghcr.io/cloudnative-pg/postgresql:18.4

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  storage:
    size: 10Gi
    storageClass: longhorn

  monitoring:
    enablePodMonitor: true

  # No default database — databases are created via the Database CRD
  bootstrap:
    initdb: {}

  # Roles are created by the operator with passwords from the referenced Secrets
  managed:
    roles:
      - name: users_owner
        ensure: present
        login: true
        inherit: true
        passwordSecret:
          name: users-db-secret
      - name: orders_owner
        ensure: present
        login: true
        inherit: true
        passwordSecret:
          name: orders-db-secret

  backup:
    barmanObjectStore:
      destinationPath: s3://k3s-barman/postgres-ecommerce
      endpointURL: https://s3.example.com:9091
      s3Credentials:
        accessKeyId:
          name: postgres-ecommerce-s3-secret
          key: AWS_ACCESS_KEY_ID
        secretAccessKey:
          name: postgres-ecommerce-s3-secret
          key: AWS_SECRET_ACCESS_KEY
      data:
        compression: bzip2
      wal:
        compression: bzip2
        maxParallel: 8
    retentionPolicy: "30d"
```

Where:
- `initdb: {}`: Creates an empty PostgreSQL instance without a default application database
- `managed.roles[].ensure: present`: The operator creates the PostgreSQL role and keeps it in sync
- `managed.roles[].passwordSecret`: Each role's login password is read from the referenced Kubernetes Secret

#### Step 2 — Create role password secrets

Each role needs a Kubernetes Secret with the password (these can be created manually or via ExternalSecrets):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: users-db-secret
  namespace: databases
type: Opaque
stringData:
  password: "<users-owner-password>"
---
apiVersion: v1
kind: Secret
metadata:
  name: orders-db-secret
  namespace: databases
type: Opaque
stringData:
  password: "<orders-owner-password>"
```

{{site.data.alerts.tip}}

For production deployments, manage role passwords with ExternalSecrets backed by a Vault instance rather than manually-created Secrets. See the e-commerce database configuration in `kubernetes/apps/e-commerce/config/databases/base/postgres-externalsecrets.yaml` for a complete example using Vault as the secret backend.

{{site.data.alerts.end}}

#### Step 3 — Create databases with the Database CRD

Apply `Database` custom resources — one per application database:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: users-db
  namespace: databases
spec:
  name: users                     # Database name inside PostgreSQL
  owner: users_owner              # Role that owns the database
  cluster:
    name: postgres-ecommerce      # Target Cluster
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: orders-db
  namespace: databases
spec:
  name: orders
  owner: orders_owner
  cluster:
    name: postgres-ecommerce
```

Each `Database` CRD creates a PostgreSQL database (`spec.name`) owned by the specified role (`spec.owner`) inside the target `Cluster` (`spec.cluster.name`).

#### Connection per service

Each service connects with its own role credentials to its dedicated database:

| Service | Host | Database | User | Password secret |
|---------|------|----------|------|----------------|
| user-service | `postgres-ecommerce-rw.databases` | `users` | `users_owner` | `users-db-secret` |
| order-service | `postgres-ecommerce-rw.databases` | `orders` | `orders_owner` | `orders-db-secret` |

All databases share the same RW service endpoint — connection isolation is enforced by PostgreSQL's role-based access control.

{{site.data.alerts.note}}

The `Database` CRD is reconciled by the CloudNative-PG operator. If you delete the `Database` resource, the corresponding PostgreSQL database is dropped. See [CloudNative-PG Database Management](https://cloudnative-pg.io/documentation/current/database_management/) for all options.

{{site.data.alerts.end}}


### Accessing Database

#### Database Kubernetes services

3 Kubernetes services are created automatically to access the database:

- `[cluster name]-rw` : Always points to the Primary node (read-write)
- `[cluster name]-ro`:  Points to only Replica nodes, chosen by round-robin (access only to read-only replicas)
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

  See details on how to configure the external S3 server for performing backups in ["S3 Backup Backend (RustFS)"](/docs/rustfs/)

- Step 1. Create secret containing Minio credentials

  ```yaml
  apiVersion: v1
  kind: Secret
  metadata:
    name: cnpg-s3-secret
    namespace: databases
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
        owner: myuser
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
            name: cnpg-s3-secret
            key: AWS_ACCESS_KEY_ID
          secretAccessKey:
            name: cnpg-s3-secret
            key: AWS_SECRET_ACCESS_KEY
      retentionPolicy: "30d"
  ```


### Scheduled backups

CloudNative-PG supports automated scheduled backups via the `ScheduledBackup` CRD. This is essential for production deployments:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: mydatabase-daily
  namespace: databases
spec:
  cluster:
    name: mydatabase
  schedule: "0 0 3 * * *"   # Daily at 03:00 UTC
  backupOwnerReference: self
  immediate: true             # Take first backup immediately
  target: primary             # Back up from primary (default) or prefer-standby
```

See [CloudNative-PG Scheduled Backups](https://cloudnative-pg.io/documentation/current/backup_barmanobjectstore/#scheduled-backups) for the full cron syntax and configuration options.


### Bootstrapping from an existing backup

To restore a cluster from a previous backup (disaster recovery or cloning), use `bootstrap.recovery`:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: mydatabase-restored
  namespace: databases
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:16.3-4
  storage:
    size: 10Gi
    storageClass: longhorn
  bootstrap:
    recovery:
      source: mydatabase     # Source cluster name
      recoveryTarget:
        targetTime: "2025-01-15T00:00:00Z"  # Point-in-time recovery (optional)
      backupID: "20250114T030000"  # Specific backup ID (optional)
  externalClusters:
    - name: mydatabase       # Reference to the source backup repository
      barmanObjectStore:
        destinationPath: s3://cloudnative-pg/backup
        endpointURL: https://s3.ricsanfre.com:9091
        s3Credentials:
          accessKeyId:
            name: cnpg-s3-secret
            key: AWS_ACCESS_KEY_ID
          secretAccessKey:
            name: cnpg-s3-secret
            key: AWS_SECRET_ACCESS_KEY
        wal:
          maxParallel: 8
```

Key recovery options:
- `targetTime`: Point-in-time recovery to a specific timestamp
- `backupID`: Restore from a specific base backup
- Omit both for the latest available backup

See [CloudNative-PG Recovery Bootstrap](https://cloudnative-pg.io/documentation/current/bootstrap/#bootstrap-from-a-live-cluster) for all options.


### Recommended production configuration

The following example consolidates all production best practices — resources, anti-affinity, monitoring, backup, and managed services:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-prod
  namespace: databases
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:16.3-4

  # Resource limits
  resources:
    requests:
      cpu: 1000m
      memory: 2048Mi
    limits:
      cpu: 4000m
      memory: 4096Mi

  # Storage
  storage:
    size: 20Gi
    storageClass: longhorn

  # Pod anti-affinity: spread replicas across nodes
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: cnpg.io/cluster
                operator: In
                values:
                  - postgres-prod
          topologyKey: kubernetes.io/hostname

  # Monitoring
  monitoring:
    enablePodMonitor: true

  # Bootstrap
  bootstrap:
    initdb:
      database: appdb
      owner: appuser
      secret:
        name: postgres-prod-secret

  # Backup
  backup:
    barmanObjectStore:
      destinationPath: s3://cloudnative-pg/postgres-prod
      endpointURL: https://s3.ricsanfre.com:9091
      s3Credentials:
        accessKeyId:
          name: cnpg-s3-secret
          key: AWS_ACCESS_KEY_ID
        secretAccessKey:
          name: cnpg-s3-secret
          key: AWS_SECRET_ACCESS_KEY
      data:
        compression: bzip2
      wal:
        compression: bzip2
        maxParallel: 8
    retentionPolicy: "30d"

  # Additional managed services
  managed:
    services:
      additional:
        - selectorType: readonly
          serviceType:
            name: postgres-prod-readonly
            type: ClusterIP
---
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: postgres-prod-daily
  namespace: databases
spec:
  cluster:
    name: postgres-prod
  schedule: "0 0 3 * * *"
  backupOwnerReference: self
```


### Upgrading PostgreSQL version

CloudNative-PG supports zero-downtime rolling updates for minor version upgrades. To upgrade:

1. **Check available images**: See [CloudNative-PG supported PostgreSQL images](https://cloudnative-pg.io/documentation/current/installation_upgrade/#in-place-updates-of-the-image)

2. **Patch the Cluster resource** with the new image tag:

   ```shell
   kubectl patch cluster mydatabase -n databases \
     --type merge \
     -p '{"spec":{"imageName":"ghcr.io/cloudnative-pg/postgresql:16.8-4"}}'
   ```

3. **Watch the rolling update**:

   ```shell
   kubectl get pods -n databases -l cnpg.io/cluster=mydatabase -w
   ```

   The operator performs a rolling restart: it starts with the replicas, then does a controlled switchover to upgrade the primary last.

{{site.data.alerts.important}}

- **Minor version upgrades** (e.g., 16.3 → 16.8): fully automated by the operator.
- **Major version upgrades** (e.g., 16.x → 17.x): require additional steps. See [CloudNative-PG Major Upgrades](https://cloudnative-pg.io/documentation/current/installation_upgrade/#major-upgrades) and use `kubectl cnpg cluster upgrade`.

{{site.data.alerts.end}}


## MongoDB Operator

The [MongoDB Community Kubernetes Operator](https://github.com/mongodb/mongodb-kubernetes-operator) is an open-source Kubernetes operator that automates the deployment and management of MongoDB replica sets. It handles provisioning, scaling, authentication, TLS, and rolling upgrades through the `MongoDBCommunity` custom resource.

MongoDB Community Operator supports the following main features:

- **Replica set management**: Declaratively create and manage multi-member MongoDB replica sets
- **Automated failover**: Automatic detection and recovery from node failures within the replica set
- **User and role management**: Declarative creation of MongoDB users with specific roles via Kubernetes Secrets
- **TLS encryption**: Built-in support for TLS certificates to encrypt inter-node and client traffic
- **Rolling upgrades**: Operator-orchestrated version upgrades with minimal disruption
- **Custom configuration**: Pass through any MongoDB server configuration via `additionalMongodConfig`


### MongoDB operator installation

MongoDB Community Kubernetes Operator can be installed following different procedures. See [MongoDB Community Operator installation](https://github.com/mongodb/mongodb-kubernetes-operator/blob/master/docs/install-upgrade.md#install-the-operator). Helm installation procedure will be described here:

Installation using `Helm` (Release 3):

- Step 1: Add the MongoDB Helm repository:

  ```shell
  helm repo add mongodb https://mongodb.github.io/helm-charts
  ```
- Step 2: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```
- Step 3: Create namespace

  ```shell
  kubectl create namespace mongodb
  ```

- Step 4: Install MongoDB operator (pinning a specific version is recommended for production):

  ```shell
  helm install community-operator mongodb/community-operator --namespace mongodb --set operator.watchNamespace="*" --version 0.13.0
  ```

  Setting `operator.watchNamespace="*"` allows creating MongoDB database resources (CRDs) in any namespace.

- Step 5: Confirm that the deployment succeeded, run:

  ```shell
  kubectl -n mongodb get pod
  ```

### Create a MongoDB database cluster

- Step 1: Create secret containing password of admin user

  ```yaml
  apiVersion: v1
  kind: Secret
  metadata:
    name: admin-user
    namespace: mongodb
  type: Opaque
  stringData:
    password: <your-secure-password-here>
  ```

  {{site.data.alerts.note}}

  The password example above uses a placeholder. In production, use a strong randomly-generated password and consider managing it via ExternalSecrets backed by a Vault instance. Do not commit plain-text passwords to Git.

  {{site.data.alerts.end}}

- Step 2: Create the MongoDBCommunity resource with persistence and resource limits

  ```yaml
  apiVersion: mongodbcommunity.mongodb.com/v1
  kind: MongoDBCommunity
  metadata:
    name: mongodb
    namespace: mongodb
  spec:
    members: 3
    type: ReplicaSet
    version: "7.0.12"
    security:
      authentication:
        modes: ["SCRAM"]
    users:
      - name: admin
        db: admin
        passwordSecretRef:
          name: admin-user
        roles:
          - name: clusterAdmin
            db: admin
          - name: userAdminAnyDatabase
            db: admin
        scramCredentialsSecretName: my-scram
        connectionStringSecretName: mongodb-admin-connection  # Custom connection string secret name
    additionalMongodConfig:
      storage.wiredTiger.engineConfig.journalCompressor: zlib
    statefulSet:
      spec:
        template:
          spec:
            containers:
              - name: mongod
                resources:
                  requests:
                    cpu: 500m
                    memory: 512Mi
                  limits:
                    cpu: 2000m
                    memory: 2048Mi
        volumeClaimTemplates:
          - metadata:
              name: data
            spec:
              storageClassName: longhorn
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 10Gi
  ```

  Where:

  - `spec.members`: Number of replica set members (odd number recommended: 1, 3, 5, or 7)
  - `spec.version`: MongoDB server version (use a currently supported version — 7.0+ recommended)
  - `spec.users[].connectionStringSecretName`: Optional custom name for the connection string secret (defaults to `<metadata.name>-<auth-db>-<username>`)
  - `spec.statefulSet.spec.template.spec.containers[].resources`: CPU/memory requests and limits for the mongod container
  - `spec.statefulSet.spec.volumeClaimTemplates`: Persistent volume claims for MongoDB data storage

### Connection to MongoDB

MongoDB operator creates a headless service `<metadata.name>-svc`, so DNS query to the service returns the IP addresses of all stateful pods created for the cluster. Also every single pod, mongodb replica, is reachable through DNS using dns name `<metadata.name>-<id>` (where `<id>` indicates the replica number: 0, 1, 2, etc.)

The Community Kubernetes Operator creates secrets that contains users' connection strings and credentials.

The secrets follow this naming convention: `<metadata.name>-<auth-db>-<username>`, where:

|Variable|Description|Value in Sample|
|---|---|---|
|`<metadata.name>`|Name of the MongoDB database resource.|`mongodb`|
|`<auth-db>`|[Authentication database](https://www.mongodb.com/docs/manual/core/security-users/#std-label-user-authentication-database) where you defined the database user.|`admin`|
|`<username>`|Username of the database user.|`admin`|

**NOTE**: Alternatively, you can specify an optional `users[i].connectionStringSecretName` field in the `MongoDBCommunity` custom resource to specify the name of the connection string secret that the Community Kubernetes Operator creates.

To obtain the connection string execute the following command

```shell
kubectl get secret mongodb-admin-admin -n mongodb \
-o json | jq -r '.data | with_entries(.value |= @base64d)'
```

The connection string is like:
```shell
{
  "connectionString.standard": "mongodb://admin:<password>@mongodb-0.mongodb-svc.mongodb.svc.cluster.local:27017,mongodb-1.mongodb-svc.mongodb.svc.cluster.local:27017,mongodb-2.mongodb-svc.mongodb.svc.cluster.local:27017/admin?replicaSet=mongodb&ssl=true",
  "connectionString.standardSrv": "mongodb+srv://admin:<password>@mongodb-svc.mongodb.svc.cluster.local/admin?replicaSet=mongodb&ssl=true",
  "password": "<password>",
  "username": "admin"
}

```

Connection string from the secret (`connectionString.standardSrv`) can be used within application as an environment variable.

```yaml
containers:
 - name: test-app
   env:
    - name: "CONNECTION_STRING"
      valueFrom:
        secretKeyRef:
          name: <metadata.name>-<auth-db>-<username>
          key: connectionString.standardSrv
```

Also connectivity can be tested using `mongosh`

- Connect to one of the mongodb pods

  ```shell
  kubectl -n mongodb exec -it mongodb-0 -- /bin/bash
  ```

- Execute mongosh using the previous connection string

  ```shell
  mongosh "mongodb+srv://admin:<password>@mongodb-svc.mongodb.svc.cluster.local/admin?replicaSet=mongodb&ssl=true"
  ```

### Secure MongoDB Connections using TLS

MongoDB Community Kubernetes Operator can be configured to use TLS certificates to encrypt traffic between:
- MongoDB hosts in a replica set, and
- Client applications and MongoDB deployments.

Certificate can be generated using cert-manager.

{{site.data.alerts.note}}

Before proceeding, ensure a `ca-issuer` ClusterIssuer is configured in your cluster. See the [cert-manager documentation](https://cert-manager.io/docs/configuration/ca/) for details on setting up a CA issuer.

{{site.data.alerts.end}}

- Step 1: Create a wildcard TLS certificate for MongoDB pods

  ```yaml
  apiVersion: cert-manager.io/v1
  kind: Certificate
  metadata:
    name: mongodb-certificate
    namespace: mongodb
  spec:
    isCA: false
    duration: 2160h    # 90d
    renewBefore: 360h  # 15d
    dnsNames:
      - "*.mongodb-svc.mongodb.svc.cluster.local"
      - mongodb-svc.mongodb.svc.cluster.local
    secretName: mongodb-cert
    privateKey:
      algorithm: RSA
      encoding: PKCS1
      size: 4096
    issuerRef:
      name: ca-issuer
      kind: ClusterIssuer
      group: cert-manager.io
  ```

  {{site.data.alerts.tip}}

  Use a wildcard DNS name (`*.mongodb-svc.mongodb.svc.cluster.local`) to cover all pod identities without needing to list each pod individually. This avoids updating the certificate when the replica count changes.

  {{site.data.alerts.end}}

- Step 2: Create MongoDB cluster with TLS enabled

  ```yaml
  apiVersion: mongodbcommunity.mongodb.com/v1
  kind: MongoDBCommunity
  metadata:
    name: mongodb
    namespace: mongodb
  spec:
    members: 3
    type: ReplicaSet
    version: "7.0.12"
    security:
      tls:
        enabled: true
        certificateKeySecretRef:
          name: mongodb-cert
        caCertificateSecretRef:
          name: mongodb-cert
      authentication:
        modes: ["SCRAM"]
    users:
      - name: admin
        db: admin
        passwordSecretRef:
          name: admin-user
        roles:
          - name: clusterAdmin
            db: admin
          - name: userAdminAnyDatabase
            db: admin
        scramCredentialsSecretName: my-scram
        connectionStringSecretName: mongodb-admin-connection
    additionalMongodConfig:
      storage.wiredTiger.engineConfig.journalCompressor: zlib
  ```

- Step 3: Test connection using TLS

  Connect to a mongod container inside a pod using kubectl:

  ```shell
  kubectl -n mongodb exec -it mongodb-0 -- /bin/bash
  ```

  Use mongosh to connect over TLS:

  ```shell
  mongosh "<connection-string>" --tls --tlsCAFile /var/lib/tls/ca/*.pem --tlsCertificateKeyFile /var/lib/tls/server/*.pem
  ```

  Where `<connection-string>` can be obtained from the operator-generated secret as described in [Connection to MongoDB](#connection-to-mongodb). TLS certificates are automatically mounted in MongoDB pods at the `/var/lib/tls/` path.


### Monitoring

MongoDB Community Operator exposes Prometheus metrics via a sidecar exporter. To enable monitoring:

1. Add the Prometheus exporter to the `MongoDBCommunity` resource:

   ```yaml
   spec:
     prometheus:
       port: 9216
       username: "admin"
       passwordSecretRef:
         name: admin-user
   ```

   The exporter runs as a sidecar container in each MongoDB pod, exposing metrics on the configured port (default `9216`).

2. Create a PodMonitor to scrape the metrics:

   ```yaml
   apiVersion: monitoring.coreos.com/v1
   kind: PodMonitor
   metadata:
     name: mongodb
     namespace: mongodb
   spec:
     selector:
       matchLabels:
         app: mongodb-svc
     podMetricsEndpoints:
       - port: metrics
         interval: 30s
         path: /metrics
   ```

Key metrics exposed:

| Metric | Description |
|--------|-------------|
| `mongodb_connections` | Number of active client connections |
| `mongodb_op_counters_total` | Operations per second (reads, writes, commands) |
| `mongodb_memory_usage_bytes` | Memory used by the MongoDB process |
| `mongodb_replset_member_state` | Replica set member state (primary/replica) |
| `mongodb_document_count` | Document count per collection |
| `mongodb_asserts_total` | Assert counts (warnings, errors) |


### Backup and restore

MongoDB Community Operator does not include a built-in backup/restore mechanism. For production deployments, consider the following approaches:

1. **Velero with CSI snapshots**: Back up MongoDB PVCs using CSI-compatible volume snapshots. This is the recommended approach for this cluster:

   ```shell
   velero backup create mongodb-backup --include-namespaces mongodb
   ```

   See the [Velero CSI Snapshot documentation](https://velero.io/docs/main/csi/) for details.

2. **mongodump/mongorestore**: For logical backups, use `mongodump` from within a pod:

   ```shell
   # Create a backup
   kubectl exec -n mongodb mongodb-0 -- mongodump \
     --uri="mongodb://admin:<password>@localhost:27017/?replicaSet=mongodb&ssl=false" \
     --archive=/tmp/mongodb-backup.archive
   kubectl cp mongodb/mongodb-0:/tmp/mongodb-backup.archive ./mongodb-backup.archive

   # Restore from backup
   kubectl cp ./mongodb-backup.archive mongodb/mongodb-0:/tmp/mongodb-backup.archive
   kubectl exec -n mongodb mongodb-0 -- mongorestore \
     --uri="mongodb://admin:<password>@localhost:27017/?replicaSet=mongodb&ssl=false" \
     --archive=/tmp/mongodb-backup.archive
   ```

3. **Scheduled backups via CronJob**: Create a Kubernetes CronJob that runs `mongodump` on a schedule and uploads the archive to S3-compatible storage.

{{site.data.alerts.tip}}

For a comprehensive backup strategy, combine CSI volume snapshots (faster restores, crash-consistent) with periodic logical dumps (finer-grained point-in-time recovery options).

{{site.data.alerts.end}}


### Upgrading MongoDB version

The MongoDB Community Operator supports rolling upgrades between minor and major versions.

1. **Patch the MongoDBCommunity resource** with the new version:

   ```shell
   kubectl patch mongodbcommunity mongodb -n mongodb \
     --type merge \
     -p '{"spec":{"version":"7.0.14"}}'
   ```

2. **Watch the rolling upgrade**:

   ```shell
   kubectl get pods -n mongodb -l app=mongodb-svc -w
   ```

   The operator performs a rolling restart, upgrading one pod at a time and waiting for each replica to become healthy before proceeding to the next.

   {{site.data.alerts.important}}

   - **Minor version upgrades** (e.g., 7.0.12 → 7.0.14): operator-managed rolling update.
   - **Major version upgrades** (e.g., 6.0.x → 7.0.x): ensure your application driver supports the new major version and review the [MongoDB upgrade documentation](https://www.mongodb.com/docs/manual/release-notes/7.0-upgrade-replica-set/) for any breaking changes.

   {{site.data.alerts.end}}


## Valkey Operator

[Valkey](https://valkey.io/) is an open-source, high-performance key-value datastore, forked from Redis 7.2.5 and now part of the Linux Foundation. It maintains full API and protocol compatibility with Redis OSS, making it a drop-in replacement.

The [Valkey Operator](https://github.com/valkey-io/valkey-operator) is a Kubernetes operator that automates the deployment and management of Valkey clusters. It handles sharding, replication, rolling upgrades, failover, TLS, and access control through a declarative `ValkeyCluster` custom resource.

{{site.data.alerts.note}}

Valkey Operator is under active development. The current API version is `v1alpha1`. See the [Valkey Operator GitHub repository](https://github.com/valkey-io/valkey-operator) for the latest release notes and feature status.

{{site.data.alerts.end}}

Valkey Operator offers the following main features:

- **Multi-shard cluster mode**: Deploy horizontally-scaled clusters with configurable shards and replicas
- **Automated failover**: Primary failure detection and automatic replica promotion
- **Rolling upgrades**: Zero-downtime version upgrades orchestrated by the operator
- **Access control (ACL)**: Per-user ACL rules including password-based authentication, command allow/deny lists, and key/channel access patterns
- **Persistence**: Operator-managed PersistentVolumeClaims (PVCs) for each Valkey node, supporting AOF and RDB persistence
- **TLS encryption**: TLS for both inter-node cluster communication and client-to-server connections
- **Monitoring**: Built-in Prometheus metrics exporter on port 9121


### Valkey Operator installation

Valkey Operator can be installed via Helm. See the [official Helm chart](https://valkey.io/valkey-helm/) for the latest version.

Installation using `Helm` (Release 3):

- **Step 1**: Add the Valkey Helm repository:

  ```shell
  helm repo add valkey https://valkey.io/valkey-helm/
  ```

- **Step 2**: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```

- **Step 3**: Create namespace

  ```shell
  kubectl create namespace databases
  ```

- **Step 4**: Install Valkey Operator

  ```shell
  helm install valkey-operator valkey/valkey-operator --namespace databases
  ```

  {{site.data.alerts.note}}

  The operator installs the `ValkeyCluster` and `ValkeyNode` CRDs in the cluster. ValkeyNode is an internal CRD managed by the operator — do not create or modify ValkeyNodes directly.

  {{site.data.alerts.end}}

- **Step 5**: Confirm that the deployment succeeded:

  ```shell
  kubectl -n databases get pod
  ```


### Deploy a Valkey database cluster

Using the Valkey Operator, a Valkey cluster is created by applying a `ValkeyCluster` custom resource.

#### Minimal Valkey cluster

The minimal spec requires only `shards` and `replicas`:

```yaml
apiVersion: valkey.io/v1alpha1
kind: ValkeyCluster
metadata:
  name: my-valkey
  namespace: databases
spec:
  shards: 2
  replicas: 1
```

This creates a 2-shard cluster with 1 replica per shard (4 pods total: 2 primaries + 2 replicas).

#### Production-ready Valkey cluster (single-shard)

For use cases that don't require sharding (e.g., caching layer), a single-shard cluster with persistence and resource limits is sufficient:

```yaml
apiVersion: valkey.io/v1alpha1
kind: ValkeyCluster
metadata:
  name: valkey
  namespace: databases
spec:
  shards: 1
  replicas: 1
  persistence:
    size: 1Gi
    storageClassName: longhorn
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi
  config:
    maxmemory-policy: allkeys-lfu
    maxmemory: "128MB"
  users:
    - name: myapp
      enabled: true
      passwordSecret:
        name: valkey-passwords
        keys:
          - MYAPP_VALKEY_PASSWORD
      commands:
        allow: ["@read", "@write", "@connection"]
        deny: ["@admin", "@dangerous"]
      keys:
        readWrite: ["myapp:*"]
```

Where:

- `spec.shards`: Number of independent data partitions (hash slots split across shards)
- `spec.replicas`: Number of read-replica copies per shard (0 for no replication)
- `spec.persistence.size`: Size of the PVC allocated to each Valkey node
- `spec.persistence.storageClassName`: Kubernetes StorageClass for PVCs (e.g., `longhorn`)
- `spec.resources`: CPU and memory requests/limits applied to each pod
- `spec.config`: Valkey server configuration directives passed to all nodes (see [Valkey configuration docs](https://valkey.io/topics/config/))
- `spec.users`: Per-user ACL rules distributed to every node via a mounted Secret

#### Multi-shard cluster with pod anti-affinity

For production deployments requiring high availability across cluster nodes, configure pod anti-affinity and topology spread constraints:

```yaml
apiVersion: valkey.io/v1alpha1
kind: ValkeyCluster
metadata:
  name: valkey-ha
  namespace: databases
spec:
  shards: 3
  replicas: 1
  persistence:
    size: 5Gi
    storageClassName: longhorn
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2048Mi
  config:
    maxmemory-policy: allkeys-lru
    maxmemory: "1536MB"
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: valkey.io/cluster
                operator: In
                values:
                  - valkey-ha
          topologyKey: kubernetes.io/hostname
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          valkey.io/cluster: valkey-ha
```


### Configuration options

#### Persistence

When `spec.persistence` is set, the operator manages a PersistentVolumeClaim for each Valkey node (each pod gets its own PVC). The Valkey server writes both AOF and RDB files to `/data` on the persistent volume.

| Persistence field | Description | Default |
|---|--------------|---------|
| `size` | PVC size (e.g., `1Gi`, `10Gi`) | Required |
| `storageClassName` | Kubernetes StorageClass name | Cluster default |
| `reclaimPolicy` | PVC reclaim policy: `Retain` or `Delete` | `Retain` |

{{site.data.alerts.important}}

`persistence` requires `workloadType: StatefulSet` (the default). Persistence settings are **immutable** after creation — `size` can only grow, and `storageClassName` cannot be changed. Plan your storage requirements before creating the cluster.

{{site.data.alerts.end}}

#### Users and ACLs

Valkey Operator supports fine-grained ACL rules through the `spec.users` field. Each user definition includes:

```yaml
users:
  - name: myapp
    enabled: true
    passwordSecret:          # Reference to an existing Kubernetes Secret
      name: valkey-passwords
      keys:
        - MYAPP_VALKEY_PASSWORD
    commands:
      allow: ["@read", "@write", "@connection"]
      deny: ["@admin", "@dangerous"]
    keys:
      readWrite: ["myapp:*"]   # Key access patterns
    channels:
      readWrite: ["myapp:*"]   # Pub/sub channel patterns
    permissions:
      - "+@all"                # Low-level ACL permission strings
```

{{site.data.alerts.note}}

Usernames starting with `_` are reserved for the operator's internal system users and cannot be used. The `passwordSecret` must be created **before** applying the `ValkeyCluster` resource.

{{site.data.alerts.end}}

To create the password secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: valkey-passwords
  namespace: databases
type: Opaque
stringData:
  MYAPP_VALKEY_PASSWORD: "your-secure-password"
```

#### Workload type

The `spec.workloadType` field controls whether Valkey nodes run as `StatefulSet` (default) or `Deployment`:

- `StatefulSet`: Required for persistence. Provides stable pod identities (`valkey-valkey-0-0-0`, `valkey-valkey-0-1-0`).
- `Deployment`: Ephemeral mode without PVCs. Pods are stateless and identities change across restarts.

{{site.data.alerts.important}}

`workloadType` is **immutable** after cluster creation. Choose `StatefulSet` for any deployment that requires data persistence.

{{site.data.alerts.end}}

#### Image and version

Pin the Valkey server version using the `spec.image` field:

```yaml
spec:
  image: valkey/valkey:9.0.0
```

If not specified, the operator default image is used. See the [Valkey Docker Hub](https://hub.docker.com/r/valkey/valkey) for available tags.

#### Pod disruption budget

The operator creates a `PodDisruptionBudget` with `maxUnavailable: 1` by default. Set to `Disabled` to opt out:

```yaml
spec:
  podDisruptionBudget: Disabled
```


### Connection to Valkey

#### Kubernetes services

The operator creates a headless Kubernetes Service for each shard, providing stable DNS names for every pod:

| Service pattern | Description |
|----------------|-------------|
| `<cluster>-<shard-index>-headless` | Headless service for shard pod discovery |
| `<cluster>-<shard-index>-<replica-index>-server` | Per-replica service (for external exposure) |

DNS name format for individual pods: `<pod-name>.<headless-service>.<namespace>.svc.cluster.local`

Example for a pod named `valkey-valkey-0-0-0`:

```shell
valkey-valkey-0-0-0.valkey-valkey-0-headless.databases.svc.cluster.local
```

#### Testing connectivity

Once the cluster is deployed, connect using the `valkey-cli` tool from within a pod:

```shell
kubectl exec -it -n databases valkey-valkey-0-0-0 -- valkey-cli -c
127.0.0.1:6379> CLUSTER INFO
127.0.0.1:6379> SET mykey "Hello Valkey"
127.0.0.1:6379> GET mykey
```

For application connections, use the headless service DNS name. If ACL users are configured, include the username and password:

```shell
valkey-cli -h valkey-valkey-0-headless.databases.svc.cluster.local -p 6379 \
  --user myapp --askpass
```

#### Connection string format

Applications can consume the following environment variable format for Valkey connections:

```
VALKEY_URL=valkey://myapp:<password>@valkey-valkey-0-headless.databases.svc.cluster.local:6379
```

{{site.data.alerts.note}}

When deploying under Istio ambient mesh with HBONE mTLS, the service DNS resolves through the ztunnel proxy automatically. No Istio-specific client configuration is needed.

{{site.data.alerts.end}}


### Securing Valkey with TLS

Valkey Operator supports TLS encryption for both cluster-internal communication and client connections.

#### Generate TLS certificates with cert-manager

First, create a certificate for the Valkey pods:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: valkey-tls-cert
  namespace: databases
spec:
  isCA: false
  duration: 2160h    # 90d
  renewBefore: 360h  # 15d
  dnsNames:
    - valkey-valkey-0-headless.databases.svc.cluster.local
    - "*.valkey-valkey-0-headless.databases.svc.cluster.local"
  secretName: valkey-tls-secret
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    size: 4096
  issuerRef:
    name: ca-issuer
    kind: ClusterIssuer
    group: cert-manager.io
```

{{site.data.alerts.note}}

The `ca-issuer` ClusterIssuer must be configured beforehand. See the [cert-manager documentation](https://cert-manager.io/docs/configuration/ca/) for details on setting up a CA issuer.

{{site.data.alerts.end}}

#### Enable TLS on the ValkeyCluster

Reference the TLS secret in the cluster spec:

```yaml
apiVersion: valkey.io/v1alpha1
kind: ValkeyCluster
metadata:
  name: valkey-tls
  namespace: databases
spec:
  shards: 1
  replicas: 1
  tls:
    secretName: valkey-tls-secret
  persistence:
    size: 1Gi
  users:
    - name: myapp
      enabled: true
      passwordSecret:
        name: valkey-passwords
        keys:
          - MYAPP_VALKEY_PASSWORD
      commands:
        allow: ["@read", "@write", "@connection"]
      keys:
        readWrite: ["myapp:*"]
```

When TLS is enabled, all inter-node cluster communication and client connections are encrypted. Connect using `--tls`:

```shell
kubectl exec -it -n databases valkey-tls-0-0-0 -- valkey-cli --tls -c
```

#### Connect from applications over TLS

Applications connecting to a TLS-enabled Valkey cluster must use the `rediss://` (TLS) scheme:

```
VALKEY_URL=rediss://myapp:<password>@valkey-tls-0-headless.databases.svc.cluster.local:6379
```

For CA verification, mount the TLS CA certificate from the secret and configure the client library accordingly.


### Monitoring

Valkey Operator includes a Prometheus metrics exporter sidecar on port `9121` that provides cluster-level and node-level metrics.

The exporter is enabled by default. To disable it:

```yaml
spec:
  exporter:
    enabled: false
```

#### Prometheus PodMonitor

Create a PodMonitor to scrape Valkey metrics with Prometheus:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: valkey
  namespace: databases
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: valkey
  podMetricsEndpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

Key metrics exposed:

| Metric | Description |
|--------|-------------|
| `valkey_connected_clients` | Number of client connections |
| `valkey_connected_slaves` | Number of connected replicas |
| `valkey_instantaneous_ops_per_sec` | Operations per second |
| `valkey_memory_used_bytes` | Memory used by Valkey |
| `valkey_keyspace_hits_total` | Total key lookup hits |
| `valkey_keyspace_misses_total` | Total key lookup misses |
| `valkey_cluster_slots_assigned` | Assigned hash slots |
| `valkey_uptime_in_seconds` | Server uptime |


### Backup and persistence management

#### PersistentVolumeClaims

Each ValkeyNode pod gets its own PVC for storing AOF and RDB files. The PVCs follow the naming pattern `<pod-name>-data`:

```shell
kubectl get pvc -n databases
NAME                                   STATUS   VOLUME                    CAPACITY   STORAGECLASS
data-valkey-valkey-0-0-0               Bound    pvc-abc123                1Gi        longhorn
data-valkey-valkey-0-1-0               Bound    pvc-def456                1Gi        longhorn
```

#### Reclaim policy

By default, PVCs use `reclaimPolicy: Retain`, meaning data survives cluster deletion. To automatically delete PVCs when the cluster is removed:

```yaml
spec:
  persistence:
    size: 1Gi
    reclaimPolicy: Delete
```

#### Manual backup using valkey-cli

For ad-hoc backups, trigger a snapshot and copy the RDB file:

```shell
# Trigger a save on the primary pod
kubectl exec -n databases valkey-valkey-0-0-0 -- valkey-cli SAVE

# Copy the RDB file from the PVC
kubectl cp databases/valkey-valkey-0-0-0:/data/dump.rdb ./valkey-backup.rdb
```

{{site.data.alerts.note}}

The operator does not yet include native backup/restore or integration with S3-compatible object stores. For automated backup workflows, consider using Velero with CSI snapshots, or scheduling periodic `valkey-cli BGSAVE` commands and copying the RDB files off-cluster.

{{site.data.alerts.end}}


### Troubleshooting

#### Cluster stuck in Reconciling state

The most common failure mode is the cluster entering a perpetual `Reconciling` state, typically caused by stale IP addresses in the cluster topology file after pod restarts.

**Symptoms**:

```shell
$ kubectl get valkeycluster -n databases
NAME     STATE          REASON         SHARDS   READY SHARDS   AGE
valkey   Reconciling    Reconciling    1        0              2d
```

- `Ready` condition is `False` with message `"Waiting for replicas to sync with primary"`
- Operator logs repeat `"replica not yet in sync, requeue.."`
- Replica pod logs show repeated connection failures to a stale primary IP

**Root cause**: When pods restart and receive new IP addresses from the CNI, the `nodes.conf` file persisted on the PVC retains old IP addresses from the previous run. The operator detects the mismatch but may not issue corrective `CLUSTER MEET` / `CLUSTER FORGET` commands automatically, especially on clusters created with older operator versions (v0.1.0).

**Recovery procedure**:

1. Verify the stale IP condition:

   ```shell
   # Check pod IPs
   kubectl get pods -n databases -l valkey.io/cluster=valkey -o wide

   # Check replication status on each pod
   kubectl exec -n databases valkey-valkey-0-0-0 -c server -- valkey-cli INFO replication
   kubectl exec -n databases valkey-valkey-0-1-0 -c server -- valkey-cli INFO replication

   # Inspect nodes.conf for stale IPs
   kubectl exec -n databases valkey-valkey-0-0-0 -c server -- cat /data/nodes.conf
   kubectl exec -n databases valkey-valkey-0-1-0 -c server -- cat /data/nodes.conf
   ```

2. Fix the cluster topology at runtime:

   ```shell
   # Get current pod IPs
   PRIMARY_IP=$(kubectl get pod -n databases valkey-valkey-0-0-0 -o jsonpath='{.status.podIP}')
   REPLICA_IP=$(kubectl get pod -n databases valkey-valkey-0-1-0 -o jsonpath='{.status.podIP}')

   # Set correct announce IPs
   kubectl exec -n databases valkey-valkey-0-0-0 -c server -- valkey-cli CONFIG SET cluster-announce-ip "$PRIMARY_IP"
   kubectl exec -n databases valkey-valkey-0-1-0 -c server -- valkey-cli CONFIG SET cluster-announce-ip "$REPLICA_IP"

   # Re-establish cluster topology
   kubectl exec -n databases valkey-valkey-0-0-0 -c server -- valkey-cli CLUSTER MEET "$REPLICA_IP" 6379
   ```

3. Verify recovery:

   ```shell
   kubectl get valkeycluster -n databases valkey
   # Should show STATE=Ready, READY SHARDS=1
   ```

{{site.data.alerts.important}}

Operator v0.2.0 and later inject `--cluster-announce-ip $(POD_IP)` via the Kubernetes downward API, which prevents self-IP staleness on restarts. However, **peer IPs** in `nodes.conf` on pre-existing PVCs may still be stale after pod IP changes. For a permanent fix, recreate the ValkeyCluster (or its PVCs) after upgrading the operator, so that `nodes.conf` starts fresh with correct addresses.

{{site.data.alerts.end}}

#### Checking operator logs

```shell
kubectl logs -n databases deployment/valkey-operator --tail 50 -f
```

#### Checking cluster health from inside a pod

```shell
kubectl exec -it -n databases valkey-valkey-0-0-0 -- valkey-cli -c

# Inside valkey-cli:
CLUSTER INFO
CLUSTER NODES
INFO replication
INFO stats
```

{{site.data.alerts.tip}}

For an automated detection and recovery of stale IP conditions, use the recovery script included in the repository at `scripts/recover-valkey-stale-ip.sh`. The script is idempotent — safe to run repeatedly on healthy clusters.

```shell
bash scripts/recover-valkey-stale-ip.sh --namespace databases --cluster valkey
```

{{site.data.alerts.end}}
