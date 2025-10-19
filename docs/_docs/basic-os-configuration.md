---
title: OS initial setup
permalink: /docs/os-basic/
description: Basic Ubuntu OS configurations of our Raspberry Pi cluster nodes.
last_modified_at: "17-05-2023"
---

## Removing snap package

Free resources (computing, memory and storage) since I am not going to use snap package manager.

- Step 1. List snap packages installed
  
  ```shell
  sudo snap list
  ```

  The output will something like

  ```shell
  sudo snap list
  Name    Version   Rev    Tracking       Publisher   Notes
  core18  20210611  2074   latest/stable  canonical✓  base
  lxd     4.0.7     21029  4.0/stable/…   canonical✓  -
  snapd   2.51.1    12398  latest/stable  canonical✓  snapd
  ```

- Step 2. Remove snap packages with command `snap remove <package>`

  ```shell
  snap remove lxd && snap remove core18 && snap remove snapd
  ```

- Step 3. Remove snapd package

  ```shell
  sudo apt purge snapd
  ```

  Remove packages not required

  ```shell
  sudo apt autoremove
  ```

## Raspberry PI specific configuration

### Installing Fake RTC clock

Raspberry PI does not have by default a RTC (real-time clock) keeping the time when the Raspberry PI is off. A RTC module can be added to each RaspberryPI but we won't do it here since we will use NTP to keep time in sync.

Even when NTP is used to synchronize the time and date, when it boots takes as current-time the time of the first-installation and it could cause problems in boot time when the OS detect that a mount point was created in the future and ask for manual execution of fscsk

{{site.data.alerts.note}}
I have detected this behaviour with my Raspberry PIs when mounting the iSCSI LUNs in `node1-node6` and after rebooting the server, the server never comes up.
{{site.data.alerts.end}}

As a side effect the NTP synchronizatio will also take longer since NTP adjust the time in small steps.

For solving this [`fake-hwclock`](http://manpages.ubuntu.com/manpages/focal/man8/fake-hwclock.8.html) package need to be installed. `fake-hwclock` keeps track of the current time in a file and it load the latest time stored in boot time.

### Installing Utility scripts

Raspberry PI OS contains several specific utilities such as `vcgencmd` that are also available in Ubuntu 24.04 through the package [`libraspberrypi-bin`](https://packages.ubuntu.com/jammy/libraspberrypi-bin)

```shell
sudo apt install libraspberrypi-bi
```

Two scripts, using `vcgencmd` command for checking temperature and throttling status of Raspberry Pi, can be deployed on each Raspberry Pi (in `/usr/local/bin` directory)

`pi_temp` for getting Raspberry Pi temperature
`pi_throttling` for getting the throttling status

Boths scripts can be executed remotely with Ansible:

```shell

ansible -i inventory.yml -b -m shell -a "pi_temp" raspberrypi
    
ansible -i inventory.yml -b -m shell -a "pi_throttling" raspberrypi
```

### Change default GPU Memory Split

The Raspberry PI allocates part of the RAM memory to the GPU (76 MB of the available RAM)

Since the Raspberry PIs in the cluster are configured as a headless server, without monitorm and using the server Ubuntu distribution (not desktop GUI) Rasberry PI reserved GPU Memory can be set to lowest possible (16M).

- Step 1. Edit `/boot/firmware/config.txt` file, adding at the end:

  ```
  gpu_mem=16
  ```

- Step 2. Reboot the Raspberry Pi

  ```shell
  sudo reboot
  ```


### Enabling VXLAN module (Ubuntu 22.04)


VXLAN support is not present in kernel since Ubuntu 21.04. It makes K3S fail to run. See more details in [K3S issue](https://github.com/k3s-io/k3s/issues/4234)

Starting with Ubuntu 21.10, vxlan support on Raspberry Pi has been moved into a separate kernel module, that need to be manually installed. See specific [Raspberry PI K3S specific installation requirements](https://docs.k3s.io/advanced#raspberry-pi). Further details in this [Ubuntu bug: "VXLAN support is not present in kernel - Ubuntu 21.10 on Raspberry Pi 4 (64bit)"](https://bugs.launchpad.net/ubuntu/+source/linux-raspi/+bug/1947628)

```shell
sudo apt install linux-modules-extra-raspi & reboot
```

{{site.data.alerts.note}}

This step is not needed anynore for Ubuntu 24.04 since the 6.7.0 version of the kernel packages, there is no linux-modules-extra package any more and everything has been combined into the linux-modules package.

See more details in this [Launchpad answer](https://answers.launchpad.net/ubuntu/+source/linux-raspi/+question/817506)

{{site.data.alerts.end}}