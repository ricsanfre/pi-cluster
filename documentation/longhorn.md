# LongHorn

[Longhorn](https://longhorn.io/) is a distributed block storage system for Kubernetes. Lightweight, reliable and easy-to-use can be used as an alternative to Rook/Cephs. It is opensource software initially developed by Rancher Labs supporting AMD64 and ARM64 architectures that can be easily integrated with K3S.


## LongHorn Installation

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
- Step 3: Install Longhorn in the longhorn-system namespace.
    ```
    helm install longhorn longhorn/longhorn --namespace longhorn-system
    ```
- Step 4: Confirm that the deployment succeeded, run:
    ```
    kubectl -n longhorn-system get pod
    ```
