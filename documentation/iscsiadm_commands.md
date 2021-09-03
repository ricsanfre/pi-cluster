# iSCSI useful commands

Discover available targets from a discovery portal:

    iscsiadm -m discovery -t sendtargets -p ipaddress

Login to all targets:

    iscsiadm -m node -l

Log into a specific target:

    iscsiadm -m node -T targetname -p ipaddress -l

Log out of all targets:

    iscsiadm -m node -u

Log out of a specific target:

    iscsiadm -m node -T targetname -p ipaddress -u
 

Display information about a target:

    iscsiadm -m node -T targetname -p ipaddress
 

Display statistics of a target:

    iscsiadm -m node -s -T targetname -p ipaddress
 

Display a list of all current sessions logged in:

    iscsiadm -m session
 

View iSCSI database regarding discovery:

    iscsiadm -m discovery -o show
 

View iSCSI database regarding targets to login to:

    iscsiadm -m node -o show
 

View iSCSI database regarding sessions logged in to:

    iscsiadm -m session -o show


Find the newly created device name, using the iscsiadm command.

    iscsiadm -m session -P3


When you expand the volume or disk, you might need to rescan. So the below command will help:

    iscsiadm -m node -p ipaddress --rescan
 