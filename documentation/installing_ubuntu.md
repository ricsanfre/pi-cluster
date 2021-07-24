# Ubuntu 20.04 Installation on Raspberry Pis

Ubuntu Server 64 bits installation on Raspberry Pi is supported since release 20.04.
Ubuntu images can be downloaded from [here](https://ubuntu.com/download/raspberry-pi).

Ubuntu Server 20.04.2 LTS for ARM64 image will be used.

## Headless installation

Ubuntu cloud-init configuration files within the image (`/boot/user-data` and `/boot/network-config`) will be modified before the first startup.



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