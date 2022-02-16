# Raspberry Pi Kubernetes Cluster 

<img src="docs/assets/img/picluster-logo.png" width="200" />

<table>
  <tr>
    <td><img src="docs/assets/img/pi-cluster.png" width="400" alt="pi-cluster-1.0"/></td>
    <td><img src="docs/assets/img/pi-cluster-2.0.png" width="360" /></td>
  </tr>
</table>

## **K3S Kubernetes Cluster using bare metal ARM-based nodes (Raspberry-PIs) automated with Ansible**

This is an educational project to explore kubernetes cluster configurations using an ARM architecture and its automation using Ansible.

The entire process for creating this cluster at home, from cluster design and architecture to step-by-step manual configuration guides, has been documented and it is published in the project website: https://picluster.ricsanfre.com.

This repository contains the Ansible's source code (playbooks/roles) and Cloud-init's configuration files used for automated all manual tasks described in the documentation. 
The cluster can be re-deployed in minutes as many times as needed for testing new cluster configurations, new software versions or just take you out of any mesh you could cause playing with the cluster.

## Scope

Automatically deploy and configure a lightweight Kubernetes flavor based on [K3S](https://ks3.io/) and set of cluster basic services such as: 1) distributed block storage for POD's persistent volumes like [LongHorn](https://longhorn.io/), 2) centralized monitoring tool like [Prometheus](https://prometheus.io/) 3) centralized log managemeent like EFK stack ([Elasticsearch](https://www.elastic.co/elasticsearch/)-[Fluentbit](https://fluentbit.io/)-[Kibana](https://www.elastic.co/kibana/) and 3) backup/restore solution for the cluster like [Velero](https://velero.io/) and [Restic](https://restic.net/).

The following picture shows the set of opensource solutions used so far in the cluster, which installation process has been documented and its deployment has been automated with Ansible:

<p align="center">
  <img src="docs/assets/img/pi-cluster-icons.png" width="500"/>
</p>

## Cluster architecture and hardware

Home lab architecture, showed in the picture bellow, consist of a Kubernetes cluster of 4 nodes (1 master and 3 workers) and a firewall, built with another Raspberry PI, to isolate cluster network from your home network.


<p align="center">
  <img src="docs/assets/img/RaspberryPiCluster_architecture.png" width="500"/>
</p>

See further details about the architecture and hardware in the [documentation](https://picluster.ricsanfre.com/docs/home/)

## Official Site

You can browse more information about Pi Cluster Project on https://picluster.ricsanfre.com/. 

The content of this website and the source code to build it (Jekyll static based website) are also stored in this repo: `/docs` folder.

## Usage 

Check out the documentation [Quick Start guide](http://picluster.ricsanfre.com/docs/ansible/) to know how to use and tweak cloud-init files (`/cloud-init` folder) and Ansible playbooks contained in this repository.

## About the Project

This project has been started in June 2021 by Ricardo Sanchez
