---
title: Raspberry PI firmware update
permalink: /docs/firmware/
description: How to update firmware of our Raspberry Pi cluster nodes. Neeeded for enabling boot from USB and keep it updated.
last_modified_at: "25-02-2022"
---

Raspberry Pi Firmware update procedure and preparing Raspberry Pis for booting from USB

## About USB Booting support (Raspberry Pi 4 and Ubuntu)

Raspberry Pi’s bootloader has a 2020/09/03 version that just started supporting booting from USB.
Ubuntu 20.04.02 LTS (Long Time Support) does not support "out-of-the-box" booting from USB and it is needed to make changes into boot folder kernel files. It can be done following this [guide](https://jamesachambers.com/raspberry-pi-4-ubuntu-20-04-usb-mass-storage-boot-guide/).

Ubuntu 20.10 and 21.04 (not LTS) already support booting from USB “out-of-the-box”.
Since 20.10 and 21.04 are development releases and not LTS releases, are less stable and to avoid issues Ubuntu 20.04 will be used within the cluster.

First step is to prepare Raspberry Pis to update its Firmware and enable boot from USB stick. 
Firmware update and bootloader configuration is fully supported only using Raspberry Pi OS.

## Configure headless Raspberry OS

Prepare Raspberry PI OS for a headless start-up (without keyboard and monitor) enabling remote ssh connection and wifi access to home network.

- Step 1. Download Raspberry Pi OS  lite
  These instructions are for a Raspberry Pi OS Lite, image that can be downloaded from here:

  https://www.raspberrypi.org/software/operating-systems/

  I’m using the lite image (no desktop) kernel version 5.10 from May 7th, 2021.

- Step 2. Burn the Raspberry Pi OS image to the SD card
  
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

- Step 3. Enable ssh to allow remote login

  For security reasons, ssh is no longer enabled by default. To enable it you need to place an empty file named ssh (no extension) in the root of the boot disk.Enable ssh to do remote login: <br> Create a empty file named `ssh` within `boot` directory

- Step 4. Enable wifi connection

  Create a file `boot/wpa_supplicant.conf` with the following content, including wifi SSID name and password: 
  ```
  country=ES
  ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
  update_config=1

  network={
      ssid="NETWORK-NAME"
      psk="NETWORK-PASSWORD"
  }
  ```

- Step 5. Eject the micro SD card

  Right-click on boot (on your desktop or File Explorer) and select the Eject option

- Step 6. Boot the Raspberry Pi from the micro SD card

  Remove the mini-SD card from the adapter and plug it into the Raspberry Pi. Plug a USB-C power supply cable into the power port

- Step 7. Connect through SSH to the Raspberry Pi

  Connect through SSH to the Raspberry PI using default user and password (pi/raspberry)

## Get latest updates of the OS and the firmware

First make sure that you have the absolute latest updates and firmware for the Pi. To upgrade all your packages and firmware to the latest version use the following command:

```shell
sudo apt update && sudo apt full-upgrade -y
```

Once the update has completed restart your Pi with a `sudo reboot` command to apply the latest firmware / kernel updates.

## Verify EEPROM Bootloader is up to date

We can check if your Pi’s bootloader firmware is up to date with the following command:

```shell
sudo rpi-eeprom-update
```

If your Raspbian is *very* out of date you may not have this utility and can install it using:

```shell
sudo apt install rpi-eeprom
```

The output from rpi-eeprom-update will look like this if you are not up to date:
```
*** UPDATE AVAILABLE ***
BOOTLOADER: update available
   CURRENT: Tue 16 Feb 13:23:36 UTC 2021 (1613481816)
    LATEST: Thu 29 Apr 16:11:25 UTC 2021 (1619712685)
   RELEASE: default (/lib/firmware/raspberrypi/bootloader/default)
            Use raspi-config to change the release.

  VL805_FW: Using bootloader EEPROM
     VL805: up to date
   CURRENT: 000138a1
    LATEST: 000138a1
```

The ouput from rpi-eeprom-update will look like this if the firmware is up to date:

```
BOOTLOADER: up to date
   CURRENT: Thu 29 Apr 16:11:25 UTC 2021 (1619712685)
    LATEST: Thu 29 Apr 16:11:25 UTC 2021 (1619712685)
   RELEASE: default (/lib/firmware/raspberrypi/bootloader/default)
            Use raspi-config to change the release.

  VL805_FW: Dedicated VL805 EEPROM
     VL805: up to date
   CURRENT: 000138a1
    LATEST: 000138a1
```

If it says any updates are available they be installed manually by adding ‘-a’ to the end of our previous command like this:

```shell
sudo rpi-eeprom-update -a
```

A reboot is required to apply the changes

## Modify Boot Order if needed

Check current boot order configuration with command

```shell
rpi-eeprom-config
```

The ouput should show as part of the configuration

```
BOOT_ORDER=0xf14
```

Which means "Try USB first, followed by SD then repeat".

{{site.data.alerts.note}}
If not specified in the eeprom config, default value is BOOT_ORDER=0xf41 (Try SD first, and then USB. Then repeat)
{{site.data.alerts.end}}

Check [documentation](https://www.raspberrypi.org/documentation/hardware/raspberrypi/bcm2711_bootloader_config.md) for details about bootloader configuration.

If the BOOT_ORDER is not set, change it using [raspi-config](https://www.raspberrypi.org/documentation/configuration/raspi-config.md) tool executing:

```shell
sudo raspi-config
```

- Step 1 Select **6. Advanced Options**

  ![raspi-menu](/assets/img/raspi-config-window-1.png)

- Step 2. Select **A6. Boot Order** 

  ![raspi-menu](/assets/img/raspi-config-window-2.png)

- Step 3. Select **B2 USB Boot**

  ![raspi-menu](/assets/img/raspi-config-window-3.png)

- Step 4. Select **OK** and **Finish**

- Step 5. Reboot Raspberry Pi


## Headless configuration for Desktop Version: Enable VNC Remote Connect

In case Raspberry PI desktop version is used (i.e. gparted application configuration), VNC remote connection can be enabled.

Using `raspi-config` tool.

```shell
sudo raspi-config
```

- Step 1. Enable VNC

  Select **Interfacing Options**
  Select **VNC**
  For the prompt to enable VNC, select Yes (Y)
  For the confirmation, select Ok

- Step 2. Change Change the default screen resolution

  There is a weird quirk where you must change the screen resolution or VNC will report “Cannot currently show the desktop.”

  Still from within raspi-config:

  Select **Display**
  on older versions this was under Advanced Options
  Select **Resolution**
  Select anything but the default (example: 1024x768)
  Select Ok
  Once you’ve established that it works, you can go back and try other screen resolutions.

- Step 3. Save raspi-config changes and reboot

  Select Finish
  For the reboot prompt, select Yes

- Step 4. Install the RealVNC viewer on your computer, smartphone or tablet
  Download the RealVNC viewer for your operating system.

  Browse to:

  https://www.realvnc.com/en/connect/download/viewer/
  For some operating systems the downloaded file may be an installer that needs to run. If that’s the case, run the installer.
- Step 5. Connect over VNC
  Launch the VNC viewer on your computer and type the IP of the Raspberry Pi server into the Connect address bar.
