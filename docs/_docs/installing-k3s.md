---
title: K3S Installation
permalink: /docs/k3s-installation/
description: How to install K3s, a lightweight kubernetes distribution, in our Raspberry Pi Kuberentes cluster.
last_modified_at: "01-02-2023"
---


K3S is a lightweight kubernetes built for IoT and edge computing, provided by the company Rancher. The following picture shows the K3S architecture (source [K3S](https://k3s.io/)).

![K3S Architecture](/assets/img/how-it-works-k3s-revised.svg)

In K3S all kubernetes processes are consolidated within one single binary. The binary is deployed on servers with two different k3s roles (k3s-server or k3s-agent).

- k3s-server: starts all kubernetes control plane processes (API, Scheduler and Controller) and worker proceses (Kubelet and kube-proxy), so master node can be used also as worker node.
- k3s-agent: consolidating all kuberentes worker processes (Kubelet and kube-proxy).

Kubernetes cluster will be installed in node1-node5. `node1` will have control-plane role while `node2-5` will be workers.

Control-plane node will be configured so no load is deployed in it.

## Installation prerequisites for all nodes

Enable `cgroup` via boot commandline, if not already enabled, for Ubuntu on a Raspberry Pi

- Step 1: Modify file `/boot/firmware/cmdline.txt` to include the line:

    ```
    cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory
    ```

- Step 2: Enable iptables to see bridged traffic

    Load `br_netfilter` kernel module an modify settings to let `iptables` see bridged traffic

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

- Step 1: Prepare K3S kubelet configuration file

  Create file `/etc/rancher/k3s/kubelet.config`

  ```yml
  apiVersion: kubelet.config.k8s.io/v1beta1
  kind: KubeletConfiguration
  shutdownGracePeriod: 30s
  shutdownGracePeriodCriticalPods: 10s
  ```

  This kubelet configuration enables new kubernetes feature [Graceful node shutdown](https://kubernetes.io/blog/2021/04/21/graceful-node-shutdown-beta/). This feature is available since Kuberentes 1.21, it is still in beta status, and it ensures that pods follow the normal [pod termination process](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination) during the node shutdown.

  See further details in ["Kuberentes documentation: Graceful-shutdown"](https://kubernetes.io/docs/concepts/architecture/nodes/#graceful-node-shutdown).


  {{site.data.alerts.note}}

  After installation, we will see that `kubelet` (k3s-server proccess) has taken [systemd's inhibitor lock](https://www.freedesktop.org/wiki/Software/systemd/inhibit/), which is the mechanism used by Kubernetes to implement the gracefully shutdown the pods.

    ```shell  
    sudo systemd-inhibit --list
    WHO                          UID USER PID  COMM            WHAT     WHY                                                       MODE 
    ModemManager                 0   root 728  ModemManager    sleep    ModemManager needs to reset devices                       delay
    Unattended Upgrades Shutdown 0   root 767  unattended-upgr shutdown Stop ongoing upgrades or perform upgrades before shutdown delay
    kubelet                      0   root 4474 k3s-server      shutdown Kubelet needs time to handle node shutdown                delay
    ```

  {{site.data.alerts.end}}

- Step 2: Installing K3S control plane node

    For installing the master node execute the following command:

    ```shell
    curl -sfL https://get.k3s.io | K3S_TOKEN=<server_token> sh -s - server --write-kubeconfig-mode '0644' --node-taint 'node-role.kubernetes.io/master=true:NoSchedule' --disable 'servicelb' --disable 'traefik' --disable 'local-path' --kube-controller-manager-arg 'bind-address=0.0.0.0' --kube-proxy-arg 'metrics-bind-address=0.0.0.0' --kube-scheduler-arg 'bind-address=0.0.0.0' --kubelet-arg 'config=/etc/rancher/k3s/kubelet.config' --kube-controller-manager-arg 'terminated-pod-gc-threshold=10'
    ```
    Where:
    - `server_token` is shared secret within the cluster for allowing connection of worker nodes
    - `--write-kubeconfig-mode '0644'` gives read permissions to kubeconfig file located in `/etc/rancher/k3s/k3s.yaml`
    - `--node-taint 'node-role.kubernetes.io/master=true:NoSchedule'` makes master node not schedulable to run any pod. Only pods marked with specific tolerance will be scheduled on master node. 
    - `--disable servicelb` to disable default service load balancer installed by K3S (Klipper Load Balancer). Metallb will be used instead.
    - `--disable local-storage` to disable local storage persistent volumes provider installed by K3S (local-path-provisioner). Longhorn will be used instead
    - `--disable traefik` to disable default ingress controller installed by K3S (Traefik). Traefik will be installed from helm chart.
    - `--kube-controller-manager.arg`, `--kube-scheduler-arg` and `--kube-proxy-arg` to bind those components not only to 127.0.0.1 and enable metrics scraping from a external node.
    - `--kubelet-arg 'config=/etc/rancher/k3s/kubelet.config'` provides kubelet configuraion parameters. See [Kubernetes Doc: Kubelet Config File](https://kubernetes.io/docs/tasks/administer-cluster/kubelet-config-file/)
    - `--kube-controller-manager-arg 'terminated-pod-gc-threshold=10'`. Setting limit to 10  terminated pods that can exist before the terminated pod garbage collector starts deleting terminated pods. See [Kubernetes Doc: Pod Garbage collection](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-garbage-collection)


    <br>
    
    {{site.data.alerts.important}}

    Avoid the use of documented taint `k3s-controlplane=true:NoExecute` used to avoid deployment of pods on master node. We are interested on running certain pods on master node, like the ones needed to collect logs/metrics from the master node.

    Instead, use the taint `node-role.kubernetes.io/master=true:NoSchedule`.

    K3S common services: core-dns, metric-service, service-lb are configured with tolerance to `node-role.kubernetes.io/master` taint, so they will be scheduled on master node.

    Metal-lb, load balancer to be used within the cluster, uses this tolerance as well, so daemonset metallb-speaker can be deployed on `node1`. Other Daemonset pods, like fluentd, have to specify this specific tolerance to be able to get logs from master node.
    
    See this [K3S PR](https://github.com/k3s-io/k3s/pull/1275) where this feature was introduced.  
    {{site.data.alerts.end}}

- Step 3: Install Helm utility

    Kubectl is installed as part of the k3s server installation (`/usr/local/bin/kubectl`), but helm need to be installed following this [instructions](https://helm.sh/docs/intro/install/).

- Step 4: Copy k3s configuration file to Kubernets default directory (`$HOME/.kube/config`), so `kubectl` and `helm` utilities can find the way to connect to the cluster.

   ```shell
   mkdir $HOME/.kube
   cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/.
   ```

## Workers installation (node2-node4)


- Step 1: Prepare K3S kubelet configuration file

  Create file `/etc/rancher/k3s/kubelet.config`

  ```yml
  apiVersion: kubelet.config.k8s.io/v1beta1
  kind: KubeletConfiguration
  shutdownGracePeriod: 30s
  shutdownGracePeriodCriticalPods: 10s
  ```

- Step 2: Installing K3S worker node

  For installing the master node execute the following command:

  ```shell
  curl -sfL https://get.k3s.io | K3S_URL='https://<k3s_master_ip>:6443' K3S_TOKEN=<server_token> sh -s - --node-label 'node_type=worker' --kubelet-arg 'config=/etc/rancher/k3s/kubelet.config' --kube-proxy-arg 'metrics-bind-address=0.0.0.0'
  ```
  Where:
  - `server_token` is shared secret within the cluster for allowing connection of worker nodes
  - `k3s_master_ip` is the k3s master node ip
  - `--node-label 'node_type=worker'` add a custom label `node_type` to the worker node.
  - `--kubelet-arg 'config=/etc/rancher/k3s/kubelet.config'` provides kubelet configuraion parameters. See [Kubernetes Doc: Kubelet Config File](https://kubernetes.io/docs/tasks/administer-cluster/kubelet-config-file/)
  - `--kube-proxy-arg 'metrics-bind-address=0.0.0.0'` to enable kube-proxy metrics scraping from a external node

  <br>
 
- Step 3: Specify role label for worker nodes

  From master node (`node1`) assign a role label to worker nodes, so when executing `kubectl get nodes` command ROLE column show worker role for workers nodes.

  ```shell
  kubectl label nodes <worker_node_name> kubernetes.io/role=worker
  ```

## Configure master node to enable remote deployment of pods with Ansible

Ansible collection for managing kubernetes cluster is available: [kubernetes.core ansible collection](https://github.com/ansible-collections/kubernetes.core).

For using this ansible collection from the `pimaster` node, python package `kubernetes` need to be installed on k3s master node

```shell
pip3 install kubernetes
```

## Remote Access

To enable remote access to the cluster using `kubectl` and `helm` applications follow the following procedure

- Step 1:  Install `helm` and `kubectl` utilities

- Step 2: Copy k3s configuration file, located in `/etc/rancher/k3s/k3s.yaml`, to `$HOME/.kube/config`.

- Step 3: Modify `k3s.yaml` configuration file for using the IP address instead of localhost

- Step 4: Enable HTTPS connectivity on port 6443 between the server and the k3s control node


## K3S Automatic Upgrade

K3s cluster upgrade can be automated using Rancher's system-upgrade-controller. This controller uses a custom resource definition (CRD), `Plan`, to schedule upgrades based on the configured plans

See more details in [K3S Automated Upgrades documentation](https://docs.k3s.io/upgrades/automated)

- Step 1. Install Rancher's system-upgrade-controller

  ```shell
  kubectl apply -f https://github.com/rancher/system-upgrade-controller/releases/latest/download/system-upgrade-controller.yaml
  ```

- Step 2. Configure upgrade plans

  At least two upgrade plans need to be configured: a plan for upgrading server (master) nodes and a plan for upgrading agent (worker) nodes.

  Plan for master: `k3s-master-upgrade.yml`

  ```yml
  apiVersion: upgrade.cattle.io/v1
  kind: Plan
  metadata:
    name: k3s-server
    namespace: system-upgrade
    labels:
      k3s-upgrade: server
  spec:
    nodeSelector:
      matchExpressions:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
    serviceAccountName: system-upgrade
    concurrency: 1
    # Cordon node before upgrade it
    cordon: true
    upgrade:
      image: rancher/k3s-upgrade
    version: <new_version>
  ```
  Plan for worker: `k3s-agent-upgrade.yml`

  ```yml
  apiVersion: upgrade.cattle.io/v1
  kind: Plan
  metadata:
    name: k3s-agent
    namespace: system-upgrade
    labels:
      k3s-upgrade: agent
  spec:
    nodeSelector:
      matchExpressions:
        - key: node-role.kubernetes.io/control-plane
          operator: DoesNotExist
    serviceAccountName: system-upgrade
    # Wait for k3s-server upgrade plan to complete before executing k3s-agent plan
    prepare:
      image: rancher/k3s-upgrade
      args:
        - prepare
        - k3s-server
    concurrency: 1
    # Cordon node before upgrade it
    cordon: true
    upgrade:
      image: rancher/k3s-upgrade
    version: <new_version>
  ```
- Step 3. Execute upgrade plans

  ```shell
  kubectl apply -f k3s-server-upgrade.yml k3s-agent-upgrade.yml
  ```

## Reset the cluster

To reset the cluster execute k3s uninstall script in master and worker nodes

On each worker node (`node2-node4`) execute:

```shell
/usr/local/bin/k3s-agent-uninstall.sh
```
On master node (node1) execute

```shell
/usr/local/bin/k3s-uninstall.sh
```

## Ansible Automation

K3s cluster installation and reset procedures have been automated with Asible playbooks

For installing the cluster execute: 
```shell
ansible-playbook k3s_install.yml
```

For resetting the cluster execute:
```shell
ansible-playbook k3s_reset.yml
```