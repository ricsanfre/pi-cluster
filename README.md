# Raspberry Pi Cluster

![Pi-cluster](documentation/images/pi-cluster.png)

## Scope
The scope of this project is to create a kubernetes cluster at home using Raspberry Pis and Ansible to automate the deployment and configuration.

This is an educational project to explore kubernetes cluster configurations using an ARM architecture and its automation using Ansible. 
As part of the project the goal is to deploy on the Kuberenets cluster basic services such as distributed block storage for persistent volumes (Rook/Ceph or LongHorn) or centralized monitoring tools like Prometheus and EFK.

## Design Principles

- Use ARM 64 bits operating system enabling the possibility of using Raspberry PI B nodes with 8GB RAM. Currently only Ubuntu supports 64 bits ARM distribution for Raspberry Pi.
- Use ligthweigh Kubernetes distribution (K3S). Kuberentes distribution with a smaller memory footprint which is ideal for running on Raspberry PIs
- Use of distributed storage block technology, instead of centralized NFS system, for pod persistent storage.  Kubernetes block distributed storage solutions, like Rook/Ceph or Longhorn, in their latest versions have included ARM 64 bits support.
- Use of Ansible for automating the configuration of the cluster.

## Content

1) [Lab architecture and hardware](documentation/hardware.md). Home lab design and hardware selection
2) [Ansible Control Node (pimaster)](documentation/pimaster.md). Installation and configuration of Ansible control node and ansible development and testing environment (Molecule, Docker, Vagrant) 
3) Nodes firmware, operating system installation and basic services configuration
    - [Raspberry-PI preparation tasks](documentation/preparing_raspberrypi.md). Updating Raspberry PI firmware to enable booting from USB.
    - [Ubuntu 20.04 Installation on Raspberry Pis](documentation/installing_ubuntu.md). General procedure for installing Ubuntu 20.04 OS on USB storage device and boot Raspberry Pi from USB.
    - [Configuring SAN for the lab cluster](documentation/san_installation.md). Details about the configuration of SAN using a Raspeberry PI, gateway as iSCSI Target exposing LUNs to cluster nodes.
    - [Gateway server OS installation and configuration](documentation/gateway.md). Installing Ubuntu OS and configuring a Raspberry PI as firewall and provider of cluster services (NTP, DHCP, DNS and iSCSI SAN services).
    - [Cluster nodes OS installation and configuration](documentation/node.md). Installing Ubutuntu and configuring 4 Raspberry PI as nodes of the cluster, using network and storage services from Gateway node
4) K3S Cluster Installation and basic services configuration
    - [K3S Installation](documentation/installing_k3s.md). Installing K3S lightweight kubernetes cluster.
    - [K3S Networking Configuration](documentation/k3s_networking.md). Complementing K3S default networking services (Flannel and CoreDNS) with baremetal Load Balancer (Metal LB).
    - [K3S Ingress Configuration](documentation/ingress_controller.md). Configuring ingress controller (Traefik) to enable secure and encrypted HTTP incoming traffic using SSL certificates.
        - [SSL certificates centralized management](documentation/certmanager.md). Configure Cert-manager to automatically manage the lifecycle of SSL certificates.
    - [K3S Distributed Storage](documentation/longhorn.md). Installing LongHorn as cluster distributed storage solution for providing Persistent Volumes to pods.
    - [K3S centralized logging monitoring](documentation/logging.md). Installing a centralized log monitoring tool based on EFK stack. Real-time processing of Kuberentes pods and services and homelab servers logs.
    - [K3S centralized monitoring](documentation/monitoring.md). Installing Kube Prometheus Stack for monitoring Kuberentes cluster

## Automatic deployment instructions using Ansible

### Preparing the Ansible Control node and adapt ansible playbooks configuration


  - Set-up a Ubuntu Server 20.04 LTS to become ansible control node `pimaster` following these [instructions](documentation/pimaster.md)

  - Clone this repo or download using the 'Download ZIP' link on GitHub on https://github.com/ricsanfre/pi-cluster

  - Install Ansible requirements:

    Ansible playbooks depend on external roles that need to be installed.

    ```
     ansible-galaxy install -r requirements.yml
    ```
  
  - Adjust [`inventory.yml`](ansible/inventory.yml) inventory file to meet your cluster configuration: IPs, hostnames, number of nodes, etc.

  - Adjust [`ansible.cfg`](ansible/ansible.cfg) file to include your SSH key: `private-file-key` variable

  - Adjust cluster variables under `group_vars` and `host_vars` directory to meet your specific configuration.


      | Variable file | Group of nodes affected |
      |----|----|
      | [`all.yml`](ansible/group_vars/all.yml) | all nodes of cluster + gateway node + pimaster |
      | [`control.yml`](ansible/group_vars/control.yml) | gateway node + pimaster |
      | [`picluster.yml`](ansible/group_vars/picluster.yml) | all nodes of the cluster | 
      | [`k3s_cluster.yml`](ansible/group_vars/picluster.yml) | all nodes of the k3s cluster |
      | [`k3s_master.yml`](ansible/group_vars/k3s_master.yml) | K3s master nodes |
      | [`gateway.yml`](ansible/host_vars/gateway.yml) | gateway node |

### Installing the cluster

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

## About the Project

This project has been started in June 2021 by Ricardo Sanchez
