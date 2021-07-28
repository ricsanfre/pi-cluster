# Configuring Raspberry PI as SAN for the lab cluster

The idea is to configure one of the Raspberry PIs as a SAN, connecting some SSD Disk to it (through USB 3.0 ports) and providing LUNs to all the cluster nodes through iSCSI.

A storage on a network is called iSCSI Target, a Client which connects to iSCSI Target is called iSCSI Initiator. In my home lab, `gateway` will be the iSCSI Target and `node1-node4` will be the iSCSI Initiators.

+----------------------+         |             +----------------------+
| [   iSCSI Target   ] |10.0.0.1 | 10.0.0.11-14| [ iSCSI Initiator  ] |
|        gateway       +---------+-------------+        node1-4       |
|                      |                       |                      |
+----------------------+                       +----------------------+


LIO, [LinuxIO](http://linux-iscsi.org/wiki/Main_Page), has been the Linux SCSI target since kernel version 2.6.38.
It support sharing different types of storage fabrics and backstorage devices, including block devices (including LVM logical volumes and physical devices).

**LUN is a Logical Unit Number**, which shared from the iSCSI Storage Server. The Physical drive of iSCSI target server shares its drive to initiator over TCP/IP network. A Collection of drives called LUNs to form a large storage as SAN (Storage Area Network). In real environment LUNs are defined in LVM, if so it can be expandable as per space requirements.

![LUNs-on-LVM](images/Creating_LUNs_using_LVM.png "Creating LUNS using LVM")

LVM will be configured for

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
   create

```
sudo targetcli
Warning: Could not load preferences file /root/.targetcli/prefs.bin.
targetcli shell version 2.1.51
Copyright 2011-2013 by Datera, Inc and others.
For help on commands, type 'help'.

/> cd iscsi
/iscsi> create
Created target iqn.2003-01.org.linux-iscsi.ubuntucloud.x8664:sn.c8d2bfaa1b03.
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

Create ACL for the iSCSI Initiator. In the Initiator server check the iqn (iSCSI Qualifier Name) within the file `/etc/iscsi/initiatorname.iscsi`


cd /iscsi/iqn.2003-01.org.linux-iscsi.ubuntucloud.x8664:sn.c8d2bfaa1b03/tpg1/acls
create <IQN_Initiator>




