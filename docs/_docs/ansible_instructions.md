---
title: Ansible Instructions
permalink: /docs/ansible/
redirect_from: /docs/ansible_instructions.md
---

## Preparing the Ansible Control node and adapt ansible playbooks configuration


  - Set-up a Ubuntu Server 20.04 LTS to become ansible control node `pimaster` following these [instructions](/docs/pimaster/)

  - Clone [Pi-Cluster Git repo](https://github.com/ricsanfre/pi-cluster) or download using the 'Download ZIP' link on GitHub. 

  - Install Ansible requirements:

    Ansible playbooks depend on external roles that need to be installed.

    ```shell
     ansible-galaxy install -r requirements.yml
    ```
  
  - Adjust [`inventory.yml`]({{ site.git_edit_address }}/inventory.yml) inventory file to meet your cluster configuration: IPs, hostnames, number of nodes, etc.

  - Adjust [`ansible.cfg`]({{ site.git_edit_address }}/ansible.cfg) file to include your SSH key: `private-file-key` variable.

  - Adjust [`all.yml`]({{ site.git_edit_address }}/group_vars/all.yml) file to include your ansible remote UNIX user (`ansible_user` variable) and whether centralized san storage architectural option is selected (`centralized_san` variable)

  - Adjust cluster variables under `group_vars`, `host_vars` and `vars`directories to meet your specific configuration.


      | Variable file | Group of nodes affected |
      |----|----|
      | [`all.yml`]({{ site.git_edit_address }}/group_vars/all.yml) | all nodes of cluster + gateway node + pimaster |
      | [`picluster.yml`]({{ site.git_edit_address }}/group_vars/picluster.yml) | all nodes of the cluster | 
      | [`k3s_cluster.yml`]({{ site.git_edit_address }}/group_vars/picluster.yml) | all nodes of the k3s cluster |
      | [`k3s_master.yml`]({{ site.git_edit_address }}/group_vars/k3s_master.yml) | K3s master nodes |
      | [`gateway.yml`]({{ site.git_edit_address }}/host_vars/gateway.yml) | gateway node |
      {: .table }

## Installing the cluster

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
  - Configure backup server (S3) (`node1`) and configuring OS backup with restic in all nodes (`node1-node4` and `gateway`)

     Run the playbook:

     ```
     ansible-playbook backup_configuration.yml
     ```

  - Install K3S cluster

     Run the playbook:

     ```
     ansible-playbook k3s_install.yml
     ```

  - Deploy and configure basic services (metallb, traefik, certmanager, longhorn, EFK, Prometheus, Velero )

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
     | `backup` | Velero |
     {: .table }

## Resetting K3s

If you mess anything up in your Kubernetes cluster, and want to start fresh, the K3s Ansible playbook includes a reset playbook, that you can use to reset the K3S:

  ```
  ansible-playbook k3s_reset.yml
  ```

## Shutting down the Raspeberry Pi Cluster

To automatically shut down the Raspberry PI cluster, Ansible can be used.

For shutting down the cluster run this command:

  ```
  ansible-playbook shutdown.yml
  ```

This playbook will connect to each Raspberry PI in the cluster (including `gateway` node) and execute the command `sudo shutdown -h 1m`, telling the raspberry pi to shutdown in 1 minute.

After a couple of minutes all raspberry pi will be shutdown. You can notice that when the Switch ethernet ports  LEDs are off. Then it is safe to unplug the Raspberry PIs.
