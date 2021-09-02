# Raspberry Pi Cluster
## Scope
The scope of this project is to create a kubernetes cluster at home using Raspberry Pis and using Ansible to automate the deployment and configuration.

This is an educational project to explore kubernetes cluster configurations using an ARM architecture and its automation using Ansible. 
As part of the project the goal is to deploy on the Kuberenets cluster basic services such as distributed block storage for persistent volumes (LongHorn) or centralized monitoring (Prometheus).

## Design Principles

- Use ARM 64 bits operating system. Full usage of 4G RAM available by the Raspberry Pi 4. Currently only Ubuntu supports 64 bits ARM distribution for Raspberry Pi.
- Use ligthweigh Kubernetes distribution (K3S)
- Use of distributed storage block technology, instead of centralized NFS system, for pod persistent storage
- Use of Ansible for automating the configuration of the cluster.

## Content

1. [Lab architecture and hardware](documentation/hardware.md). Home lab design and hardware selection
2. [Installing Ansible Control Node (pimaster)](documentation/pimaster.md). Ansible and Ansible Molecule installation
3. Raspberry-PI preparation tasks
    - [Firmware Update](documentation/preparing_raspberrypi.md). Updating Raspberry PI firmware and boot order to enable boot from USB.
    - [Ubuntu OS Installation](documentation/installing_ubuntu.md). Installing Ubuntu 20.04 LTS 64 bits on Raspberry PIs.
4. [Gateway node configuration](documentation/gateway.md). Configuring a Raspberry PI as firewall and provider of cluster services (NTP, DHCP, iSCSI SAN).
5. [K3S Installation](documentation/intstalling_k3s.md). Installing K3S lightweight kubernetes cluster


## About the Project

This project has been started in June 2021 by Ricardo Sanchez
