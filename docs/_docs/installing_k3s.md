---
title: K3S Installation
permalink: /docs/k3s_installation/
redirect_from: /docs/k3s_installation.md
---


K3S is a lightweight kubernetes built for IoT and edge computing, provided by the company Rancher. The following picture shows the K3S architecture

![K3S Architecture](images/how-it-works-k3s-revised.svg)

In K3S all kubernetes processes are consolidated within one single binary. The binary is deployed on servers with two different k3s roles (k3s-server or k3s-agent).

- k3s-server: starts all kubernetes control plane processes (API, Scheduler and Controller) and worker proceses (Kubelet and kube-proxy), so master node can be used also as worker node.
- k3s-agent: consolidating all kuberentes worker processes (Kubelet and kube-proxy).


Kubernetes cluster will be installed in node1-node4. `node1` will have control-plane role while `node2-4` will be workers.

Control-plane node will be configured so no load is deployed in it.

## Installation prerequisites for all nodes

Enable `cgroup` via boot commandline, if not already enabled, for Ubuntu on a Raspberry Pi

- Step 1: Modify file `/boot/firmware/cmdline.txt` to include the line:

    ```
    cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory
    ```

- Step 2: Enable iptables to see bridged traffic

    Load br_netfilter kernel module an modify settings to let iptable see bridged traffic

    ```shell
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
    br_netfilter
    EOF
    
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-ip6tables = 1
    net.bridge.bridge-nf-call-iptables = 1
    EOF

    sudo sysctl --system
    ```
- Step 3: Reboot the server


## Master installation (node1)

- Step 1: Installing K3S control plane node
    For installing the master node execute the following command:
```
    curl -sfL https://get.k3s.io | K3S_TOKEN=<server_token> sh -s - server --write-kubeconfig-mode '0644' --node-taint 'node-role.kubernetes.io/master=true:NoSchedule' --disable 'servicelb' --kube-controller-manager-arg 'bind-address=0.0.0.0' --kube-controller-manager-arg 'address=0.0.0.0' --kube-proxy-arg 'metrics-bind-address=0.0.0.0' --kube-scheduler-arg 'bind-address=0.0.0.0' --kube-scheduler-arg 'address=0.0.0.0'
```
- **server_token** is shared secret within the cluster for allowing connection of worker nodes
- **--write-kubeconfig-mode '0644'** gives read permissions to kubeconfig file located in `/etc/rancher/k3s/k3s.yaml`
- **--node-taint 'node-role.kubernetes.io/master=true:NoSchedule'** makes master node not schedulable to run any pod. Only pods marked with specific tolerance will be scheduled on master node. 
- **--disable servicelb** to disable default service load balancer installed by K3S (Klipper Load Balancer)
- **--kube-controller-manager.arg**, **--kube-schedueler-arg** and **--kube-proxy-arg** to bind those components not only to 127.0.0.1 and enable metrics scraping from external node.


> NOTE 1: 

> Avoid the use of documented taint `k3s-controlplane=true:NoExecute` to avoid deployment of pods on master node. We are interested on running certain pods on master node, like the ones needed to collect logs/metrics from the master node.
>
> K3S common services: core-dns, metric-service, service-lb are configured with tolerance to `node-role.kubernetes.io/master` taint, so they will be scheduled on master node.
>
> Metal-lb, load balancer to be used, as well use this tolerance, so daemonset metallb-speaker will be deployed on node1. Daemonset pod like fluentd will have the specific tolerance to be able to get logs from master node.
> 
> See K3S PR introducing this feature: https://github.com/k3s-io/k3s/pull/1275 


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

On each worker node (`node2-node4`) execute:

```
  /usr/local/bin/k3s-agent-uninstall.sh
```
On master node (node1) execute

```
/usr/local/bin/k3s-uninstall.sh
```

## Ansible Automation

K3s cluster installation and reset procedures have been automated with Asible playbooks

For installing the cluster execute: 
```
ansible-playbook k3s_install.yml
```

For resetting the cluster execute:
```
ansible-playbook k3s_reset.yml
```