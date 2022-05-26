---
title: Distributed Storage (Longhorn)
permalink: /docs/longhorn/
description: How to deploy distributed block storage solution based on Longhorn in our Raspberry Pi Kubernetes Cluster.
last_modified_at: "25-02-2022"
---

K3s comes with a default [Local Path Provisioner](https://rancher.com/docs/k3s/latest/en/storage/) that allows creating a PersistentVolumeClaim backed by host-based storage. This means the volume is using storage on the host where the pod is located. If the POD need to be started on a different node it won`t be able to access the data.

A distributed block storage is needed to handle this issue. With distributed block storage, the storage is decouple from the pods, and the PersistentVolumeClaim can be mounted to the pod regardless of where the pod is running.

[Longhorn](https://longhorn.io/) is a distributed block storage system for Kubernetes. Lightweight, reliable and easy-to-use can be used as an alternative to Rook/Cephs. It is opensource software initially developed by Rancher Labs supporting AMD64 and ARM64 architectures that can be easily integrated with K3S.

## LongHorn Installation

### Open-iscsi Requirement

LongHorn requires that `open-iscsi` package has been installed on all the nodes of the Kubernetes cluster, and `iscsid` daemon is running on all the nodes.

Longhorn uses internally iSCSI to expose the block device presented by the Longhorn volume to the kuberentes pods. So the iSCSI initiator need to be setup on each node. Longhorn, acting as iSCSI Target, exposes Longhorn Volumes that are discovered by the iSCSI Initiator running on the node as `/dev/longhorn/` block devices. For implementation details see [Longhorn enfine document](https://github.com/longhorn/longhorn-engine).

![longhorn](https://github.com/longhorn/longhorn-engine/raw/master/overview.png)

Since all cluster nodes (`node1-node4`) have been already configured as iSCSI Initiators all pre-requisties are met.

### Longhorn issues with Multipath

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
- Step 3: Install Longhorn in the longhorn-system namespace, setting `/storage` as default path for storing replicas

  ```shell
  helm install longhorn longhorn/longhorn --namespace longhorn-system --set defaultSettings.defaultDataPath="/storage"
  ```
- Step 4: Confirm that the deployment succeeded, run:

  ```shell
  kubectl -n longhorn-system get pod
  ```

## Configuring acces to Longhorn UI

Create a Ingress rule to make Longhorn front-end available through the Ingress Controller (Traefik) using a specific URL (`storage.picluster.ricsanfre.com`), mapped by DNS to Traefik Load Balancer external IP.

Longhorn backend is providing not secure communications (HTTP traffic) and thus Ingress resource will be configured to enable HTTPS (Traefik TLS end-point) and redirect all HTTP traffic to HTTPS.
Since Longhorn frontend does not provide any authentication mechanism, Traefik HTTP basic authentication will be configured.

There is a known issue with accessing Longhorn UI from Traefik 2.x that makes Longhorn APIs calls fail. Traefik 2.x ingress controller does not set the WebSocket headers and a specific middleware to route to the Longhorn UI must be specified. See [Longhorn documentation: "Troubleshooting Traefik 2.x as ingress controller"](https://longhorn.io/kb/troubleshooting-traefik-2.x-as-ingress-controller/) to know how to solve this particular issue.


- Step 1. Create a manifest file `longhorn_ingress.yml`

  Two Ingress resources will be created, one for HTTP and other for HTTPS. Traefik middlewares, HTTPS redirect, basic authentication and X-Forwareded-Proto headers will be used.
  
  ```yml
  # Solving API issue. 
  ---
  apiVersion: traefik.containo.us/v1alpha1
  kind: Middleware
  metadata:
    name: svc-longhorn-headers
    namespace: longhorn-system
  spec:
    headers:
      customRequestHeaders:
        X-Forwarded-Proto: "https"
  ---
  # HTTPS Ingress
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: longhorn-ingress
    namespace: longhorn-system
    annotations:
      # HTTPS as entry point
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      # Enable TLS
      traefik.ingress.kubernetes.io/router.tls: "true"
      # Use Basic Auth Midleware configured
      traefik.ingress.kubernetes.io/router.middlewares: 
        traefik-system-basic-auth@kubernetescrd,
        longhorn-system-svc-longhorn-headers@kubernetescrd
      # Enable cert-manager to create automatically the SSL certificate and store in Secret
      cert-manager.io/cluster-issuer: ca-issuer
      cert-manager.io/common-name: storage.picluster.ricsanfre.com
  spec:
    tls:
    - hosts:
      - storage.picluster.ricsanfre.com
      secretName: storage-tls
    rules:
    - host: storage.picluster.ricsanfre.com
      http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: longhorn-frontend
              port:
                number: 80
  ---
  # http ingress for http->https redirection
  kind: Ingress
  apiVersion: networking.k8s.io/v1
  metadata:
    name: longhorn-redirect
    namespace: longhorn-system
    annotations:
      # Use redirect Midleware configured
      traefik.ingress.kubernetes.io/router.middlewares: traefik-system-redirect@kubernetescrd
      # HTTP as entrypoint
      traefik.ingress.kubernetes.io/router.entrypoints: web
  spec:
    rules:
      - host: storage.picluster.ricsanfre.com
        http:
          paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: longhorn-frontend
                port:
                  number: 80
  ```

- Step 2. Apply the manifest file

  ```shell
  kubectl apply -f longhorn_ingress.yml
  ```

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


## Setting Longhorn as default Kubernetes StorageClass

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

Both Local-Path and longhor are defined as default storage classes:

Remove Local path from default storage classes with the command:

```shell
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

Procedure is explained in kubernetes documentation: ["Change default Storage Class"](https://kubernetes.io/docs/tasks/administer-cluster/change-default-storage-class/).
