# Ubuntu 20.04 Installation on Raspberry Pis

Ubuntu Server 64 bits installation on Raspberry Pi is supported since release 20.04.
Ubuntu images can be downloaded from [here](https://ubuntu.com/download/raspberry-pi).

Ubuntu Server 20.04.2 LTS for ARM64 image will be used.


## Headless installation

Fast deployment of a headless Ubuntu 64 bits OS in Raspberry Pi 4 configuring **cloud-init**.
Ubuntu cloud-init configuration files within the image (`/boot/user-data` and `/boot/network-config`) will be modified before the first startup.

### Step 1. Download Ubuntu 20.04 OS for Raspberry PI

Ubuntu 20.04 LTS image that can be downloaded from here:

https://ubuntu.com/download/raspberry-pi


### Step 2. Burn the Raspberry Pi OS image to the SD card
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

### Step 3: Mofify user-data network-config within /boot directory in the SDCard

- Modify file `/boot/user-data`

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
- Modify `/boot/network-config` file within the SDCard

    ```
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


## (Optional) USB Booting

As alternative to using a SDCard a USB 3.0 Flass Drive can be used to hosts the OS.

Latest version of LTS 20.04.2 does not allow to boot from USB directy and some additional steps are required. 

You can follow the instructions of this [post](https://jamesachambers.com/raspberry-pi-4-ubuntu-20-04-usb-mass-storage-boot-guide/).

### Step 1. Flash USB Flash Disk with Ubuntu 20.04

Repeat the steps for flashing Ubuntu image, but selecting the USB Flash Drive instead the SDCard

### Step 2. Boot the Raspberry Pi with Raspi OS Lite

The SDCard burnt in [preparing Raspberry Pi](preparing_raspberrypi.md) section, can be used for booting the RaspberryPI.

### Step 3. Plug in the USB Flash Disk using USB 3.0 port in Raspberry Pi 

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
### Step 4. Create 2 mountpoints  

Now we are going to create two mountpoints and mount the Ubuntu drive.
Use these commands substituting your own drive it is not /dev/sda:
```
sudo mkdir /mnt/boot
sudo mkdir /mnt/writable
sudo mount /dev/sda1 /mnt/boot
sudo mount /dev/sda2 /mnt/writable
```

Check mounted disks with `lsblk` command:

```
lsblk
NAME        MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sda           8:0    1 29.9G  0 disk
├─sda1        8:1    1  256M  0 part /mnt/boot
└─sda2        8:2    1  2.8G  0 part /mnt/writable
mmcblk0     179:0    0 29.7G  0 disk
├─mmcblk0p1 179:1    0  256M  0 part /boot
└─mmcblk0p2 179:2    0 29.5G  0 part /
```

### Step 5. Modify Mounted Partitions – Using Automated Script from James A. Chambers

Download and execute the automated script:

    curl https://raw.githubusercontent.com/TheRemote/Ubuntu-Server-raspi4-unofficial/master/BootFix.sh -O BootFix.sh
    chmod +x BootFix.sh
    sudo ./BootFix.sh

The script output should be like:
```
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
### Step 6. Shutdown Raspberry Pi, remove SDCard and boot again from USB
RaspberryPI is  now able to boot from USB without needing a SDCard

# Ubuntu OS Preparation Tasks

## Removing snap package

### Step 1. List snap packages installed

    sudo snap list

The output will something like

    sudo snap list
    Name    Version   Rev    Tracking       Publisher   Notes
    core18  20210611  2074   latest/stable  canonical✓  base
    lxd     4.0.7     21029  4.0/stable/…   canonical✓  -
    snapd   2.51.1    12398  latest/stable  canonical✓  snapd


### Step 3. Remove snap packages

    snap remove <package>

    snap remove lxd && snap remove core18 && snap remove snapd

### Step 4. Remove snapd package

    sudo apt purge snapd

Remove packages not required

    sudo apt autoremove