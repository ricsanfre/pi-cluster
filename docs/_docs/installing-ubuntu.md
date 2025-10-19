---
title: OS Installation - Raspberry Pi
permalink: /docs/ubuntu/rpi/
description: How to install ARM-64 based Ubuntu OS in of our Raspberry Pi cluster nodes. How to configure boot from USB.
last_modified_at: "09-06-2023"
---

Ubuntu Server 64 bits installation on Raspberry Pi is supported since release 20.04.
Ubuntu images for Raspberry Pi can be downloaded from [Ubuntu's download page](https://ubuntu.com/download/raspberry-pi).

Ubuntu Server 24.04.3 LTS for ARM64 image will be used.


## Headless installation

Fast deployment of a headless Ubuntu 64 bits OS in Raspberry Pi 4 using **cloud-init**.

Ubuntu cloud-init configuration files within the image (`/boot/user-data` and `/boot/network-config`) will be modified before the first startup.


- Step 1. Burn the Ubuntu OS image to a SD-card or USB flash drive

  SDCard or USB 3.0 Flass Drive (or SSD disk connected through a USB3.0 to SATA adapter) can be used to hosts the OS.

  [Raspberry PI Imager](https://www.raspberrypi.com/software/) can be used to burn Ubuntu 24.04 Server (64 bits) OS into a SD Card/USB Flash disk.


- Step 3: Mofify user-data network-config within /boot directory in the SDCard or USB Flash drive/SSD

  - Modify file `/boot/user-data`

    As an example this cloud-init `user-data` file, set hostname, locale and timezone and specify a new user, `ricsanfre` (removing default `ubuntu` user) with its ssh public keys
    
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
      - name: ricsanfre
        primary_group: users
        groups: [adm, admin]
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        lock_passwd: true
        ssh_authorized_keys:
          - ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAusTXKfFoy6p3G4QAHvqoBK+9Vn2+cx2G5AY89WmjMikmeTG9KUseOCIAx22BCrFTNryMZ0oLx4u3M+Ibm1nX76R3Gs4b+gBsgf0TFENzztST++n9/bHYWeMVXddeV9RFbvPnQZv/TfLfPUejIMjFt26JCfhZdw3Ukpx9FKYhFDxr2jG9hXzCY9Ja2IkVwHuBcO4gvWV5xtI1nS/LvMw44Okmlpqos/ETjkd12PLCxZU6GQDslUgGZGuWsvOKbf51sR+cvBppEAG3ujIDySZkVhXqH1SSaGQbxF0pO6N5d4PWus0xsafy5z1AJdTeXZdBXPVvUSNVOUw8lbL+RTWI2Q== ubuntu@mi_pc
    ## Reboot to enable Wifi configuration (more details in network-config file)
    power_state:
      mode: reboot

    ```

    {{site.data.alerts.important}}

    Before applying the provided cloud-init files remember to change user name (`ricsanfre`) and `ssh_authorized_keys` field. Your own user_name and ssh public keys must be included.

    `timezone` and `locale` can be changed as well to fit your environment. 

    {{site.data.alerts.end}}

  - Modify `/boot/network-config` file within the SDCard/Fash drive

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


## Automating Image creation (USB Booting)

Using a Linux desktop, creation of booting USB SSD disk for different cluster nodes can be automated.

- Step 1. Download Ubuntu 24.04 Raspberry PI 64 bits image

  https://cdimage.ubuntu.com/releases/22.04/release/ 

  ```shell
  IMG=ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz
  URL_IMG=https://cdimage.ubuntu.com/releases/24.04/release/${IMG}
  mkdif img
  # Download Image
  wget ${URL_IMG} -O img/${IMG}
  ```

- Step 2. Insert USB SSD disk

  Get device associated with USB disk (i.e: /dev/sdb) executing command `lsblk`

  ```shell
  USB=/dev/sdb
  ```

- Step 3: Optional (Wipe USB disk partition table)

  This remove current partition tables defined in the USB disk.

  ```shell
  sudo wipefs -a -f ${USB}
  ```

- Step 4: burn image into USB disk

  ```shell
  # `-d` decompress `<` redirect $FILE contents to expand `|` sending the output to `dd` to copy directly to $USB
  xz -d < img/${IMG} - | sudo dd bs=100M of=${USB}
  ```

- Step 5: Mount system-boot in the burned image

  ```shell
  SYSTEM_BOOT_MOUNT=/tmp/pi-disk
  sudo mkdir ${SYSTEM_BOOT_MOUNT}
  # Mount first partition of device /dev/sdb1 corresponding with system-boot partion
  sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
  ```

- Step 6: Copy cloud-init configuration files

  ```shell
  sudo cp user-data ${SYSTEM_BOOT_MOUNT}
  sudo cp network-config ${SYSTEM_BOOT_MOUNT}
  ```

- Step 7: Unmount system-boot partition

  ```shell
  sudo umount ${SYSTEM_BOOT_MOUNT}
  ```

## Ubuntu 20.04 USB Booting

Ubuntu LTS 22.04 supports out-of-the-box booting from USB Flash Drive/SSD. In case of using Ubuntu LTS 20.04 release additional steps are required to enable USB booting

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

