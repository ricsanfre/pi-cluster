---
title: Minio S3 Object Storage Service
permalink: /docs/minio/
description: How to deploy a Minio S3 object storage service in our Raspberry Pi Kubernetes Cluster.
last_modified_at: "03-07-2023"
---

Minio will be deployed as a Kuberentes service providing Object Store S3-compatile backend for other Kubernetes Services (Loki, Tempo, Mimir, etc. )

Official [Minio Kubernetes installation documentation](https://min.io/docs/minio/kubernetes/upstream/index.html) uses Minio Operator to deploy and configure a multi-tenant S3 cloud service.

Instead of using Minio Operator, [Vanilla Minio helm chart](https://github.com/minio/minio/tree/master/helm/minio) will be used. Not need to support multi-tenant installations and Vanilla Minio helm chart supports also the automatic creation of buckets, policies and users. Minio Operator creation does not automate this process.


## Minio installation


Installation using `Helm` (Release 3):

- Step 1: Add the Minio Helm repository:

  ```shell
  helm repo add minio https://charts.min.io/
  ```
- Step2: Fetch the latest charts from the repository:

  ```shell
  helm repo update
  ```
- Step 3: Create namespace

  ```shell
  kubectl create namespace minio
  ```

- Step 3: Create Minio secret


  The following secret need to be created, containing Minio's root user and password, and keys from others users that are going to be provisioned automatically when installing the helm chart (loki, tempo):
  ```yml
  apiVersion: v1
  kind: Secret
  metadata:
    name: minio-secret
    namespace: minio
  type: Opaque
  data:
    rootUser: < minio_root_user | b64encode >
    rootPassword: < minio_root_key | b64encode >
    lokiPassword: < minio_loki_key | b64encode >
    tempoPassword: < minio_tempo_key | b64encode >
  ```


- Step 4: Create file `minio-values.yml`

  ```yml
  # Get root user/password from secret
  existingSecret: minio-secret

  # Number of drives attached to a node
  drivesPerNode: 1
  # Number of MinIO containers running
  replicas: 3
  # Number of expanded MinIO clusters
  pools: 1

  # Run minio server only on amd64 nodes
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/arch
            operator: In
            values:
            - amd64

  # Persistence
  persistence:
    enabled: true
    storageClass: "longhorn"
    accessMode: ReadWriteOnce
    size: 10Gi

  # Resource request
  resources:
    requests:
      memory: 1Gi

  # Minio Buckets
  buckets:
    - name: k3s-loki
      policy: none
    - name: k3s-tempo
      policy: none

  # Minio Policies
  policies:
    - name: loki
      statements:
        - resources:
            - 'arn:aws:s3:::k3s-loki'
            - 'arn:aws:s3:::k3s-loki/*'
          actions:
            - "s3:DeleteObject"
            - "s3:GetObject"
            - "s3:ListBucket"
            - "s3:PutObject"
    - name: tempo
      statements:
        - resources:
            - 'arn:aws:s3:::k3s-tempo'
            - 'arn:aws:s3:::k3s-tempo/*'
          actions:
            - "s3:DeleteObject"
            - "s3:GetObject"
            - "s3:ListBucket"
            - "s3:PutObject"
            - "s3:GetObjectTagging"
            - "s3:PutObjectTagging"
  # Minio Users
  users:
    - accessKey: loki
      existingSecret: minio-secret
      existingSecretKey: lokiPassword
      policy: loki
    - accessKey: tempo
      existingSecret: minio-secret
      existingSecretKey: tempoPassword
      policy: tempo
  ```

  With this configuration:

  - Minio cluster of 3 nodes (`replicas`) is created with 1 drive per node (`drivesPerNode`) of 10Gb (`persistence`)

  - Root user and passwork is obtained from the secret created in Step 3 (`existingSecret`).

  - Memory resources for each replica is set to 1GB (`resources.requests.memory`). Default config is 16GB which is not possible in a Raspberry Pi.

  - Minio PODs are deployed only on x86 nodes (`affinity`). Minio does not work properly when mixing nodes of different architectures. See [issue #137](https://github.com/ricsanfre/pi-cluster/issues/137)

  - Buckets (`buckets`), users (`users`) and policies (`policies`) are created for Loki and Tempo

- Step 5: Install Minio in `minio` namespace
  ```shell
  helm install minio minio -f minio-values.yml --namespace minio
  ```
- Step 6: Check status of Loki pods
  ```shell
  kubectl get pods -l app.kubernetes.io/name=minio -n minio
  ```


## Configuring Ingress

Create a Ingress rule to make Minio console and service API available through the Ingress Controller (Traefik) using a specific URLs (`minio.picluster.ricsanfre.com` and `s3.picluster.ricsanfre.com`), mapped by DNS to Traefik Load Balancer external IP.

Minio backend is deployed in insecure mode (TLS is not activated) and thus Ingress resource will be configured to enable HTTPS (Traefik TLS end-point). The following configuration assumes that, Traefik is already configured for redirecting all HTTP traffic to HTTPS.


- Step 1. Create a manifest file `minio_ingress.yml` for providing access to Minio API.

  ```yml
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: minio-ingress
    namespace: minio
    annotations:
      # HTTPS as entry point
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      # Enable TLS
      traefik.ingress.kubernetes.io/router.tls: "true"
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      cert-manager.io/cluster-issuer: ca-issuer
      cert-manager.io/common-name: s3.picluster.ricsanfre.com
  spec:
    tls:
      - hosts:
          - s3.picluster.ricsanfre.com
        secretName: minio-tls
    rules:
      - host: s3.picluster.ricsanfre.com
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: minio
                  port:
                    number: 9000
  ```

- Step 2. Create a manifest file `minio_console_ingress.yml` for providing access to Minio Console.

  ```yml
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: minio-console-ingress
    namespace: minio
    annotations:
      # HTTPS as entry point
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      # Enable TLS
      traefik.ingress.kubernetes.io/router.tls: "true"
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      cert-manager.io/cluster-issuer: ca-issuer
      cert-manager.io/common-name: minio.picluster.ricsanfre.com
  spec:
    tls:
      - hosts:
          - minio.picluster.ricsanfre.com
        secretName: minio-console-tls
    rules:
      - host: minio.picluster.ricsanfre.com
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: minio-console
                  port:
                    number: 9001
```