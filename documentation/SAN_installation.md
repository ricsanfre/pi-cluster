# Configuring Raspberry PI as SAN for the lab cluster

The idea is to configure one of the Raspberry PIs as a SAN, connecting some SSD Disk to it (through USB 3.0 ports) and providing LUNs to all the cluster nodes through iSCSI.

A storage on a network is called iSCSI Target, a Client which connects to iSCSI Target is called iSCSI Initiator. In my home lab, `gateway` will be the iSCSI Target and `node1-node4` will be the iSCSI Initiators.

```
+----------------------+         |             +----------------------+
| [   iSCSI Target   ] |10.0.0.1 | 10.0.0.11-14| [ iSCSI Initiator  ] |
|        gateway       +---------+-------------+        node1-4       |
|                      |                       |                      |
+----------------------+                       +----------------------+

```

LIO, [LinuxIO](http://linux-iscsi.org/wiki/Main_Page), has been the Linux SCSI target since kernel version 2.6.38.
It support sharing different types of storage fabrics and backstorage devices, including block devices (including LVM logical volumes and physical devices).

**LUN is a Logical Unit Number**, which shared from the iSCSI Storage Server. The Physical drive of iSCSI target server shares its drive to initiator over TCP/IP network. A Collection of drives called LUNs to form a large storage as SAN (Storage Area Network). 

In real environment LUNs are defined in LVM, if so it can be expandable as per space requirements.

![LUNs-on-LVM](images/Creating_LUNs_using_LVM.png "Creating LUNS using LVM")

## iSCSI Qualifier Names (iqn)

Unique identifier are asigned to iSCSI Initiators and iSCSI targets
Format iqn.yyyy-mm.reverse_domain_name:any

In my case I will use hostname to make iqn unique

    iqn.2021-07.com.ricsanfre.picluster:<hostname>

## Hardware

A Kingston A400 480GB SSD Disk and a SATA Disk USB3.0 Case will be used for building Raspberry PI cluster.

## Preparing SSD Disk and LVM configuration for LUNS

### Step 1. Connect SSD Disk through USB 3.0 port

### Step 2. Partition HDD with `fdisk`

Add one primary partition (type LVM) using all disk space available.

```
sudo fdisk -c -u /dev/sdb

Welcome to fdisk (util-linux 2.34).
Changes will remain in memory only, until you decide to write them.
Be careful before using the write command.

Device does not contain a recognized partition table.
Created a new DOS disklabel with disk identifier 0x5721e48c.

Command (m for help): n
Partition type
   p   primary (0 primary, 0 extended, 4 free)
   e   extended (container for logical partitions)
Select (default p): p
Partition number (1-4, default 1): 1
First sector (2048-41943039, default 2048):
Last sector, +/-sectors or +/-size{K,M,G,T,P} (2048-41943039, default 41943039):

Created a new partition 1 of type 'Linux' and of size 20 GiB.

Command (m for help): t
Selected partition 1
Hex code (type L to list all codes): L

 0  Empty           24  NEC DOS         81  Minix / old Lin bf  Solaris
 1  FAT12           27  Hidden NTFS Win 82  Linux swap / So c1  DRDOS/sec (FAT-
 2  XENIX root      39  Plan 9          83  Linux           c4  DRDOS/sec (FAT-
 3  XENIX usr       3c  PartitionMagic  84  OS/2 hidden or  c6  DRDOS/sec (FAT-
 4  FAT16 <32M      40  Venix 80286     85  Linux extended  c7  Syrinx
 5  Extended        41  PPC PReP Boot   86  NTFS volume set da  Non-FS data
 6  FAT16           42  SFS             87  NTFS volume set db  CP/M / CTOS / .
 7  HPFS/NTFS/exFAT 4d  QNX4.x          88  Linux plaintext de  Dell Utility
 8  AIX             4e  QNX4.x 2nd part 8e  Linux LVM       df  BootIt
 9  AIX bootable    4f  QNX4.x 3rd part 93  Amoeba          e1  DOS access
 a  OS/2 Boot Manag 50  OnTrack DM      94  Amoeba BBT      e3  DOS R/O
 b  W95 FAT32       51  OnTrack DM6 Aux 9f  BSD/OS          e4  SpeedStor
 c  W95 FAT32 (LBA) 52  CP/M            a0  IBM Thinkpad hi ea  Rufus alignment
 e  W95 FAT16 (LBA) 53  OnTrack DM6 Aux a5  FreeBSD         eb  BeOS fs
 f  W95 Ext'd (LBA) 54  OnTrackDM6      a6  OpenBSD         ee  GPT
10  OPUS            55  EZ-Drive        a7  NeXTSTEP        ef  EFI (FAT-12/16/
11  Hidden FAT12    56  Golden Bow      a8  Darwin UFS      f0  Linux/PA-RISC b
12  Compaq diagnost 5c  Priam Edisk     a9  NetBSD          f1  SpeedStor
14  Hidden FAT16 <3 61  SpeedStor       ab  Darwin boot     f4  SpeedStor
16  Hidden FAT16    63  GNU HURD or Sys af  HFS / HFS+      f2  DOS secondary
17  Hidden HPFS/NTF 64  Novell Netware  b7  BSDI fs         fb  VMware VMFS
18  AST SmartSleep  65  Novell Netware  b8  BSDI swap       fc  VMware VMKCORE
1b  Hidden W95 FAT3 70  DiskSecure Mult bb  Boot Wizard hid fd  Linux raid auto
1c  Hidden W95 FAT3 75  PC/IX           bc  Acronis FAT32 L fe  LANstep
1e  Hidden W95 FAT1 80  Old Minix       be  Solaris boot    ff  BBT
Hex code (type L to list all codes): 8e
Changed type of partition 'Linux' to 'Linux LVM'.

Command (m for help): p
Disk /dev/sdb: 20 GiB, 21474836480 bytes, 41943040 sectors
Disk model: VBOX HARDDISK
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0x5721e48c

Device     Boot Start      End  Sectors Size Id Type
/dev/sdb1        2048 41943039 41940992  20G 8e Linux LVM

Command (m for help): w
The partition table has been altered.
Calling ioctl() to re-read partition table.
Syncing disks.
```

### Step 3. Create LVM Physical Volume

    sudo pvcreate /dev/sdb1

### Step 4. Create LVM Volumen Group for iSCSI

    sudo vgcreate vg_iscsi /dev/sdb1

### Step 5. Create LVM Logical Volume associated to LUNs

    sudo lvcreate -L 4G -n lv_iscsi_1 vg_iscsi

    sudo lvcreate -L 4G -n lv_iscsi_2 vg_iscsi

    ...


### Step 6.

List the Physical volume, Volume group, logical volumes to confirm:

    sudo pvs
    sudo vgs
    sudo lvs

## Configuring Target iSCSI

### Step 1. Installing `targetcli`

`targetcli` is a command shell for managing the Linux LIO kernel target

    sudo apt install targetcli-fb

### Step 2. Execute `targetcli`

    sudo targetcli

### Step 3. Create an iSCSI Target and Target Port Group (TPG)

   cd iscsi/
   create iqn.2021-07.com.ricsanfre.picluster:iscsi-server

```
sudo targetcli
Warning: Could not load preferences file /root/.targetcli/prefs.bin.
targetcli shell version 2.1.51
Copyright 2011-2013 by Datera, Inc and others.
For help on commands, type 'help'.

/> cd iscsi
/iscsi> create iqn.2021-07.com.ricsanfre.picluster:iscsi-server
Created target iqn.2021-07.com.ricsanfre.picluster:iscsi-server.
Created TPG 1.
Global pref auto_add_default_portal=true
Created default portal listening on all IPs (0.0.0.0), port 3260.
```

### Step 4. Create a backstore (bock devices associated to LVM Logical Volumes created before).


    cd /backstores/block
    create block0 /dev/vg_iscsi/lv_iscsi_0

```
/> cd /backstores/block
/backstores/block> create block0 /dev/vg_iscsi/lv_iscsi_0
Created block storage object block0 using /dev/vg_iscsi/lv_iscsi_0.
```

### Step 5. Create an Access Control List (ACL) for security and access to the Target.

In the Initiator server check the iqn (iSCSI Qualifier Name) within the file `/etc/iscsi/initiatorname.iscsi`

> NOTE: Assign unique iqn (iSCSI Initiator Qualifier Name) to each cluster node (`node1-4`). See section [Configuring iSCSI Inititator](#configuring-iscsi-initiator)

Create ACL for the iSCSI Initiator. 

```
cd /iscsi/iqn.2003-01.org.linux-iscsi.ubuntucloud.x8664:sn.c8d2bfaa1b03/tpg1/acls
create <IQN_Initiator>
```

Specify userid and password

cd <IQN_Initiator>
set auth userid=<USER>
set auth password=<PASSWORD>


```
sudo targetcli
/> cd iscsi
/iscsi> create iqn.2021-07.com.ricsanfre.vbox:iscsi-server
Created target iqn.2021-07.com.ricsanfre.vbox:iscsi-server.
Created TPG 1.
Global pref auto_add_default_portal=true
Created default portal listening on all IPs (0.0.0.0), port 3260.
/iscsi> cd /backstores/block
/backstores/block> create iscsi-client-vol1 /dev/vg_iscsi/lv_iscsi_1
Created block storage object iscsi-client-vol1 using /dev/vg_iscsi/lv_iscsi_1.
/backstores/block> cd /iscsi/iqn.2021-07.com.ricsanfre.vbox:iscsi-server/tpg1/luns
/iscsi/iqn.20...ver/tpg1/luns> create /backstores/block/iscsi-client-vol1
Created LUN 0.
/iscsi/iqn.20...ver/tpg1/luns> cd ../acls
/iscsi/iqn.20...ver/tpg1/acls> create iqn.2021-07.com.ricsanfre.vbox:iscsi-client
Created Node ACL for iqn.2021-07.com.ricsanfre.vbox:iscsi-client
Created mapped LUN 0.
/iscsi/iqn.20...ver/tpg1/acls> cd iqn.2021-07.com.ricsanfre.vbox:iscsi-client/
/iscsi/iqn.20...:iscsi-client> set auth userid=user1
Parameter userid is now 'user1'.
/iscsi/iqn.20...:iscsi-client> set auth password=s1cret0
Parameter password is now 's1cret0'.
/iscsi/iqn.20...:iscsi-client> exit
Global pref auto_save_on_exit=true
Last 10 configs saved in /etc/rtslib-fb-target/backup/.
Configuration saved to /etc/rtslib-fb-target/saveconfig.json
```

### Step 6. Load configuration on startup

    sudo systemctl enable rtslib-fb-targetctl 

### Step 7. Configure firewall rules

Enable incoming traffic on port TCP 3260.

## Configuring iSCSI Initiator

### Step 1. Ensure package open-iscsi is installed
In order to communicate and connect to iSCSI volume, we need to install open-iscsi package.

    sudo apt install open-iscsi

### Step 2. Configure iSCI Intitiatio iqn 

Edit iqn assigned to the server in the file `/etc/iscsi/initiatorname.conf`.

```
InitiatorName=iqn.2021-07.com.ricsanfre.picluster:<host_name>
```
### Step 3. Configure iSCSI Authentication

Edit file `/etc/iscsi/iscsid.conf`

Unncomment and add the proper values to the following entries:

```
node.session.auth.authmethod = CHAP
node.session.auth.username = user1
node.session.auth.password = s1cret0
```

### Step 4. Restart open-iscsi service

    sudo systemctl restart iscsid open-iscsi

### Step 5. Connect to iSCSI Target

Discover the iSCSI Target.


    sudo iscsiadm -m discovery -t sendtargets -p 192.168.100.100

```
sudo iscsiadm -m discovery -t sendtargets -p 192.168.56.100
192.168.56.100:3260,1 iqn.2021-07.com.ricsanfre.vbox:iscsi-server
```

Login to the iSCSI target

    sudo iscsiadm --mode node --targetname <iqn-target> --portal <iscsi-server-ip> --login

```
sudo iscsiadm --mode node --targetname iqn.2021-07.com.ricsanfre.vbox:iscsi-server --portal 192.168.56.100 --login
Logging in to [iface: default, target: iqn.2021-07.com.ricsanfre.vbox:iscsi-server, portal: 192.168.56.100,3260](multiple)
Login to [iface: default, target: iqn.2021-07.com.ricsanfre.vbox:iscsi-server, portal: 192.168.56.100,3260] successful.
```

Check the connected iSCSI disks with command `fdisk -l`:

```
sudo fdisk -l
....
    
Device      Start     End Sectors  Size Type
/dev/sda1  227328 4612062 4384735  2,1G Linux filesystem
/dev/sda14   2048   10239    8192    4M BIOS boot
/dev/sda15  10240  227327  217088  106M EFI System

Partition table entries are not in disk order.


Disk /dev/sdb: 4 GiB, 4294967296 bytes, 8388608 sectors
Disk model: iscsi-client-vo
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 33550336 bytes

```

### Step 6. Configure automatic login 

    sudo iscsiadm --mode node --op=update -n node.conn[0].startup -v automatic
    sudo iscsiadm --mode node --op=update -n node.startup -v automatic



### Step 7. Format iSCSI disk
New Disk can be partitioned and formatted

- Create a primary partition

```
sudo fdisk /dev/sdb

Welcome to fdisk (util-linux 2.34).
Changes will remain in memory only, until you decide to write them.
Be careful before using the write command.

Device does not contain a recognized partition table.
Created a new DOS disklabel with disk identifier 0x071ca572.

Command (m for help): n
Partition type
   p   primary (0 primary, 0 extended, 4 free)
   e   extended (container for logical partitions)
Select (default p): p
Partition number (1-4, default 1): 1
First sector (65528-8388607, default 65528):
Last sector, +/-sectors or +/-size{K,M,G,T,P} (65528-8388607, default 8388607):

Created a new partition 1 of type 'Linux' and of size 4 GiB.

Command (m for help): w
The partition table has been altered.
Calling ioctl() to re-read partition table.
Syncing disks.

```

Check created partition with `fdisk -l`

```
sudo fdisk -l

....
Disk /dev/sdb: 4 GiB, 4294967296 bytes, 8388608 sectors
Disk model: iscsi-client-vo
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 33550336 bytes
Disklabel type: dos
Disk identifier: 0x071ca572

Device     Boot Start     End Sectors Size Id Type
/dev/sdb1       65528 8388607 8323080   4G 83 Linux
```

Format the partition to ext4 file system

```

pi@server:~$ sudo mkfs.ext4 /dev/sdb1

mke2fs 1.45.5 (07-Jan-2020)
Creating filesystem with 1040385 4k blocks and 260096 inodes
Filesystem UUID: 1256920d-baeb-411b-ac93-f1af1bfb5e06
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376, 294912, 819200, 884736

Allocating group tables: done
Writing inode tables: done
Creating journal (16384 blocks): done
Writing superblocks and filesystem accounting information: done
```

Mount the disk

    sudo mkdir /data
    sudo mount /dev/sdb1 /data


### Step 8. Mount iSCSI disk on startup

Modify `/etc/fstab` to mount iSCSI disk on startup

First find the volume UUID.

    sudo blkid


```
sudo blkid
/dev/sr0: UUID="2021-07-30-14-56-50-42" LABEL="CIDATA" TYPE="iso9660"
/dev/sda1: LABEL="cloudimg-rootfs" UUID="7339cdbb-1045-46fc-99df-ed81a4d0b313" TYPE="ext4" PARTUUID="15d1e14d-e787-4550-8457-dae123d40109"
/dev/sda15: LABEL_FATBOOT="UEFI" LABEL="UEFI" UUID="BD61-C33D" TYPE="vfat" PARTUUID="02bff6fe-fbb6-47bd-af18-645273993fdc"
/dev/loop0: TYPE="squashfs"
/dev/loop1: TYPE="squashfs"
/dev/loop2: TYPE="squashfs"
/dev/sda14: PARTUUID="40a58950-3814-4880-8671-f3386594554c"
/dev/sdb1: UUID="1256920d-baeb-411b-ac93-f1af1bfb5e06" TYPE="ext4" PARTUUID="071ca572-01"
```

Add the following line to `/etc/fstab`
```
/dev/disk/by-uuid/[iSCSI_DISK_UUID] [MOUNT_POINT] ext4 _netdev 0 0
```
    


# Preparing SSD disk for gateway node

`gateway`node will be acting as SAN server. It will boot from USB using a SSD disk

## Step 1. Burn Ubuntu 20.04 server to SSD distk using Balena Etcher

## Step 2. Boot Raspberry PI with Raspberry OS

### Step 3. Connect SSD Disk to USB 3.0 port.

Check the disk

   sudo fdisk -l

```
sudo fdisk -l

Disk /dev/mmcblk0: 29.7 GiB, 31914983424 bytes, 62333952 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0x9c46674d

Device         Boot  Start      End  Sectors  Size Id Type
/dev/mmcblk0p1        8192   532479   524288  256M  c W95 FAT32 (LBA)
/dev/mmcblk0p2      532480 62333951 61801472 29.5G 83 Linux


Disk /dev/sda: 447.1 GiB, 480103981056 bytes, 937703088 sectors
Disk model: Generic
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 4096 bytes
I/O size (minimum/optimal): 4096 bytes / 4096 bytes
Disklabel type: dos
Disk identifier: 0x4ec8ea53

Device     Boot  Start     End Sectors  Size Id Type
/dev/sda1  *      2048  526335  524288  256M  c W95 FAT32 (LBA)
/dev/sda2       526336 6366175 5839840  2.8G 83 Linux
```


## Step 3. Repartition with parted

After flashing the disk the root partion size is less than 3 GB. On first boot this partition is automatically extended to occupy 100% of the available disk space.
Since I want to use the SSD disk not only for the Ubuntu OS, but providing iSCSI LUNS. Before the first boot, I will repartition the SSD disk.

- Extending the root partition to 32 GB Size
- Create a new partition for storing iSCSI LVM LUNS


```
pi@gateway:~ $ sudo parted /dev/sda
GNU Parted 3.2
Using /dev/sda
Welcome to GNU Parted! Type 'help' to view a list of commands.
(parted) print
Model: JMicron Generic (scsi)
Disk /dev/sda: 480GB
Sector size (logical/physical): 512B/4096B
Partition Table: msdos
Disk Flags:

Number  Start   End     Size    Type     File system  Flags
 1      1049kB  269MB   268MB   primary  fat32        boot, lba
 2      269MB   3259MB  2990MB  primary  ext4

(parted) resizepart
Partition number? 2
End?  [3259MB]? 32500
(parted) print
Model: JMicron Generic (scsi)
Disk /dev/sda: 480GB
Sector size (logical/physical): 512B/4096B
Partition Table: msdos
Disk Flags:

Number  Start   End     Size    Type     File system  Flags
 1      1049kB  269MB   268MB   primary  fat32        boot, lba
 2      269MB   32.5GB  32.2GB  primary  ext4

(parted) mkpart
Partition type?  primary/extended? primary
File system type?  [ext2]? ext4
Start? 32501
End?
End? 100%
(parted) print
Model: JMicron Generic (scsi)
Disk /dev/sda: 480GB
Sector size (logical/physical): 512B/4096B
Partition Table: msdos
Disk Flags:

Number  Start   End     Size    Type     File system  Flags
 1      1049kB  269MB   268MB   primary  fat32        boot, lba
 2      269MB   32.5GB  32.2GB  primary  ext4
 3      32.5GB  480GB   448GB   primary  ext4         lba

(parted) set 3 lvm on
(parted) print
Model: JMicron Generic (scsi)
Disk /dev/sda: 480GB
Sector size (logical/physical): 512B/4096B
Partition Table: msdos
Disk Flags:

Number  Start   End     Size    Type     File system  Flags
 1      1049kB  269MB   268MB   primary  fat32        boot, lba
 2      269MB   32.5GB  32.2GB  primary  ext4
 3      32.5GB  480GB   448GB   primary  ext4         lvm, lba

(parted) quit
```

## Step 5. Checking USB-SATA Adapter

Checking that the USB SATA adapter suppors UASP.

```
lsusb -t

/:  Bus 02.Port 1: Dev 1, Class=root_hub, Driver=xhci_hcd/4p, 5000M
    |__ Port 1: Dev 2, If 0, Class=Mass Storage, Driver=uas, 5000M
/:  Bus 01.Port 1: Dev 1, Class=root_hub, Driver=xhci_hcd/1p, 480M
    |__ Port 1: Dev 2, If 0, Class=Hub, Driver=hub/4p, 480M
        |__ Port 3: Dev 3, If 0, Class=Human Interface Device, Driver=usbhid, 1.5M
        |__ Port 3: Dev 3, If 1, Class=Human Interface Device, Driver=usbhid, 1.5M
        |__ Port 4: Dev 4, If 0, Class=Human Interface Device, Driver=usbhid, 1.5M

```
> Driver=uas indicates that the adpater supports UASP


Check USB-SATA adapter ID

```
sudo lsusb
Bus 002 Device 002: ID 174c:55aa ASMedia Technology Inc. Name: ASM1051E SATA 6Gb/s bridge, ASM1053E SATA 6Gb/s bridge, ASM1153 SATA 3Gb/s bridge, ASM1153E SATA 6Gb/s bridge
Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
Bus 001 Device 004: ID 0000:3825
Bus 001 Device 003: ID 145f:02c9 Trust
Bus 001 Device 002: ID 2109:3431 VIA Labs, Inc. Hub
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
```

> NOTE: In this case ASMedia TEchnology ASM1051E has ID 152d:0578


## Step 6. Modify USB partitions following instrucions described [here](./installing_ubuntu.md)