# K3S Installation

Kubernetes cluster will be installed in node1-node4. `node1` will have control-plane role while `node2-4` will be workers.

Control-plane node will be configured so no load is deployed in it.

## Prerequisites for all nodes

Enable cgroup via boot commandline if not already enabled for Ubuntu on a Raspberry Pi

- Step 1: Modify file `/boot/firmware/cmdline.txt` to include the line:

    cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory

- Step 2: Reboot the server

## Master installation (node1)

- Step 1: Installing K3S control plane node
    For installing the master node execute the following command:
```
    curl -sfL https://get.k3s.io | K3S_TOKEN=<server_token> sh -s - server --write-kubeconfig-mode '0644' --node-taint 'k3s-controlplane=true:NoExecute'
```
- **server_token** is shared secret within the cluster for allowing connection of worker nodes
- **--write-kubeconfig-mode '0644'** gives read permissions to kubeconfig file located in `/etc/rancher/k3s/k3s.yaml`
- **--node-taint 'k3s-controlplane=true:NoExecute'** makes master node not to run any pod. By default master node is a worker node.

- Step 2: Install Helm utility

Kubectl is installed as part of the k3s server installation (`/usr/local/bin/kubectl`), but helm need to be installed following this [instructions](https://helm.sh/docs/intro/install/).


- Step 3: Copy k3s configuration file to Kubernets default directory (`$HOME/.kube/config`), so `kubectl` and `helm` utilities can find the way to connect to the cluster.

   ```shell
   mkdir $HOME/.kube
   cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/.
   ```

## Workers installation (node2-node4)

- Step 1: Installing K3S worker node
    For installing the master node execute the following command:
```
    curl -sfL https://get.k3s.io | K3S_URL='https://<k3s_master_ip>:6443' K3S_TOKEN=<server_token> sh -s - --node-label 'node_type=worker'
```
- **server_token** is shared secret within the cluster for allowing connection of worker nodes
- **k3s_master_ip** is the k3s master node ip
- **--node-label 'node_type=worker'** add a custom label `node_type` to the worker node.

- Step 2: Specify role label for worker nodes

  From master node (`node1`) assign a role label to worker nodes, so when executing `kubectl get nodes` command ROLE column show worker role for workers nodes.

  ```
  kubectl label nodes <worker_node_name> kubernetes.io/role=worker
  ```

## Configure master node to enable remote deployment of pods with Ansible

Ansible collection for managing kubernetes cluster is available: [kubernetes.core ansible collection](https://github.com/ansible-collections/kubernetes.core).

For using this ansible collection from the `pimaster` node, python package `kubernetes` need to be installed on k3s master node

    pip3 install kubernetes


## Remote Access

To enable remote access to the cluster using kubectl and helm applications follow the following procedure

- Step 1:  Install Helm and kubectl utilities

- Step 2: Copy k3s configuration file to (`$HOME/.kube/config`)

- Step 3: Modify `k3s.yaml` configuration file for using the IP address instead of localhost

- Step 4: Enable HTTPS connectivity on port 6443 between the server and the k3s control node


## Reset the cluster

To reset the cluster execute k3s uninstall script in master and worker nodes

On each worker node (node2-node4) execute:

```
  /usr/local/bin/k3s-agent-uninstall.sh
```
On master node (node1) execute

```
/usr/local/bin/k3s-uninstall.sh
```