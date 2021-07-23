# Preparing Ansible Control Node

A Virtual-BOX VM running on a Windows PC is used as Ansible Control Node for automating the provisioning of the Raspberry PIs cluster.

This server, **pimaster**, is an Ubuntu 18.04 VM.

## Installing Docker

Docker is used by Molecule, Ansible's testing tool, for building the testing environment, so it is needed to have a Docker installation on the Control Node for developing and testing the Ansible Playbooks/Roles.

Follow official [installation guide](https://docs.docker.com/engine/install/ubuntu/).

Step 1. Uninstall old versions of docker

    sudo apt-get remove docker docker-engine docker.io containerd runc

Step 2. Install packages to allow apt to use a repository over HTTPS

```
sudo apt-get update

sudo apt-get install \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release
```
	
	
Step 3. Add docker´s official GPG	key
	
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
	

Step 4: Add x86_64 repository	

```
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

Step 5: Install Docker Engine


    sudo apt-get install docker-ce docker-ce-cli containerd.io
	

Step 6: Enable docker management with non-priviledge user

- Create docker group

    ```
    sudo groupadd docker
    ```
    
- Add user to docker group

    ```
    sudo usermod -aG docker $USER
    ```
    
Step 7: Configure Docker to start on boot

    sudo systemctl enable docker.service
    sudo systemctl enable containerd.service

Step 8: Configure docker daemon.

- Edit file `/etc/docker/daemon.json´
	
   Set storage driver to overlay2 and to use systemd for the management of the container’s cgroups.
   Optionally default directory for storing images/containers can be changed to a different disk partition (example /data).
   Documentation about the possible options can be found [here](https://docs.docker.com/engine/reference/commandline/dockerd/#daemon-configuration-file)
	
	```
	{
      "exec-opts": ["native.cgroupdriver=systemd"],
      "log-driver": "json-file",
      "log-opts": {
        "max-size": "100m"
       },
      "storage-driver": "overlay2",
	  "data-root": "/data/docker"
	  
    }
    ```	
- Restart docker

    ```
    sudo systemctl restart docker
    ```
    
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
