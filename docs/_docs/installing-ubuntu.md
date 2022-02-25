---
title: Ubuntu OS Installation
permalink: /docs/ubuntu/
description: How to install ARM-64 based Ubuntu 20.04 OS in of our Raspberry Pi cluster nodes. How to configure boot from USB.
last_modified_at: "25-02-2022"
---

Ubuntu Server 64 bits installation on Raspberry Pi is supported since release 20.04.
Ubuntu images can be downloaded from [here](https://ubuntu.com/download/raspberry-pi).

Ubuntu Server 20.04.3 LTS for ARM64 image will be used.


## Headless installation

Fast deployment of a headless Ubuntu 64 bits OS in Raspberry Pi 4 configuring **cloud-init**.
Ubuntu cloud-init configuration files within the image (`/boot/user-data` and `/boot/network-config`) will be modified before the first startup.

- Step 1. Download Ubuntu 20.04 OS for Raspberry PI

  Ubuntu 20.04 LTS image that can be downloaded from here:

  https://ubuntu.com/download/raspberry-pi


- Step 2. Burn the Ubuntu OS image to the SD card

  Burn the latest Raspberry Pi OS image to SD-Card using Etcher

  Browse to https://www.balena.io/etcher/
  Download the version for your operating system
  Run the installer
  To run Etcher is pretty straight forward.

  Put a blank mini SD card and adapter into your machine. No need to format it. You can use a new SD card right out of the package.

  1 - Click **Flash from file** - browse to the zip file you downloaded for Raspberry Pi OS.<br>
  2 - Click **Select target** - it may find the SDHC Card automatically, if not select it.<br>
  3 - Click **Flash!** - you may be prompted for your password

  After you flash (burn) the image,  File Explorer (Windows) may have trouble seeing it. A simple fix is to pull the SD card out then plug it back in. On Windows it should appear in File Explorer with the name boot followed by a drive letter.

- Step 3: Mofify user-data network-config within /boot directory in the SDCard

  - Modify file `/boot/user-data`

    As an example this cloud-init `user-data` file, set hostname, locale and timezone and specify a couple of users, `oss` and `ansible` (removing default `ubuntu` user) with its ssh public keys
    
    ```yml
    #cloud-config

    # Set TimeZone and Locale
    timezone: Europe/Madrid
    locale: es_ES.UTF-8

    # Hostname
    hostname: gateway

    # cloud-init not managing hosts file. only hostname is added
    manage_etc_hosts: localhost

    users:
      # not using default ubuntu user
      - name: oss
        primary_group: users
        groups: [adm, admin]
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: true
        ssh_authorized_keys:
          - ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAusTXKfFoy6p3G4QAHvqoBK+9Vn2+cx2G5AY89WmjMikmeTG9KUseOCIAx22BCrFTNryMZ0oLx4u3M+Ibm1nX76R3Gs4b+gBsgf0TFENzztST++n9/bHYWeMVXddeV9RFbvPnQZv/TfLfPUejIMjFt26JCfhZdw3Ukpx9FKYhFDxr2jG9hXzCY9Ja2IkVwHuBcO4gvWV5xtI1nS/LvMw44Okmlpqos/ETjkd12PLCxZU6GQDslUgGZGuWsvOKbf51sR+cvBppEAG3ujIDySZkVhXqH1SSaGQbxF0pO6N5d4PWus0xsafy5z1AJdTeXZdBXPVvUSNVOUw8lbL+RTWI2Q== ubuntu@mi_pc
      # Ansible user
      - name: ansible
        primary_group: users
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: true
        ssh_authorized_keys:
          - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDsVSvxBitgaOiqeX4foCfhIe4yZj+OOaWP+wFuoUOBCZMWQ3cW188nSyXhXKfwYK50oo44O6UVEb2GZiU9bLOoy1fjfiGMOnmp3AUVG+e6Vh5aXOeLCEKKxV3I8LjMXr4ack6vtOqOVFBGFSN0ThaRTZwKpoxQ+pEzh+Q4cMJTXBHXYH0eP7WEuQlPIM/hmhGa4kIw/A92Rm0ZlF2H6L2QzxdLV/2LmnLAkt9C+6tH62hepcMCIQFPvHVUqj93hpmNm9MQI4hM7uK5qyH8wGi3nmPuX311km3hkd5O6XT5KNZq9Nk1HTC2GHqYzwha/cAka5pRUfZmWkJrEuV3sNAl ansible@pimaster

    ## Reboot to enable Wifi configuration (more details in network-config file)
    power_state:
      mode: reboot

    ```

    {{site.data.alerts.important}}

    Before applying the provided cloud-init files remember to change `ssh_authorized_keys` fields for both users (`ansible` and the non-default `ubuntu`). Your own ssh public keys must be included.

    `timezone` and `locale` can be changed as well to fit your environment. 

    {{site.data.alerts.end}}

  - Modify `/boot/network-config` file within the SDCard

    ```yml
    version: 2
    ethernets:
      eth0:
        dhcp4: false
        addresses: [10.0.0.1/24]
    wifis:
      wlan0:
        dhcp4: true
        optional: true
        access-points:
          "<SSID_NAME>":
          password: "<SSID_PASSWD>"
    ```
    {{site.data.alerts.important}}

    Remember to include the SSID name and password of your home network

    {{site.data.alerts.end}}

## (Optional) USB Booting

As alternative to using a SDCard a USB 3.0 Flass Drive (or SSD disk connected through a USB3.0 to SATA adapter) can be used to hosts the OS.

Latest version of LTS 20.04.2 does not allow to boot from USB directy and some additional steps are required. 

You can follow the instructions of this [post](https://jamesachambers.com/raspberry-pi-4-ubuntu-20-04-usb-mass-storage-boot-guide/).

- Step 1. Flash USB Flash Disk/SSD Disk with Ubuntu 20.04

  Repeat the steps for flashing Ubuntu image, but selecting the USB Flash Drive instead the SDCard

- Step 2. Boot the Raspberry Pi with Raspi OS Lite

  The SDCard burnt in [preparing Raspberry Pi](/docs/firmware/) section, can be used for booting the RaspberryPI.

- Step 3. Plug in the USB Flash Disk/SSD Disk using USB 3.0 port in Raspberry Pi 

  Execute `lsblk` for finding the new USB disk

  ```
  lsblk
  NAME        MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
  sda           8:0    1 29.9G  0 disk
  ├─sda1        8:1    1  256M  0 part
  └─sda2        8:2    1  2.8G  0 part
  mmcblk0     179:0    0 29.7G  0 disk
  ├─mmcblk0p1 179:1    0  256M  0 part /boot
  └─mmcblk0p2 179:2    0 29.5G  0 part /
  ```
  {{site.data.alerts.note}}
  In this case USB device is labelled as sda: two partitions (boot and OS) are automatically created by initial image burning process.
  - boot partition: sda1
  - root filesystem: sda2
  {{site.data.alerts.end}}

- Step 3.5 (Case of SSDD with USB to SATA Adapter). Checking USB-SATA Adapter support UASP

  Checking that the USB SATA adapter suppors UASP.

  ```shell
  lsusb -t

  /:  Bus 02.Port 1: Dev 1, Class=root_hub, Driver=xhci_hcd/4p, 5000M
      |__ Port 1: Dev 2, If 0, Class=Mass Storage, Driver=uas, 5000M
  /:  Bus 01.Port 1: Dev 1, Class=root_hub, Driver=xhci_hcd/1p, 480M
      |__ Port 1: Dev 2, If 0, Class=Hub, Driver=hub/4p, 480M
          |__ Port 3: Dev 3, If 0, Class=Human Interface Device, Driver=usbhid, 1.5M
          |__ Port 3: Dev 3, If 1, Class=Human Interface Device, Driver=usbhid, 1.5M
          |__ Port 4: Dev 4, If 0, Class=Human Interface Device, Driver=usbhid, 1.5M

  ```

  `Driver=uas` indicates that the adpater supports UASP.


  Check USB-SATA adapter ID

  ```shell
  sudo lsusb
  Bus 002 Device 002: ID 174c:55aa ASMedia Technology Inc. Name: ASM1051E SATA 6Gb/s bridge, ASM1053E SATA 6Gb/s bridge, ASM1153 SATA 3Gb/s bridge, ASM1153E SATA 6Gb/s bridge
  Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
  Bus 001 Device 004: ID 0000:3825
  Bus 001 Device 003: ID 145f:02c9 Trust
  Bus 001 Device 002: ID 2109:3431 VIA Labs, Inc. Hub
  Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
  ```
  {{site.data.alerts.note}}
  In this case ASMedia TEchnology ASM1051E has ID 152d:0578
  {{site.data.alerts.end}}

- Step 4. Create 2 mountpoints  

  Now we are going to create two mountpoints and mount the Ubuntu drive.
  Use these commands substituting your own drive it is not /dev/sda:

  ```shell
  sudo mkdir /mnt/boot
  sudo mkdir /mnt/writable
  sudo mount /dev/sda1 /mnt/boot
  sudo mount /dev/sda2 /mnt/writable
  ```

  Check mounted disks with `lsblk` command:

  ```shell
  lsblk
  NAME        MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
  sda           8:0    1 29.9G  0 disk
  ├─sda1        8:1    1  256M  0 part /mnt/boot
  └─sda2        8:2    1  2.8G  0 part /mnt/writable
  mmcblk0     179:0    0 29.7G  0 disk
  ├─mmcblk0p1 179:1    0  256M  0 part /boot
  └─mmcblk0p2 179:2    0 29.5G  0 part /
  ```

- Step 5. Modify Mounted Partitions to fix booting procedure from disk 

  Modify step 4 mounted partitions using script from James A. Chambers

  Download and execute the automated script:

  ```shell
  curl https://raw.githubusercontent.com/TheRemote/Ubuntu-Server-raspi4-unofficial/master/BootFix.sh -o BootFix.sh
  chmod +x BootFix.sh
  sudo ./BootFix.sh
  ```

  The script output should be like:

  ```shell
  sudo ./BootFix.sh
  Found writable partition at /mnt/writable
  Found boot partition at /mnt/boot
  Decompressing kernel from vmlinuz to vmlinux...
  Kernel decompressed
  Updating config.txt with correct parameters...
  Creating script to automatically decompress kernel...
  Creating apt script to automatically decompress kernel...
  Updating Ubuntu partition was successful!  Shut down your Pi, remove the SD card then reconnect the power.
  ```

- Step 6. Shutdown Raspberry Pi, remove SDCard and boot again from USB
  RaspberryPI is  now able to boot from USB without needing a SDCard
