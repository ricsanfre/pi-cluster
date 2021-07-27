#!/bin/bash
# Script that fixes an Ubuntu 20.04 / 20.10 partition created by the official Raspberry Pi Imager to boot with a Raspberry Pi 4
# by James A. Chambers - https://jamesachambers.com/raspberry-pi-4-ubuntu-20-04-usb-mass-storage-boot-guide

# First image your drive with Ubuntu 20.04 or 20.10 using the official Pi Imager tool
# Next connect your drive to the Raspberry Pi
# Find drive using lsblk (normally it's /dev/sda but check first) -- unmount if it was automatically mounted with sudo umount mountpoint (ex: sudo umount /media/pi/system-boot)
# Mount boot partition with sudo mount /dev/sda1 /mnt/boot
# Mount writable partition with sudo mount /dev/sda2 /mnt/writable
# Now you are ready to run this script to update the partition for Raspberry Pi booting

# Safety check, run as sudo
if [ $(id -u) != 0 ]; then
   echo "Safety check:  This script is meant to be ran as root or sudo.  Please run using sudo ./BootFix.sh.  Exiting..."
   exit 1
fi

# Safety check -- check for system-boot automount
if [ -d /media/*/system-boot ]; then
   echo "Safety check:  automount detected at /media/*/system-boot.  Please unmount the automount in File Explorer or with sudo umount /media/$LOGNAME/system-boot."
   exit 1
fi

# Safety check -- check for writable automount
if [ -d /media/*/writable ]; then
   echo "Safety check:  automount detected at /media/*/writable.  Please unmount the automount in File Explorer or with sudo umount /media/$LOGNAME/system-boot."
   exit 1
fi

# Find the "writable" root filesystem mount
if [ -d /mnt/writable ] && [ -d /mnt/writable/usr/lib/u-boot ] ; then
    mntWritable='/mnt/writable'
else
    echo "The partition 'writable' was not found in /mnt/writable.  Make sure you have mounted your USB mass storage device (ex: sudo mount /dev/sda2 /mnt/writable)."
    exit 1
fi
echo "Found writable partition at $mntWritable"

# Find the "system-boot" boot filesystem mount
if [ -d /mnt/boot ] && [ -e /mnt/boot/vmlinuz ]; then
    mntBoot='/mnt/boot'
else
    echo "The 'boot' partition was not found in /mnt/boot.  Make sure you have mounted your USB mass storage device (ex: sudo mount /dev/sda1 /mnt/boot)."
    exit 1
fi
echo "Found boot partition at $mntBoot"

# Decompress the kernel
echo "Decompressing kernel from vmlinuz to vmlinux..."
zcat -qf "$mntBoot/vmlinuz" > "$mntBoot/vmlinux"
echo "Kernel decompressed"

# Check if 32 bit or 64 bit and modify config.txt
if cat "$mntBoot/config.txt" | grep -q "arm_64bit=1"; then

# Update config.txt with correct parameters
echo "Updating config.txt with correct parameters..."

cat <<EOF | sudo tee "$mntBoot/config.txt">/dev/null
# Please DO NOT modify this file; if you need to modify the boot config, the
# usercfg.txt file is the place to include user changes. Please refer to
# the README file for a description of the various configuration files on
# the boot partition.

# The unusual ordering below is deliberate; older firmwares (in particular the
# version initially shipped with bionic) don't understand the conditional
# [sections] below and simply ignore them. The Pi4 doesn't boot at all with
# firmwares this old so it's safe to place at the top. Of the Pi2 and Pi3, the
# Pi3 uboot happens to work happily on the Pi2, so it needs to go at the bottom
# to support old firmwares.

[pi4]
max_framebuffers=2
dtoverlay=vc4-fkms-v3d
boot_delay
kernel=vmlinux
initramfs initrd.img followkernel

[pi2]
boot_delay
kernel=vmlinux
initramfs initrd.img followkernel

[pi3]
boot_delay
kernel=vmlinux
initramfs initrd.img followkernel

[all]
arm_64bit=1
device_tree_address=0x03000000

# The following settings are defaults expected to be overridden by the
# included configuration. The only reason they are included is, again, to
# support old firmwares which don't understand the include command.

enable_uart=1
cmdline=cmdline.txt

include syscfg.txt
include usercfg.txt

EOF

# End 64 bit
else

# Update config.txt with correct parameters
echo "Updating config.txt with correct parameters..."

cat <<EOF | sudo tee "$mntBoot/config.txt">/dev/null
# Please DO NOT modify this file; if you need to modify the boot config, the
# usercfg.txt file is the place to include user changes. Please refer to
# the README file for a description of the various configuration files on
# the boot partition.

# The unusual ordering below is deliberate; older firmwares (in particular the
# version initially shipped with bionic) don't understand the conditional
# [sections] below and simply ignore them. The Pi4 doesn't boot at all with
# firmwares this old so it's safe to place at the top. Of the Pi2 and Pi3, the
# Pi3 uboot happens to work happily on the Pi2, so it needs to go at the bottom
# to support old firmwares.

[pi4]
max_framebuffers=2
dtoverlay=vc4-fkms-v3d
boot_delay
kernel=vmlinux
initramfs initrd.img followkernel

[pi2]
boot_delay
kernel=vmlinux
initramfs initrd.img followkernel

[pi3]
boot_delay
kernel=vmlinux
initramfs initrd.img followkernel

[all]
device_tree_address=0x03000000

# The following settings are defaults expected to be overridden by the
# included configuration. The only reason they are included is, again, to
# support old firmwares which don't understand the include command.

enable_uart=1
cmdline=cmdline.txt

include syscfg.txt
include usercfg.txt

EOF

# End 32 bit
fi


# Create script to automatically decompress kernel (source: https://www.raspberrypi.org/forums/viewtopic.php?t=278791)
echo "Creating script to automatically decompress kernel..."
cat << \EOF | sudo tee "$mntBoot/auto_decompress_kernel">/dev/null
#!/bin/bash -e
# auto_decompress_kernel script
BTPATH=/boot/firmware
CKPATH=$BTPATH/vmlinuz
DKPATH=$BTPATH/vmlinux
# Check if compression needs to be done.
if [ -e $BTPATH/check.md5 ]; then
   if md5sum --status --ignore-missing -c $BTPATH/check.md5; then
      echo -e "\e[32mFiles have not changed, Decompression not needed\e[0m"
      exit 0
   else
      echo -e "\e[31mHash failed, kernel will be compressed\e[0m"
   fi
fi
# Backup the old decompressed kernel
mv $DKPATH $DKPATH.bak
if [ ! $? == 0 ]; then
   echo -e "\e[31mDECOMPRESSED KERNEL BACKUP FAILED!\e[0m"
   exit 1
else
   echo -e "\e[32mDecompressed kernel backup was successful\e[0m"
fi
# Decompress the new kernel
echo "Decompressing kernel: "$CKPATH".............."
zcat -qf $CKPATH > $DKPATH
if [ ! $? == 0 ]; then
   echo -e "\e[31mKERNEL FAILED TO DECOMPRESS!\e[0m"
   exit 1
else
   echo -e "\e[32mKernel Decompressed Succesfully\e[0m"
fi
# Hash the new kernel for checking
md5sum $CKPATH $DKPATH > $BTPATH/check.md5
if [ ! $? == 0 ]; then
   echo -e "\e[31mMD5 GENERATION FAILED!\e[0m"
else
   echo -e "\e[32mMD5 generated Succesfully\e[0m"
fi
exit 0
EOF
sudo chmod +x "$mntBoot/auto_decompress_kernel"

# Create apt script to automatically decompress the kernel
echo "Creating apt script to automatically decompress kernel..."
echo 'DPkg::Post-Invoke {"/bin/bash /boot/firmware/auto_decompress_kernel"; };' | sudo tee "$mntWritable/etc/apt/apt.conf.d/999_decompress_rpi_kernel" >/dev/null
sudo chmod +x "$mntWritable/etc/apt/apt.conf.d/999_decompress_rpi_kernel"

# Successful
echo "Updating Ubuntu partition was successful!  Shut down your Pi, remove the SD card then reconnect the power."
