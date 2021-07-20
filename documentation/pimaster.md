# Preparing Ansible Control Node

A Virtual-BOX VM running on a Windows PC is used as Ansible Control Node for automating the provisioning of the Raspberry PIs cluster.

This server, **pimaster**, is an Ubuntu 18.04 VM.

## Installing Docker

Docker is used by Molecule, Ansible's testing tool, for building the testing environment, so it is needed to have a Docker installation on the Control Node for developing and testing the Ansible Playbooks/Roles.

Follow official [installation guide](https://docs.docker.com/engine/install/ubuntu/)

## Installing Ansible, playboook syntax checking tools and Molecule (Ansible testing environment)

Ansible can be installed in Ubuntu 18.04 using official package from the ansible repository 'sudo apt install ansible' will install an old ansible verion for python2.

Ansible Molecule is not available as official package, so pip is the only alternative
Instead, install latest version for python3 with python package manager pip.

Python Ansible and Molecule packages and its dependencies installed using Pip might conflict with python3 packages included in the Ubuntu official release.

Since some of those python3 packages installed with apt(like PyYaml) cannot be updated without impacting some of Ubuntu core utils, a python virtual environment for Ansible will be used instead.

Installation of the whole Ansible environment can be done using a python virtual environment.

Step 1. Install python Virtual Env and Pip3 package

    sudo apt-get install python3-venv python3-pip

Step 2. Create Virtual Env for Ansible

    python3 -m venv ansible_env

Step 3. Activate Virtual Environment

    source ansible_env/bin/activate
	
> NOTE: For deactivating the Virtual environment

	deactivate

Step 4. Upgrade setuptools and pip packages

    pip3 install --upgrade pip setuptools
	
Step 5. Install ansible

    pip3 install ansible

Step 6. Install yamllint and ansible-lint

    pip3 install yamllint ansible-lint

Step 7. Install Docker python driver and molecule packages:

    pip3 install docker molecule
