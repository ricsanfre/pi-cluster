---
title: Cluster SAN (optional)
permalink: /docs/san/
description: How to configure iSCSI storage for Raspberry PI cluster nodes deploying a SAN network using a Raspberry Pi node as storage server, iSCSI Target.
last_modified_at: "25-02-2022"
---

The idea is to configure one of the Raspberry PIs as a SAN for the lab cluster, connecting some SSD Disk to it (through USB 3.0 ports) and providing LUNs to all the cluster nodes through iSCSI.

A storage on a SAN network is called iSCSI Target, a Client which connects to iSCSI Target is called iSCSI Initiator.

In my home lab, `gateway` will be the iSCSI Target and `node1-node5` will be the iSCSI Initiators.

```
+----------------------+         |             +----------------------+
| [   iSCSI Target   ] |10.0.0.1 | 10.0.0.11-14| [ iSCSI Initiator  ] |
|        gateway       +---------+-------------+        node1-5       |
|                      |                       |                      |
+----------------------+                       +----------------------+

```

LIO, [LinuxIO](http://linux-iscsi.org/wiki/Main_Page), has been the Linux SCSI target since kernel version 2.6.38.It support sharing different types of storage fabrics and backstorage devices, including block devices (including LVM logical volumes and physical devices). [`targetcli`](http://linux-iscsi.org/wiki/Targetcli) is the single-node LinuxIO management CLI developed by Datera, that is part of most linux distributions. 

A SAN (Storage Area Network) is a collection of logical drives, called LUNS, that iSCSI target server exposed to iSCSI initiator over TCP/IP network.
A logical unit number, or **LUN**, is a number used to identify a logical unit, which is a device addressed by the SCSI protocol or by Storage Area Network protocols that encapsulate SCSI, such as Fibre Channel or iSCSI.

In real environment, as the picture below shows, LUNs are defined using LVM. That way they can be expandable as per space requirements.

![LUNs-on-LVM](/assets/img/Creating_LUNs_using_LVM.png "Creating LUNS using LVM")

{{site.data.alerts.important}}
iSCSI Qualifier Names (iqn)

Unique identifier are asigned to iSCSI Initiators and iSCSI targets.

Format of the iqn is the following: `iqn.yyyy-mm.reverse_domain_name:any`

In my case I will use hostname to make iqn unique

```
iqn.2021-07.com.ricsanfre.picluster:<hostname>
```
{{site.data.alerts.end}}

## Preparing Storage Device

Follow these steps for preparing the storage device for hosting the LUNs: add new hard drive/partition existing one and configure LVM.

- Step 1. Allocate storage block device for LUN storage

  Connect a new Disk (SSD/Flash Drive) through USB 3.0 port.
  As alternative a partition on existing SSD/Flash Drive, same disk with boot and root partitions, can be configured. 

- Step 2. (optional) Repartition used disk

  If we are reusing the storage device containig the boot and root partitions (OS installation), re-partition of the storage is needed for freeing space for iSCSI LUNs. 

  If a new disk is attached to the device this step is not needed:

  Re-partition with `fdisk` or `parted` for freeing space for iSCSI LUNs.

  Example, using `parted` for repartition /dev/sda. Partition ext4 (root filesystem) is resized and with the free space a new `ext4` partition is created (/dev/sda2) with `lvm` flag

    ```shell
    ubuntu@test:~$ sudo parted /dev/sda
    GNU Parted 3.3
    Using /dev/sda
    Welcome to GNU Parted! Type 'help' to view a list of commands.
    (parted) print
    Model: ATA VBOX HARDDISK (scsi)
    Disk /dev/sda: 8590MB
    Sector size (logical/physical): 512B/512B
    Partition Table: gpt
    Disk Flags:

    Number  Start   End     Size    File system  Name  Flags
    14      1049kB  5243kB  4194kB                     bios_grub
    15      5243kB  116MB   111MB   fat32              boot, esp
    1      116MB   8590MB  8474MB  ext4

    (parted) resizepart
    Partition number? 1
    Warning: Partition /dev/sda1 is being used. Are you sure you want to continue?
    Yes/No? Yes
    End?  [8590MB]? 4494MB
    Warning: Shrinking a partition can cause data loss, are you sure you want to continue?
    Yes/No? Yes
    (parted) print
    Model: ATA VBOX HARDDISK (scsi)
    Disk /dev/sda: 8590MB
    Sector size (logical/physical): 512B/512B
    Partition Table: gpt
    Disk Flags:

    Number  Start   End     Size    File system  Name  Flags
    14      1049kB  5243kB  4194kB                     bios_grub
    15      5243kB  116MB   111MB   fat32              boot, esp
    1      116MB   4494MB  4378MB  ext4

    (parted) mkpart
    Partition name?  []? 2
    File system type?  [ext2]? ext4
    Start? 4494
    End? 100%
    (parted) print
    Model: ATA VBOX HARDDISK (scsi)
    Disk /dev/sda: 8590MB
    Sector size (logical/physical): 512B/512B
    Partition Table: gpt
    Disk Flags:

    Number  Start   End     Size    File system  Name  Flags
    14      1049kB  5243kB  4194kB                     bios_grub
    15      5243kB  116MB   111MB   fat32              boot, esp
    1      116MB   4494MB  4378MB  ext4
    2      4494MB  8589MB  4095MB  ext4         2

    (parted) set 2 lvm on
    (parted) print
    Model: ATA VBOX HARDDISK (scsi)
    Disk /dev/sda: 8590MB
    Sector size (logical/physical): 512B/512B
    Partition Table: gpt
    Disk Flags:

    Number  Start   End     Size    File system  Name  Flags
    14      1049kB  5243kB  4194kB                     bios_grub
    15      5243kB  116MB   111MB   fat32              boot, esp
    1      116MB   4494MB  4378MB  ext4
    2      4494MB  8589MB  4095MB  ext4         2     lvm

    (parted) quit
    ```

- Step 3. Create LVM Physical Volume

  In case of new device added (`/dev/sdb`). If a partition is used instead (`/dev/sda2`) replace the device in the commands below.

  Create physical volume with command `sudo pvcreate <storage_device>`

  ``` shell   
  sudo pvcreate /dev/sdb
  ```

- Step 4. Create LVM Volumen Group for iSCSI

  Create volume group with command `sudo vgcreate <vg_name> <pv_name>`

  ```shell
  sudo vgcreate vg_iscsi /dev/sdb
  ```

- Step 5. Create LVM Logical Volume associated to LUNs

  A Logical Volume need to be created per LUN, specifying the size of each of one with command `sudo lvcreate -L <size> -n <lv_name> <vg_name>`
  
  ```shell
  sudo lvcreate -L 4G -n lv_iscsi_1 vg_iscsi
  sudo lvcreate -L 4G -n lv_iscsi_2 vg_iscsi
  ...
  ```

- Step 6. Check Logical volumes

  List the Physical volume, Volume group, logical volumes to confirm:

    - List phisical volume: `sudo pvs` or `sudo pvdisplay`
    - List volume group: `sudo vgs` or `sudo vgdisplay`
    - List logical volumes:  `sudo lvs` or `sudo lvdisplay`

## Configuring Target iSCSI

- Step 1. Installing `targetcli`

  `targetcli` is a command shell for managing the Linux LIO kernel target

  ```shell
  sudo apt install targetcli-fb
  ```
- Step 2. Execute `targetcli`
  
  ```shell
  sudo targetcli
  ```

- Step 3. Disable auto addind of mapped LUNs

  By default all LUNs configured at target level are assigned automatically to any iSCSI initiator which is created (Target ACL). To avoid this and enabling manual allocation of LUNs a targetcli global preference must be setting

  ```shell
  set global auto_add_mapped_luns=false
  ```

- Step 4. Create an iSCSI Target and Target Port Group (TPG)

  ```shell
  cd iscsi/
  create iqn.2021-07.com.ricsanfre.picluster:iscsi-server
  ```

    ```shell
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

- Step 5. Create a backstore (bock devices associated to LVM Logical Volumes created before).

  ```shell   
  cd /backstores/block
  create <block_id> <block_dev_path>
  ```

    ```shell
    /> cd /backstores/block
    /backstores/block> create block0 /dev/vg_iscsi/lv_iscsi_0
    Created block storage object block0 using /dev/vg_iscsi/lv_iscsi_0.
    ```

- Step 6. Create LUNs
  
  ```shell
  cd /iscsi/<target_iqn>/tpg1/luns
  create storage_object=<block_storage> lun=<lun_id>
  ```

    ```shell
    /> cd /iscsi/iqn.2021-07.com.ricsanfre.vbox:iscsi-server/tpg1/luns
    /iscsi/iqn.20...ver/tpg1/luns> create /backstores/block/iscsi-client-vol1
    Created LUN 0.
```

- Step 7. Create an Access Control List (ACL) for security and access to the Target.

  In the Initiator server check the iqn (iSCSI Qualifier Name) within the file `/etc/iscsi/initiatorname.iscsi`

  {{site.data.alerts.important}}
  Assign unique iqn (iSCSI Initiator Qualifier Name) to each cluster node (`node1-5`). See section [Configuring iSCSI Inititator](#configuring-iscsi-initiator)
  {{site.data.alerts.end}}

  Create ACL for the iSCSI Initiator. 
  ```shell
  cd /iscsi/<target_iqn>/tpg1/acls
  create <initiator_iqn>
  ```

  Specify userid and password for initiator and target (mutual authentication)
  
  ```shell
  cd /iscsi/<target_iqn>/tpg1/acls/<initiator_iqn>
  set auth userid=<initiator_iqn>
  set auth password=<initiator_password>
  set auth mutual_userid=<target_iqn>
  set auth mutual_passwird=<target_password>
  ```

    ```shell
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

- Step 8. Assing mapped LUNs to initiators

  ```shell
  cd /iscsi/<target_iqn>/tpg1/acls/<initiator_iqn>
  create mapped_lun=<mapped_lunid> tpg_lun_or_backstore=<lunid> write_protect=<0/1>
  ```
  Where: `write_protect=1`, means read-only lun and `write_protect=0` means read-write lun

- Step 9. Save config

  Upon exiting targetcli configuration is saved automatically.
  If configuration has been executed through command line without entering targetcli shell (i.e: sudo targetcli command), changes need to be saved

  ```shell
  sudo targetcli saveconfig
  ```

- Step 10. Load configuration on startup

  ```shell
  sudo systemctl enable rtslib-fb-targetctl 
  ```

- Step 11. Configure firewall rules

  Enable incoming traffic on port TCP 3260.

## Configuring iSCSI Initiator

- Step 1. Ensure package open-iscsi is installed
  In order to communicate and connect to iSCSI volume, we need to install open-iscsi package.

  ```shell
  sudo apt install open-iscsi
  ```

- Step 2. Configure iSCI Intitiator iqn 

  Edit iqn assigned to the server in the file `/etc/iscsi/initiatorname.conf`.

  ```
  InitiatorName=iqn.2021-07.com.ricsanfre.picluster:<host_name>
  ```

- Step 3. Configure iSCSI Authentication

  Edit file `/etc/iscsi/iscsid.conf`

  Unncomment and add the proper values to the following entries:

  ```
  node.session.auth.authmethod = CHAP
  node.session.auth.username = user1
  node.session.auth.password = s1cret0
  ```

{{site.data.alerts.note}}
This configuration assumes that all iSCSI targets to which the host is connecting have the same credentials. It this is not the case, credentials can configured per target and this step must be avoided. See configuration per target below in step 5
{{site.data.alerts.end}}

- Step 4. Restart open-iscsi service and enable it in boot time

  ```shell
  sudo systemctl restart iscsid
  sudo systemctl enable iscsid
  ```

- Step 5. Discovery iSCSI Target

  Discover the iSCSI Targets exposed by the portal.

  ```shell
  sudo iscsiadm -m discovery -t sendtargets -p 192.168.100.100
  ```
    ```
    sudo iscsiadm -m discovery -t sendtargets -p 192.168.56.100
    192.168.56.100:3260,1 iqn.2021-07.com.ricsanfre.vbox:iscsi-server
    ```

  When targets are discovered node session configuration parameters are stored locally using the defaults values within the configuration file `iscsi.conf` are used (for example: authentication credentials )

  Target information can be showed using the command:

  ```shell
  sudo iscsiadm -m node -o show
  ```

  The corresponding information is localy stored in files: `/etc/iscsi/nodes/<target_name>/<portal_ip>,<port>,1/default`

  And it can be modified before logging in (actual connection of the iSCSI target) using the following command:

  ```shell
  sudo iscsiadm --mode node --targetname <target> --op=update --name <parmeters_name> --value <parameter_value>
  ```

  For example authentication credentials can be specified per target:

    ```shell
    sudo iscsiadm --mode node --targetname iqn.2021-07.com.ricsanfre.vbox:iscsi-server --op=update --name node.session.auth.authmethod --value CHAP

    sudo iscsiadm --mode node --targetname iqn.2021-07.com.ricsanfre.vbox:iscsi-server --op=update --name node.session.auth.username --value user1

    sudo iscsiadm --mode node --targetname iqn.2021-07.com.ricsanfre.vbox:iscsi-server --op=update --name node.session.auth.pass --value s1cret0
    ```

- Step 6. Connect to the iSCSI target.

  Login to the iSCSI target

  ```shell
  sudo iscsiadm --mode node --targetname <iqn-target> --portal <iscsi-server-ip> --login
  ```

    ```shell
    sudo iscsiadm --mode node --targetname iqn.2021-07.com.ricsanfre.vbox:iscsi-server --portal 192.168.56.100 --login
    Logging in to [iface: default, target: iqn.2021-07.com.ricsanfre.vbox:iscsi-server, portal: 192.168.56.100,3260](multiple)
    Login to [iface: default, target: iqn.2021-07.com.ricsanfre.vbox:iscsi-server, portal: 192.168.56.100,3260] successful.
    ```

  Check the discovered iSCSI disks

  ```shell
  sudo iscsiadm -m session -P 3
  ```

    ```
    sudo iscsiadm -m session -P 3
    iSCSI Transport Class version 2.0-870
    version 2.0-874
    Target: iqn.2021-07.com.ricsanfre:iscsi-target (non-flash)
            Current Portal: 192.168.0.11:3260,1
            Persistent Portal: 192.168.0.11:3260,1
                    **********
                    Interface:
                    **********
                    Iface Name: default
                    Iface Transport: tcp
                    Iface Initiatorname: iqn.2021-07.com.ricsanfre:iscsi-initiator
                    Iface IPaddress: 192.168.0.12
                    Iface HWaddress: <empty>
                    Iface Netdev: <empty>
                    SID: 1
                    iSCSI Connection State: LOGGED IN
                    iSCSI Session State: LOGGED_IN
                    Internal iscsid Session State: NO CHANGE
                    *********
                    Timeouts:
                    *********
                    Recovery Timeout: 120
                    Target Reset Timeout: 30
                    LUN Reset Timeout: 30
                    Abort Timeout: 15
                    *****
                    CHAP:
                    *****
                    username: iqn.2021-07.com.ricsanfre:iscsi-initiator
                    password: ********
                    username_in: iqn.2021-07.com.ricsanfre:iscsi-target
                    password_in: ********
                    ************************
                    Negotiated iSCSI params:
                    ************************
                    HeaderDigest: None
                    DataDigest: None
                    MaxRecvDataSegmentLength: 262144
                    MaxXmitDataSegmentLength: 262144
                    FirstBurstLength: 65536
                    MaxBurstLength: 262144
                    ImmediateData: Yes
                    InitialR2T: Yes
                    MaxOutstandingR2T: 1
                    ************************
                    Attached SCSI devices:
                    ************************
                    Host Number: 2  State: running
                    scsi2 Channel 00 Id 0 Lun: 0
                            Attached scsi disk sdb          State: running
                    scsi2 Channel 00 Id 0 Lun: 1
                            Attached scsi disk sdc          State: running

    ```

  At the end of the ouput the iSCSI attached disks can be found (sdb and sdc)


  Command `lsblk` can be used to list SCSI devices

  ```
  sudo lsblk -S
  ```

    ```
    lsblk -S
    NAME HCTL       TYPE VENDOR   MODEL      REV TRAN
    sda  2:0:0:0    disk ATA      VBOX_HARDDISK 1.0  sata
    sda  2:0:0:0    disk LIO-ORG  lun_node1 4.0  iscsi
    sdb  2:0:0:1    disk LIO-ORG  lun_node3 4.0  iscsi
    ```

  {{site.data.alerts.note}}

  TRANS column let us separate iSCSI disk (trans=iscsi) from local SCSI (TRANS=sata)

  MODEL column shows LUN name configured in the target
  {{site.data.alerts.end}}

  Check the connected iSCSI disks with command `fdisk -l`:

    ```shell
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

- Step 7. Configure automatic login

  ```shell
  sudo iscsiadm --mode node --op=update -n node.conn[0].startup -v automatic
  sudo iscsiadm --mode node --op=update -n node.startup -v automatic
  ```

- Step 8. Format and mount iSCSI disk

  The new iSCSI disk can be partitioned with `fdisk`/`parted` and formated with `mkfs.ext4` and mount as any other disk

  Also it can be used with LVM as a physical volume for createing Logical Volumes

  - Create a physical volume

    ```shell
    sudo pvcreate /dev/sdb
    ```

  - Create a volume group

    ```shell
    sudo vgcreate vgcreate vg_iscsi /dev/sdb
    ```

  - Create Logical Volume
    
    ```shell
    sudo lvcreate vg_iscsi -l 100%FREE -n lv_iscsi
    ```

  - Format Logical Volume
    
    ```shell
    sudo mkfs.ext4 /dev/vg_iscsi/lv_iscsi
    ```

  - Mount the disk

    ```shell
    sudo mkdir /data
    sudo mount /dev/vg_iscsi/lv_iscsi /data
    ```

- Step 9. Mount iSCSI disk on startup

  Modify `/etc/fstab` to mount iSCSI disk on startup

  First find the volume UUID.

  ```shell
  sudo blkid
  ```

    ```
    sudo blkid

    ...
    /dev/sdb: UUID="xj6V9b-8uo6-RACn-MTqB-7siH-nvjT-Aw9B0V" TYPE="LVM2_member"
    /dev/mapper/vg_iscsi-lv_iscsi: UUID="247a2c91-4af8-4403-ac5b-a99116dac96c" TYPE="ext4"
    ```

  Add the following line to `/etc/fstab`
  ```
  /dev/disk/by-uuid/[iSCSI_DISK_UUID] [MOUNT_POINT] ext4 _netdev 0 0
  ```

  ```
  #iSCSI data
  UUID=247a2c91-4af8-4403-ac5b-a99116dac96c /data            ext4    _netdev    0  0
  ```

  {{site.data.alerts.important}}
  Do not forget to specify `_netdev` option (it indicates to mount filesystem after network boot is completed)
  {{site.data.alerts.end}}
