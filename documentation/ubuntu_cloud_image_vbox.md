# Creationg Ubuntu VM in VBox from Ubuntu cloud image

Fast deployment of a headless Ubuntu server in VBox using a cloud-image ready to be configured in boot time using **cloud-init**.

Canonical generates cloud-specific images which are available on https://cloud-images.ubuntu.com/
Images for VMware/VBox in vmdk disk formats can be found there.
Those images can be configured through **cloud-init** at boot time, using [**NoCloud**](https://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html) data source.

Cloud-init metadata and user-data can be provided to a local VM boot via files in vfat or iso9660 filesystems. The filesystem volume label must be `cidata` or `CIDATA` and it must contain at least two files

   /user-data
   /metadata

Network configuration can be provided to cloud-init formated in yaml file `network-config`

## Step 1. Download Ubuntu 20.04 LTS 64 bits cloud-image in VMDK format

Download the specific image in VMDK format from https://cloud-images.ubuntu.com/releases

> In our case, Ubuntu-20.04-server-cloudimg-amd64.vmdk
> 
> https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64.vmdk

## Step 2. Create SSH keys

Authentication using SSH keys will be the only mechanism available to login to the server.
We will create SSH keys for two different users:

- **ubuntu** user, used to connect from my home laptop

    For generating SSH private/public key in Windows, Putty Key Generator can be used:

    ![ubuntu-SSH-key-generation](images/ubuntu-user-SSH-key-generation.png "SSH Key Generation")

Public-key string will be used in Step 3 to configure ssh_authorized_keys of the default user (ubuntu)

- **ansible** user, used to automate configuration activities with ansible
 
     For generating ansible SSH keys in Ubuntu server execute command:

        ssh-keygen

    In directory `$HOME/.ssh/` public and private key files can be found for the user

    `id_rsa` contains the private key and `id_rsa.pub` contains the public key.

    Content of the id_rsa.pub file has to be copied in Step 3 to configure ssh_authorized_keys of the ansible user
    ```
    cat id_rsa.pub 
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDsVSvxBitgaOiqeX4foCfhIe4yZj+OOaWP+wFuoUOBCZMWQ3cW188nSyXhXKfwYK50oo44O6UVEb2GZiU9bLOoy1fjfiGMOnmp3AUVG+e6Vh5aXOeLCEKKxV3I8LjMXr4ack6vtOqOVFBGFSN0ThaRTZwKpoxQ+pEzh+Q4cMJTXBHXYH0eP7WEuQlPIM/hmhGa4kIw/A92Rm0ZlF2H6L2QzxdLV/2LmnLAkt9C+6tH62hepcMCIQFPvHVUqj93hpmNm9MQI4hM7uK5qyH8wGi3nmPuX311km3hkd5O6XT5KNZq9Nk1HTC2GHqYzwha/cAka5pRUfZmWkJrEuV3sNAl ansible@pimaster
    ```

## Step 3. Create seed iso file

For creating the iso file from my windows labtop an open-source tool like [FreeISO Creator](http://www.freeisocreator.com/)

- Create in a temporary directory
- Create a file `metadata`
  
     ```
     instance-id: ubuntucloud-001
     local-hostname: ubuntucloud1
     ```
- Create a file `user-data`

    ```
    #cloud-config
    
    # Disable password authentication with the SSH daemon
    ssh_pwauth: false
    # SSH authorized keys for default user (ubuntu)
    ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAusTXKfFoy6p3G4QAHvqoBK+9Vn2+cx2G5AY89WmjMikmeTG9KUseOCIAx22BCrFTNryMZ0oLx4u3M+Ibm1nX76R3Gs4b+gBsgf0TFENzztST++n9/bHYWeMVXddeV9RFbvPnQZv/TfLfPUejIMjFt26JCfhZdw3Ukpx9FKYhFDxr2jG9hXzCY9Ja2IkVwHuBcO4gvWV5xtI1nS/LvMw44Okmlpqos/ETjkd12PLCxZU6GQDslUgGZGuWsvOKbf51sR+cvBppEAG3ujIDySZkVhXqH1SSaGQbxF0pO6N5d4PWus0xsafy5z1AJdTeXZdBXPVvUSNVOUw8lbL+RTWI2Q== ubuntu@mi_pc

    # Set TimeZone and Locale
    timezone: Europe/Madrid
    locale: es_ES.UTF-8

    # Hostname
    hostname: node1
    manage_etc_hosts: true
    # Users
    users:
      - default
      - name: ansible
        primary_group: users
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: true
        ssh_authorized_keys:
          - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDsVSvxBitgaOiqeX4foCfhIe4yZj+OOaWP+wFuoUOBCZMWQ3cW188nSyXhXKfwYK50oo44O6UVEb2GZiU9bLOoy1fjfiGMOnmp3AUVG+e6Vh5aXOeLCEKKxV3I8LjMXr4ack6vtOqOVFBGFSN0ThaRTZwKpoxQ+pEzh+Q4cMJTXBHXYH0eP7WEuQlPIM/hmhGa4kIw/A92Rm0ZlF2H6L2QzxdLVnLAkt9C+6tH62hepcMCIQFPvHVUqj93hpmNm9MQI4hM7uK5qyH8wGi3nmPuX311km3hkd5O6XT5KNZq9Nk1HTC2GHqYzwha/cAka5pRUfZmWkJrEuV3sNAl ansible@pimaster

    ```
- Create network-configuration file

    ```

    ```

- Create ISO file with FreeISO
    
    Select the folder where the files has been generated and specify `CIDATA` as Volume Name

    ![Free-ISO-Creation](images/VBox_create_ubuntu_cloud_image_0.png "Create seed.iso")

## Step 3. Create VM in VirtualBOX

- Create new VM without creating any virtual disk

    ![Create-VM-VBox](images/VBox_create_ubuntu_cloud_image_1.png "Create new VM")

    ![Create-VM-VBox](images/VBox_create_ubuntu_cloud_image_2.png "Configure Memory")

    ![Create-VM-VBox](images/VBox_create_ubuntu_cloud_image_3.png "Do not create virtual disk")

- Copy vmdk disk downloaded in step 1 and seed.iso file created in step 2 to new VM's folder

- Configure new VM, add vmdiks and iso

   Add vmdk containing ubuntu image as new disk under SATA controller.

   Load seed.iso file in the Optical Disk (IDE Controller)

    ![Create-VM-VBox](images/VBox_create_ubuntu_cloud_image_4.png "Configure Disk")

- Configure Serial Port
    Serial Port **Port1** need to be enabled.

    ![Create-VM-VBox](images/VBox_create_ubuntu_cloud_image_5.png "Create new VM")

- Configure network interfaces

    Two interfaces enabled: 
    
    Host-only interface

    ![Create-VM-VBox](images/VBox_create_ubuntu_cloud_image_6.png "Host-only interface")

    NAT interface to provide internet access to the VM

    ![Create-VM-VBox](images/VBox_create_ubuntu_cloud_image_7.png "NAT interface")