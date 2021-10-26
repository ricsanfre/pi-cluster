# Raspberry Pi Cluster
## Scope
The scope of this project is to create a kubernetes cluster at home using Raspberry Pis and using Ansible to automate the deployment and configuration.

This is an educational project to explore kubernetes cluster configurations using an ARM architecture and its automation using Ansible. 
As part of the project the goal is to deploy on the Kuberenets cluster basic services such as distributed block storage for persistent volumes (Rook/Ceph or LongHorn) or centralized monitoring (Prometheus and ELK).

## Design Principles

- Use ARM 64 bits operating system enabling the possibility of using Raspberry PI B nodes with 8GB RAM. Currently only Ubuntu supports 64 bits ARM distribution for Raspberry Pi.
- Use ligthweigh Kubernetes distribution (K3S). Kuberentes distribution with a smaller memory footprint which is ideal for running on Raspberry PIs
- Use of distributed storage block technology, instead of centralized NFS system, for pod persistent storage.  Kubernetes block distributed storage solutions, like Rook/Ceph or Longhorn, in their latest versions have included ARM 64 bits support.
- Use of Ansible for automating the configuration of the cluster.

## Content

1. [Lab architecture and hardware](documentation/hardware.md). Home lab design and hardware selection
2. [Installing Ansible Control Node (pimaster)](documentation/pimaster.md). Ansible and Ansible Molecule installation
3. [Raspberry-PI preparation tasks](documentation/preparing_raspberrypi.md). Updating Raspberry PI firmware to enable booting from USB.
4. [Gateway node configuration](documentation/gateway.md). Configuring a Raspberry PI as firewall and provider of cluster services (NTP, DHCP, DNS and iSCSI SAN services).
5. [Cluster nodes configuration](documentation/node.md). Configuring 4 Raspberry PI as nodes of the cluster, using network and storage services from Gateway node
6. [K3S Installation and basic configuration](documentation/installing_k3s.md). Installing K3S lightweight kubernetes cluster.
7. [K3S Networking Configuration](documentation/k3s_networking.md). Complementing K3S default networking services (Flannel and CoreDNS) with baremetal Load Balancer (Metal LB).
8. [K3S Ingress Configuration](documentation/ingress_controller.md). Configuring ingress controller (Traefik) to enable secure and encrypted HTTP incoming traffic using SSL certificates.
9. [SSL certificates centralized management](documentation/certmanager.md). Configure Cert-manager to automatically manage the lifecycle of SSL certificates.
10. [K3S Distributed Storage](documentation/longhorn.md). Installing LongHorn as cluster distributed storage solution for providing Persistent Volumes to pods.
11. [K3S centralized logging monitoring](documentation/logging.md). Installing a centralized log monitoring tool based on EFK stack. Real-time processing of Kuberentes pods and services and homelab servers logs.

## About the Project

This project has been started in June 2021 by Ricardo Sanchez
