# Ansible Automation


## Preparing the Ansible Control node


  1. Set-up a Ubuntu Server 20.04 LTS to become ansible control node `pimaster` following these [instructions](./pimaster.md)
  
  2. Clone this repo or download using the 'Download ZIP' link on GitHub on https://github.com/ricsanfre/pi-cluster

 
  3. Install Ansible requirements:

     ```
     ansible-galaxy install -r requirements.yml
     ```
  
  4. Adjust `inventory.yml` inventory file to meet your cluster configuration
  


## Installing the cluster


  1. Configure cluster firewall (`gateway` node)
     
     Run the playbook:

     ```
     ansible-playbook setup_picluster.yml --tags "gateway"
     ```
  2. Configure cluster nodes (`node1-node4` nodes)

     Run the playbook:

     ```
     ansible-playbook setup_picluster.yml --tags "node"
     ```


## Resetting K3s

If you mess anything up in your Kubernetes cluster, and want to start fresh, the K3s Ansible playbook includes a reset playbook, that you can use to reset the K3S:

  ansible-playbook k3s_reset.yml


## Shutting down the Raspeberry Pi Cluster

To automatically shut down the Raspberry PI cluster, Ansible can be used.

For shutting down the cluster run this command:

    ansible-playbook shutdown.yml

This playbook will connect to each Raspberry PI in the cluster (including `gateway` node) and execute the command `sudo shutdown -h 1m`, telling the raspberry pi to shutdown in 1 minute.

After a couple of minutes all raspberry pi will be shutdown. You can notice that when the Switch ethernet ports  LEDs are off. Then it is safe to unplug the Raspberry PIs.