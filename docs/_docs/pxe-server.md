---
title: OS Installation - x86 (PXE sever)
permalink: /docs/ubuntu/x86/
description: How to netboot server auntoinstall for x86 cluster nodes using PXE server and Ubutu auto-install cloud-init.
last_modified_at: "08-06-2023"
---

## About Ubuntu Automated Server installation

https://ubuntu.com/server/docs/install/autoinstall


> NOTE: When any system is installed using the server installer, an autoinstall file for repeating the install is created at /var/log/installer/autoinstall-user-data.

TBD: Include diagram netboot installation


## PXE server Ubuntu 22.04


### Configure PXE as Firewall/router

Enable incoming TFTP/NFS traffic 


### Install Apache server

- Step 1. Install apache2

  ```shell
  sudo apt install apache2
  ```

- Step 2. Created a new file ks-server.conf under /etc/apache2/sites-available/ with the following content

```
<VirtualHost 10.0.0.10:80>
    ServerAdmin root@server1.example.com
    DocumentRoot /
    ServerName server.example.com
    ErrorLog ${APACHE_LOG_DIR}/ks-server.example.com-error_log
    CustomLog ${APACHE_LOG_DIR}/ks-server.example.com-access_log common
    <Directory /ks>
        Options Indexes MultiViews
        AllowOverride All
        Require all granted
    </Directory>
    <Directory /images>
        Options Indexes MultiViews
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
```

- Step 3. Create HTTP serving directories
  `ks` which will contain cloud-init files and
  `images` where we will place our ubuntu live-server iso image.

  ```shell
  sudo mkdir -p /var/www/html/ks
  sudo mkdir -p /var/www/html/images
  ```
- Step 4. Enable apache2

  ```shell
  sudo systemctl enable apache2 --now
  ``` 

- Step 4. Check apache status

  ```shell
  sudo systemctl status apache2
  ```


#### Serve ISO live

- Step 1. Download Ubuntu 22.04 server live ISO

  ```shell
  wget http://cdimage.ubuntu.com/ubuntu-server/jammy/daily-live/current/jammy-live-server-amd64.iso
  ```

- Step 2. Copy to images directory

  ```shell
  cp jammy-live-server-amd64.iso /var/www/html/images/.
  ```

#### Serve cloud-init files

- Step 1.  Create a directory with name <server-macaddress> within /var/www/html/ks

  /var/www/html/ks
  /var/www/html/ks/aa:bb:cc:dd:ee:00/meta-data
  /var/www/html/ks/aa:bb:cc:dd:ee:00/user-data

- Step 1. Create user-data file in /var/www/html/ks/

  This must be a [cloud-init ubuntu auto-install file](https://ubuntu.com/server/docs/install/autoinstall)

  Minimal config

  ```yml
#cloud-config
autoinstall:
  identity:
    hostname: jammy-minimal
    password: $6$gnqbMUzHhQzpDEw.$.cCNVVDsDfj5Feebh.5O4VbOmib7tyjmeI2ZsFP7VK2kWwgJFbfjvXo3chpeAqCgXWVIW9oNQ/Ag85PR0IsKD/
    username: ubuntu
  version: 1
  ```

- Step 2. Create meta-data file in /var/www/html/ks/

  Create cloud-init meta-data file containing the hostname of the server or a empty file.

  ```shell
  cat > /var/www/html/ks/meta-data <<EOF
  instance-id: ubuntu-server
  EOF
  ```

> NOTE: This files must be placed under /var/www/html/ks/<mac-address> if different configurations are desired for different servers.  


### Install and configure DHCP and TFTP Server

- Step 1. Install dnsmasq

  ```shell
  sudo apt install dnsmasq
	```

- Step 2. Create TFTP server directory

  
  ```shell
  sudo mkdir /srv/tftp
  sudo mkdir /srv/tftp/grub
  sudo mkdir /srv/tftp/pxelinux.cfg
  ```

- Step 3. Configure dnsmasq

  Edit file `/etc/dnsmasq.d/dnsmasq.conf`

    ```
# Enable DHCP service will be providing addresses over enp0s8 adapter (NAT network no DHCP)

interface=enp0s8

# We will listen on the static IP address we declared earlier
listen-address= 10.0.0.10

# Pre-allocate pool of IPs for vbox host only adaptor
dhcp-range=10.0.0.100,10.0.0.200,12h

# Set gateway
dhcp-option=3,10.0.0.1

# DNS nameservers
server=80.58.61.250
server=80.58.61.254

# Bind dnsmasq to the interfaces it is listening on (eth0)
bind-interfaces

# Never forward plain names (without a dot or domain part)
domain-needed

local=/local.test/

domain=local.test

# Never forward addresses in the non-routed address spaces.
bogus-priv

# Do not use the hosts file on this machine
# expand-hosts

# Useful for debugging issues
# log-queries
# log-dhcp

# Enabling Netboot
dhcp-boot=pxelinux.0
dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-boot=tag:efi-x86_64,bootx64.efi

# Enable-tftp
enable-tftp
tftp-root=/srv/tftp
    ```

- Step 4. Restart dnsmasq service

  ```shell
  sudo systemctl restart dnsmasq
  ```

### Preparing TFTP files (boot loading files)


#### Copying kernel and initrd files

- Step 1. Download Ubuntu 22.04 server live ISO

  ```shell
  wget http://cdimage.ubuntu.com/ubuntu-server/jammy/daily-live/current/jammy-live-server-amd64.iso
  ```
  
- Step 2. Mount the ISO file

  ```shell
  mount jammy-live-server-amd64.iso /mnt
  ```

- Step 3. Copy linux kernel and initrd files to TFTP server root

  ```shell
  cp /mnt/casper/{vmlinuz,initrd} /srv/tftp/
  ```

#### Copying files for UEFI boot

- Step 1. Copy the signed shim binary into place:
 
  ```shell
  apt download shim-signed
  dpkg-deb --fsys-tarfile shim-signed*deb | tar x ./usr/lib/shim/shimx64.efi -O > /srv/tftp/bootx64.efi

- Step 2. Copy the signed GRUB binary into place:

  ```shell
  apt download grub-efi-amd64-signed
  dpkg-deb --fsys-tarfile grub-efi-amd64-signed*deb | tar x ./usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed -O > /srv/tftp/grubx64.efi  
  ```

- Step 3. Copy unicode.pf2

  ```shell
  apt download grub-common
  dpkg-deb --fsys-tarfile grub-common*deb | tar x ./usr/share/grub/unicode.pf2 -O > /srv/tftp/unicode.pf2
  ```

- Step 4. Prepare grub.conf file and copy to /srv/tftp/grub

  ```shell
set default="0"
set timeout=5

if loadfont unicode ; then
  set gfxmode=auto
  set locale_dir=$prefix/locale
  set lang=en_US
fi
terminal_output gfxterm

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray
if background_color 44,0,30; then
  clear
fi

function gfxmode {
        set gfxpayload="${1}"
        if [ "${1}" = "keep" ]; then
                set vt_handoff=vt.handoff=7
        else
                set vt_handoff=
        fi
}

set linux_gfx_mode=keep

export linux_gfx_mode

menuentry 'Install Ubuntu 22.04' {
        gfxmode $linux_gfx_mode
        linux vmlinuz ip=dhcp url=http://10.0.0.10/images/jammy-live-server-amd64.iso autoinstall ds=nocloud-net\;s=http://10.0.0.10/ks/${net_default_mac}/ cloud-config-url=/dev/null
        initrd initrd
}
  ```

This configuration launch autoinstall using cloud-init files per mac address (`${net_default_mac}`)

#### Copying files for legacy boot

- Step 1. Copy the pxelinux.0 binary:
 
  ```shell
  apt download pxelinux
  dpkg-deb --fsys-tarfile pxelinux*deb | tar x ./usr/lib/PXELINUX/pxelinux.0 -O > /srv/tftp/pxelinux.0
  ```

- Step 2. Copy syslinux-common packages:

  ```shell
  apt download syslinux-common
  dpkg-deb --fsys-tarfile pxelinux*deb | tar x ./usr/lib/PXELINUX/pxelinux.0 -O > /srv/tftp/pxelinux.0
  dpkg-deb --fsys-tarfile syslinux-common*deb | tar x ./usr/lib/syslinux/modules/bios/ldlinux.c32 -O > /srv/tftp/ldlinux.c32
  dpkg-deb --fsys-tarfile syslinux-common*deb | tar x ./usr/lib/syslinux/modules/bios/menu.c32 -O > /build/menu.c32
  dpkg-deb --fsys-tarfile syslinux-common*deb | tar x ./usr/lib/syslinux/modules/bios/libutil.c32 -O > /srv/tftp/libutil.c32 
  ```

- Step 4. Prepare pxe.conf file and copy to /srv/tftp/pxelinux.cfg

  PXE looks for a file containing in the name the MAC address, using as separator '-'

  01-<mac-address>, ie: 01-10-e7-c6-16-54-10 for MAC address 10:e7:c6:16:54:10

  ```shell
  default menu.c32
  menu title Ubuntu installer

  label jammy
          menu label Install Ubuntu J^ammy (22.04)
          menu default
          kernel vmlinuz
          initrd initrd
          append ip=dhcp url=http://10.0.0.1/images/jammy-live-server-amd64.iso autoinstall ds=nocloud-net;s=http://10.0.0.1/ks/10:e7:c6:16:54:10/ cloud-config-url=/dev/null
  prompt 0
  timeout 300
  ```
  

### Alternative booting contents of the ISO via nfsroot.

Netboot installation requires to download the ISO and keep it in RAM, which is not possible if the server RAM is not > 4GB.
Testing with server of 4GB the installation hangs with initdram message "not space left". With Virtualbox a VM with 5GB is needed.

> NOTE: Idea from this POST: https://discourse.ubuntu.com/t/netbooting-the-live-server-installer/14510/184
>
> "Extracting or mounting ISO on NFS server, then serve the contents itself, which goes around the requirement of keeping whole ISO in RAM plus additional RAM to do the booting and installation procedure"

Installation downloading ISO file 

Not enough RAM space to download the ISO

- Step 1: Intall NFS server

  ```shell
  sudo apt install nfs-kernel-server
  ```

- Step 2: Make shared NFS directory

  ```shell
  sudo mkdir -p /mnt/jammy-live-server-amd64-iso-nfs/
  ```
- Step 3: Mount ubuntu ISO file

  ```shell
  sudo mount /var/www/html/images/jammy-live-server-amd64.iso /mnt/jammy-live-server-amd64-iso-nfs/ 
  ```

  Configure mount on start

  Add to /etc/fstab file the following line
  ```
  /var/www/html/images/jammy-live-server-amd64.iso /mnt/jammy-live-server-amd64-iso-nfs iso9660 loop 0 0
  ```

- Step 4: Configure NFS

  Edit /etc/exports file adding the following line:

  ```
  /mnt/jammy-live-server-amd64-iso-nfs 10.0.0.0/24(ro,sync,no_subtree_check)
  ```

- Step 5: export NFS directory

  ```shell
  sudo exportfs -a
  ```

- Step 6: Restart NFS service

  ```shell
  sudo systemctl restart nfs-kernel-server
  ```

- Step 7: Show NFS directories

  ```shell
  sudo exportfs -v
  ```

- Step 8: Update `/srv/tftp/grub/grub.cfg` file
 
  ```
set default="0"
set timeout=-30

if loadfont unicode ; then
  set gfxmode=auto
  set locale_dir=$prefix/locale
  set lang=en_US
fi
terminal_output gfxterm

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray
if background_color 44,0,30; then
  clear
fi

function gfxmode {
        set gfxpayload="${1}"
        if [ "${1}" = "keep" ]; then
                set vt_handoff=vt.handoff=7
        else
                set vt_handoff=
        fi
}

set linux_gfx_mode=keep

export linux_gfx_mode

menuentry 'Install Ubuntu 22.04' {
        gfxmode $linux_gfx_mode
        linux vmlinuz netboot=nfs nfsroot=192.168.57.10:/mnt/jammy-live-server-amd64-iso-nfs ip=dhcp  autoinstall ds=nocloud-net\;s=http://192.168.57.10/ks/ cloud-config-url=/dev/null
        initrd initrd
}

  ```

NOTE: nfsroot=<nfs-server-ip>:<path>,ver=4.

  NFS ver 4 need to be specified so 2049 port is used


## Ubuntu Autoinstall files (user-data)

[Ubuntu Autoistall files](https://ubuntu.com/server/docs/install/autoinstall-reference) cloud-init YAML format.



### Minimum

```yml
#cloud-config
autoinstall:
  identity:
    hostname: jammy-minimal
    password: $6$gnqbMUzHhQzpDEw.$.cCNVVDsDfj5Feebh.5O4VbOmib7tyjmeI2ZsFP7VK2kWwgJFbfjvXo3chpeAqCgXWVIW9oNQ/Ag85PR0IsKD/
    username: ubuntu
  version: 1
```

### Server installation

```yml
#cloud-config
autoinstall:
  keyboard:
    layout: es
  ssh:
    allow-pw: false
    install-server: true
  storage:
    layout:
      name: lvm
  user-data:
    # Set TimeZone and Locale
    timezone: UTC
    locale: es_ES.UTF-8

    # Hostname
    hostname: server

    # cloud-init not managing hosts file. only hostname is added
    manage_etc_hosts: localhost

    users:
      # not using default ubuntu user
      - name: ricsanfre
        primary_group: users
        groups: [adm, admin]
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: true
        ssh_authorized_keys:
          - ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAusTXKfFoy6p3G4QAHvqoBK+9Vn2+cx2G5AY89WmjMikmeTG9KUseOCIAx22BCrFTNryMZ0oLx4u3M+Ibm1nX76R3Gs4b+gBsgf0TFENzztST++n9/bHYWeMVXddeV9RFbvPnQZv/TfLfPUejIMjFt26JCfhZdw3Ukpx9FKYhFDxr2jG9hXzCY9Ja2IkVwHuBcO4gvWV5xtI1nS/LvMw44Okmlpqos/ETjkd12PLCxZU6GQDslUgGZGuWsvOKbf51sR+cvBppEAG3ujIDySZkVhXqH1SSaGQbxF0pO6N5d4PWus0xsafy5z1AJdTeXZdBXPVvUSNVOUw8lbL+RTWI2Q== ricardo@dol-guldur
          - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDsVSvxBitgaOiqeX4foCfhIe4yZj+OOaWP+wFuoUOBCZMWQ3cW188nSyXhXKfwYK50oo44O6UVEb2GZiU9bLOoy1fjfiGMOnmp3AUVG+e6Vh5aXOeLCEKKxV3I8LjMXr4ack6vtOqOVFBGFSN0ThaRTZwKpoxQ+pEzh+Q4cMJTXBHXYH0eP7WEuQlPIM/hmhGa4kIw/A92Rm0ZlF2H6L2QzxdLV/2LmnLAkt9C+6tH62hepcMCIQFPvHVUqj93hpmNm9MQI4hM7uK5qyH8wGi3nmPuX311km3hkd5O6XT5KNZq9Nk1HTC2GHqYzwha/cAka5pRUfZmWkJrEuV3sNAl ansible@pimaster

```

Enabling SSH user/password
```yml
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: erebor
    password: $6$gnqbMUzHhQzpDEw.$.cCNVVDsDfj5Feebh.5O4VbOmib7tyjmeI2ZsFP7VK2kWwgJFbfjvXo3chpeAqCgXWVIW9oNQ/Ag85PR0IsKD/
    username: ricsanfre
  keyboard:
    layout: es
  ssh:
    allow-pw: true
    install-server: true
  storage:
    layout:
      name: lvm
  user-data:
    # Set TimeZone and Locale
    timezone: UTC
    locale: es_ES.UTF-8

    # Hostname
    hostname: server

    # cloud-init not managing hosts file. only hostname is added
    manage_etc_hosts: localhost

    users:
      - name: ricsanfre
        primary_group: users
        groups: [adm, admin]
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: true
        ssh_authorized_keys:
          - ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAusTXKfFoy6p3G4QAHvqoBK+9Vn2+cx2G5AY89WmjMikmeTG9KUseOCIAx22BCrFTNryMZ0oLx4u3M+Ibm1nX76R3Gs4b+gBsgf0TFENzztST++n9/bHYWeMVXddeV9RFbvPnQZv/TfLfPUejIMjFt26JCfhZdw3Ukpx9FKYhFDxr2jG9hXzCY9Ja2IkVwHuBcO4gvWV5xtI1nS/LvMw44Okmlpqos/ETjkd12PLCxZU6GQDslUgGZGuWsvOKbf51sR+cvBppEAG3ujIDySZkVhXqH1SSaGQbxF0pO6N5d4PWus0xsafy5z1AJdTeXZdBXPVvUSNVOUw8lbL+RTWI2Q== ricardo@dol-guldur
          - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDsVSvxBitgaOiqeX4foCfhIe4yZj+OOaWP+wFuoUOBCZMWQ3cW188nSyXhXKfwYK50oo44O6UVEb2GZiU9bLOoy1fjfiGMOnmp3AUVG+e6Vh5aXOeLCEKKxV3I8LjMXr4ack6vtOqOVFBGFSN0ThaRTZwKpoxQ+pEzh+Q4cMJTXBHXYH0eP7WEuQlPIM/hmhGa4kIw/A92Rm0ZlF2H6L2QzxdLV/2LmnLAkt9C+6tH62hepcMCIQFPvHVUqj93hpmNm9MQI4hM7uK5qyH8wGi3nmPuX311km3hkd5O6XT5KNZq9Nk1HTC2GHqYzwha/cAka5pRUfZmWkJrEuV3sNAl ansible@pimaster

```

## Storage Configuration

storage section. https://ubuntu.com/server/docs/install/autoinstall-reference

Reference https://curtin.readthedocs.io/en/latest/topics/storage.html


[partition]!(ubuntu-partition.png)

```yml
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: erebor
    password: $6$gnqbMUzHhQzpDEw.$.cCNVVDsDfj5Feebh.5O4VbOmib7tyjmeI2ZsFP7VK2kWwgJFbfjvXo3chpeAqCgXWVIW9oNQ/Ag85PR0IsKD/
    username: ricsanfre
  keyboard:
    layout: es
  ssh:
    allow-pw: true
    install-server: true
  storage:
    config:
    - ptable: gpt
      path: /dev/sda
      wipe: superblock-recursive
      preserve: false
      name: ''
      grub_device: false
      type: disk
      id: disk-sda
    - device: disk-sda
      size: 1075M
      wipe: superblock
      flag: boot
      number: 1
      preserve: false
      grub_device: true
      path: /dev/sda1
      type: partition
      id: partition-0
    - fstype: fat32
      volume: partition-0
      preserve: false
      type: format
      id: format-0
    - device: disk-sda
      size: 2G
      wipe: superblock
      number: 2
      preserve: false
      grub_device: false
      path: /dev/sda2
      type: partition
      id: partition-1
    - fstype: ext4
      volume: partition-1
      preserve: false
      type: format
      id: format-1
    - device: disk-sda
      size: -1
      wipe: superblock
      number: 3
      preserve: false
      grub_device: false
      path: /dev/sda3
      type: partition
      id: partition-2
    - name: ubuntu-vg
      devices:
      - partition-2
      preserve: false
      type: lvm_volgroup
      id: lvm_volgroup-0
    - name: ubuntu-lv
      volgroup: lvm_volgroup-0
      size: 100G
      wipe: superblock
      preserve: false
      path: /dev/ubuntu-vg/ubuntu-lv
      type: lvm_partition
      id: lvm_partition-0
    - fstype: ext4
      volume: lvm_partition-0
      preserve: false
      type: format
      id: format-3
    - path: /
      device: format-3
      type: mount
      id: mount-3
    - name: lv-data
      volgroup: lvm_volgroup-0
      size: -1
      wipe: superblock
      preserve: false
      path: /dev/ubuntu-vg/lv-data
      type: lvm_partition
      id: lvm_partition-1
    - fstype: ext4
      volume: lvm_partition-1
      preserve: false
      type: format
      id: format-4
    - path: /storage
      device: format-4
      type: mount
      id: mount-4
    - path: /boot
      device: format-1
      type: mount
      id: mount-1
    - path: /boot/efi
      device: format-0
      type: mount
      id: mount-0
  user-data:
    # Set TimeZone and Locale
    timezone: UTC
    locale: es_ES.UTF-8

    # Hostname
    hostname: erebor

    # cloud-init not managing hosts file. only hostname is added
    manage_etc_hosts: localhost

    users:
      - name: ricsanfre
        primary_group: users
        groups: [adm, admin]
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: true
        ssh_authorized_keys:
          - ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAusTXKfFoy6p3G4QAHvqoBK+9Vn2+cx2G5AY89WmjMikmeTG9KUseOCIAx22BCrFTNryMZ0oLx4u3M+Ibm1nX76R3Gs4b+gBsgf0TFENzztST++n9/bHYWeMVXddeV9RFbvPnQZv/TfLfPUejIMjFt26JCfhZdw3Ukpx9FKYhFDxr2jG9hXzCY9Ja2IkVwHuBcO4gvWV5xtI1nS/LvMw44Okmlpqos/ETjkd12PLCxZU6GQDslUgGZGuWsvOKbf51sR+cvBppEAG3ujIDySZkVhXqH1SSaGQbxF0pO6N5d4PWus0xsafy5z1AJdTeXZdBXPVvUSNVOUw8lbL+RTWI2Q== ricardo@dol-guldur
          - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDsVSvxBitgaOiqeX4foCfhIe4yZj+OOaWP+wFuoUOBCZMWQ3cW188nSyXhXKfwYK50oo44O6UVEb2GZiU9bLOoy1fjfiGMOnmp3AUVG+e6Vh5aXOeLCEKKxV3I8LjMXr4ack6vtOqOVFBGFSN0ThaRTZwKpoxQ+pEzh+Q4cMJTXBHXYH0eP7WEuQlPIM/hmhGa4kIw/A92Rm0ZlF2H6L2QzxdLV/2LmnLAkt9C+6tH62hepcMCIQFPvHVUqj93hpmNm9MQI4hM7uK5qyH8wGi3nmPuX311km3hkd5O6XT5KNZq9Nk1HTC2GHqYzwha/cAka5pRUfZmWkJrEuV3sNAl ansible@pimaster


```




## How to validate cloud-init file format

```shell
cloud-init schema --config-file user-data
```




## References

- [Setup PXE Boot Server using cloud-init for Ubuntu 20.04](https://www.golinuxcloud.com/pxe-boot-server-cloud-init-ubuntu-20-04/)
- [Setup IPv4 UEFI PXE Boot Server Ubuntu 20.04 [cloud-init]](https://www.golinuxcloud.com/uefi-pxe-boot-server-ubuntu-20-04-cloud-init/)
- [Ubuntu Automated Server Installation](https://ubuntu.com/server/docs/install/autoinstall)
- [Netbooting the server installer on amd64](https://ubuntu.com/server/docs/install/netboot-amd64)
- [Ubuntu 22.04 (Jammy) autoinstall over PXE](https://www.molnar-peter.hu/en/ubuntu-jammy-netinstall-pxe.html)
- [Using Ubuntu Live-Server to automate Desktop installation](https://github.com/canonical/autoinstall-desktop)
- [Configuring PXE Network Boot Server on Ubuntu 22.04 LTS](https://linuxhint.com/pxe_boot_ubuntu_server/)
- 
- [How to manage multiple Ubuntu servers with UEFI PXE boot](https://askubuntu.com/questions/1377514/how-to-manage-multiple-ubuntu-servers-with-uefi-pxe-boot)](https://askubuntu.com/questions/1377514/how-to-manage-multiple-ubuntu-servers-with-uefi-pxe-boot)


