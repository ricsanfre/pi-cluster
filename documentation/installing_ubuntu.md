# Ubuntu 20.04 Installation on Raspberry Pis

Ubuntu Server 64 bits installation on Raspberry Pi is supported since release 20.04.
Ubuntu images can be downloaded from [here](https://ubuntu.com/download/raspberry-pi).

Ubuntu Server 20.04.2 LTS for ARM64 image will be used.

## Headless installation

Ubuntu cloud-init configuration files within the image (`/boot/user-data` and `/boot/network-config`) will be modified before the first startup.
