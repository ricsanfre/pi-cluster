## Ansible Automation


### 1) Preparing the Ansible Control node and adapt ansible playbooks configuration


  - Set-up a Ubuntu Server 20.04 LTS to become ansible control node `pimaster` following these [instructions](./pimaster.md)

  - Clone this repo or download using the 'Download ZIP' link on GitHub on https://github.com/ricsanfre/pi-cluster

  - Install Ansible requirements:

    Ansible playbooks depend on external roles that need to be installed.

     ```
     ansible-galaxy install -r requirements.yml
     ```
  
  - Adjust [`inventory.yml`](../ansible/inventory.yml) inventory file to meet your cluster configuration: IPs, hostnames, number of nodes, etc.
  
  - Adjust [`ansible.cfg`](../ansible/ansible.cfg) file to include your SSH key: `private-file-key` variable

  - Adjust cluster variables under `group_vars` and `host_vars` directory to meet your specific configuration.
    

      | Variable file | Group of nodes affected |
      |----|----|
      | [`all.yml`](../ansible/group_vars/all.yml) | all nodes of cluster + gateway node + pimaster |
      | [`control.yml`](../ansible/group_vars/control.yml) | gateway node + pimaster |
      | [`picluster.yml`](../ansible/group_vars/picluster.yml) | all nodes of the cluster | 
      | [`k3s_cluster.yml`](../ansible/group_vars/picluster.yml) | all nodes of the k3s cluster |
      | [`k3s_master.yml`](../ansible/group_vars/k3s_master.yml) | K3s master nodes |
      | [`gateway.yml`](../ansible/host_vars/gateway.yml) | gateway node |
      {: .table }

### 2) Installing the cluster

  - Configure cluster firewall (`gateway` node)
     
     Run the playbook:

     ```
     ansible-playbook setup_picluster.yml --tags "gateway"
     ```
  - Configure cluster nodes (`node1-node4` nodes)

     Run the playbook:

     ```
     ansible-playbook setup_picluster.yml --tags "node"
     ```
  - Install K3S cluster

     Run the playbook:

     ```
     ansible-playbook k3s_install.yml
     ```

  - Deploy and configure basic services (metallb, traefik, certmanager, longhorn, EFK and Prometheus )

     Run the playbook:

     ```
     ansible-playbook k3s_deploy.yml
     ```

     Different tags can be used to select the componentes to deploy executing

     ```
     ansible-playbook k3s_deploy.yml --tags <ansible_tag>
    ```

     | Ansible Tag | Component to configure/deploy |
     |---|---|
     | `metallb` | Metal LB |
     | `traefik` | Traefik | 
     | `certmanager` | Cert-manager |
     | `longhorn` | Longhorn |
     | `logging` | EFK Stack |
     | `monitoring` | Prometheus Stack |
     {: .table }

### Resetting K3s

If you mess anything up in your Kubernetes cluster, and want to start fresh, the K3s Ansible playbook includes a reset playbook, that you can use to reset the K3S:

  ```
  ansible-playbook k3s_reset.yml
  ```

### Shutting down the Raspeberry Pi Cluster

To automatically shut down the Raspberry PI cluster, Ansible can be used.

For shutting down the cluster run this command:

  ```
  ansible-playbook shutdown.yml
  ```

This playbook will connect to each Raspberry PI in the cluster (including `gateway` node) and execute the command `sudo shutdown -h 1m`, telling the raspberry pi to shutdown in 1 minute.

After a couple of minutes all raspberry pi will be shutdown. You can notice that when the Switch ethernet ports  LEDs are off. Then it is safe to unplug the Raspberry PIs.