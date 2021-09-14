# LongHorn

[Longhorn](https://longhorn.io/) is a distributed block storage system for Kubernetes. Lightweight, reliable and easy-to-use can be used as an alternative to Rook/Cephs. It is opensource software initially developed by Rancher Labs supporting AMD64 and ARM64 architectures that can be easily integrated with K3S.


## LongHorn Installation


### Open-iscsi Requirement

LongHorn requires that `open-iscsi` package has been installed on all the nodes of the Kubernetes cluster, and `iscsid` daemon is running on all the nodes.

Longhorn uses internally iSCSI to expose the block device presented by the Longhorn volume to the kuberentes pods. So the iSCSI initiator need to be setup on each node. Longhorn is acting as iSCSI Target exposing Longhorn Volumes that are presented to the node by the iSCSI Initiator running on the same node as /dev/longhorn/ block devices. For implementation details see (https://github.com/longhorn/longhorn-engine).


![longhorn](https://github.com/longhorn/longhorn-engine/raw/master/overview.png)

Since all cluster nodes (`node1-node4`) have been already configured as iSCSI Initiators all pre-requisties are met.


### Installation procedure using Helm

Installation using `Helm` (Release 3):

- Step 1: Add the Longhorn Helm repository:
    ```
    helm repo add longhorn https://charts.longhorn.io
    ```
- Step2: Fetch the latest charts from the repository:
    ```
    helm repo update
    ```
- Step 3: Create namespace
    ```
    kubectl create namespace longhorn-system
    ```
- Step 3: Install Longhorn in the longhorn-system namespace, setting `/storage` as default path for storing replicas
    ```
    helm install longhorn longhorn/longhorn --namespace longhorn-system --set defaultSettings.defaultDataPath="/storage"
    ```
- Step 4: Confirm that the deployment succeeded, run:
    ```
    kubectl -n longhorn-system get pod
    ```

### Configuring acces to Longhorn UI

Create a Ingress rule to make Longhorn front-end available through the Ingress Controller (Traefik) using a specific URL (`storage.picluster.ricsanfre.com`), mapped by DNS to Traefik Load Balancer external IP.

- Step 1. Create a manifest file `longhorn_ingress.yml`

```yml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: longhorn-ingress
  namespace: longhorn-system
  annotations:
    kubernetes.io/ingress.class: traefik
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

    kubectl apply -f longhorn_ingress.yml

### Setting Longhorn as default Kubernetes StorageClass

By default K3S comes with Rancher’s Local Path Provisioner and this enables the ability to create persistent volume claims out of the box using local storage on the respective node.

In order to use Longhorn as default storageClass whenever a new Helm is installed, Local Path Provisioner need to be removed from default storage class.

```
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```