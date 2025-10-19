---
title: External Services Node
permalink: /docs/external/
description: How to configure a Raspberry Pi to host external services needed in HomeLab, like DNS authoritative server, PXE server, SAN, HA Proxy.
last_modified_at: "15-08-2025"
---

One of the Raspeberry Pi (4GB), `node1`, is used to run external services like authoritative DNS, PXE Server, Vault or external Kuberentes API Load Balancer (HA Proxy). 

In case of deployment using centralized SAN storage architectural option, `node1` is providing SAN services also.

This Raspberry Pi (gateway), is connected to my home network using its WIFI interface (wlan0) and to the LAN Switch using the eth interface (eth0).

In order to ease the automation with Ansible, OS installed on **gateway** is the same as the one installed in the nodes of the cluster: Ubuntu 24.04 64 bits.


## Storage Configuration

`node1` node is based on a Raspberry Pi 4B $GB booting from a USB Flash Disk or SSD Disk depending on storage architectural option selected.

- Dedicated disks storage architecture: A Samsung USB 3.1 32 GB Fit Plus Flash Disk will be used connected to one of the USB 3.0 ports of the Raspberry Pi.
- Centralized SAN architecture: Kingston A400 480GB SSD Disk and a USB3.0 to SATA adapter will be used connected to `node1`. SSD disk for hosting OS and iSCSI LUNs.


## Network Configuration

Only ethernet interface (eth0) will be used connected to the lan switch. Wifi interface won't be used. Ethernet interface will be configured with static IP address.

## Unbuntu OS instalation

Ubuntu can be installed on Raspbery PI using a preconfigurad cloud image that need to be copied to SDCard or USB Flashdisk/SSD.

Raspberry Pis will be configured to boot Ubuntu OS from USB conected disk (Flash Disk or SSD disk). The initial Ubuntu 24.04 LTS configuration on a Raspberry Pi 4 will be automated using cloud-init.

In order to enable boot from USB, Raspberry PI firmware might need to be updated. Follow the producedure indicated in ["Raspberry PI - Firmware Update"](/docs/firmware/).

The installation procedure followed is the described in ["Ubuntu OS Installation"](/docs/ubuntu/rpi/) using cloud-init configuration files (`user-data` and `network-config`) for `node1`.

`user-data` depends on the storage architectural option selected:

| Dedicated Disks | Centralized SAN    |
|--------------------| ------------- |
|  [user-data]({{ site.git_edit_address }}/metal/rpi/cloud-init/node1/user-data) | [user-data]({{ site.git_edit_address }}/metal/rpi/cloud-init/node1/user-data-centralizedSAN) |
{: .table .border-dark }

`network-config` is the same in both architectures:


| Network configuration |
|---------------------- |
| [network-config]({{ site.git_edit_address }}/metal/rpi/cloud-init/node1/network-config) |
{: .table .border-dark }

### cloud-init partitioning configuration (Centralized SAN)

By default, during first boot, cloud image partitions grow to fill the whole capacity of the SDCard/USB Flash Disk or SSD disk. So root partition (/) will grow to fill the full capacity of the disk.

{{ site.data.alerts.note }}

As a reference of how cloud images partitions grow in boot time check this blog [entry](https://elastisys.com/how-do-virtual-images-grow/).

{{ site.data.alerts.end }}


In case of centralized SAN, node1's SSD Disk will be partitioned in boot time reserving 30 GB for root filesystem (OS installation) and the rest will be used for creating logical volumes (LVM), SAN LUNs to be mounted using iSCSI by the other nodes.

cloud-init configuration `user-data` includes commands to be executed once in boot time, executing a command that changes partition table and creates a new partition before the automatic growth of root partitions to fill the entire disk happens.

```yml
bootcmd:
  # Create second LVM partition. Leaving 30GB for root partition
  # sgdisk /dev/sda -e .g -n=0:30G:0 -t 0:8e00
  # First convert MBR partition to GPT (-g option)
  # Second moves the GPT backup block to the end of the disk where it belongs (-e option)
  # Then creates a new partition starting 10GiB into the disk filling the rest of the disk (-n=0:10G:0 option)
  # And labels it as an LVM partition (-t option)
  - [cloud-init-per, once, addpartition, sgdisk, /dev/sda, "-g", "-e", "-n=0:30G:0", -t, "0:8e00"]

runcmd:
  # reload partition table
  - "sudo partprobe /dev/sda"
```

Command executed in boot time is

```shell
sgdisk /dev/sda -e .g -n=0:30G:0 -t 0:8e00
```

This command:
  - First convert MBR partition to GPT (-g option)
  - Second moves the GPT backup block to the end of the disk  (-e option)
  - then creates a new partition starting 30GiB into the disk filling the rest of the disk (-n=0:10G:0 option)
  - And labels it as an LVM partition (-t option)

LVM logical volumes creation using the new partition,`/dev/sda3`, (LUNs) have been automated with Ansible developing the ansible role: **ricsanfre.storage** for managing LVM.

Specific ansible variables to be used by this role are stored in [`ansible/vars/centralized_san/centralized_san_target.yml`]({{ site.git_edit_address }}/ansible/vars/centralized_san/centralized_san_target.yml)


### cloud-init: network configuration


Ubuntu's netplan yaml configuration file used, part of cloud-init boot `/boot/network-config` is the following:

```yml
version: 2
ethernets:
  eth0:
    dhcp4: false
    dhcp6: false
    addresses:
      - 10.0.0.11/24
    routes:
      - to: default
        via: 10.0.0.1
    nameservers:
      addresses:
        - 10.0.0.1
      search:
        - homelab.ricsanfre.com
```

It assigns static IP address 10.0.0.11 to eth0 port using as gateway and DNS server 10.0.0.1 (`gateway`).
Also `homelab.ricsanfre.com` domain is added to dns search

## Ubuntu OS Initital Configuration

After booting from the USB3.0 external storage for the first time, the Raspberry Pi will have SSH connectivity and it will be ready to be automatically configured from the ansible control node `pimaster`.

Initial configuration tasks includes: removal of snap package, and Raspberry PI specific configurations tasks such as: intallation of fake hardware clock, installation of some utility packages scripts and change default GPU Memory plit configuration. See instructions in ["Ubuntu OS initial configurations"](/docs/os-basic/).

For automating all this initial configuration tasks, ansible role **basic_setup** has been developed.

### NTP Service Configuration

Cluster nodes will be configured as NTP clients using NTP server running in `gateway`
See ["NTP Configuration instructions"](/docs/gateway/#ntp-server-configuration).

NTP configuration in cluster nodes has been automated using ansible role **ricsanfre.ntp**

## iSCSI configuration. Centralized SAN

`node1` has to be configured as iSCSI Target to export LUNs mounted by `node1-node6`

iSCSI configuration in `node1` has been automated developing a couple of ansible roles: **ricsanfre.storage** for managing LVM and **ricsanfre.iscsi_target** for configuring a iSCSI target.

Specific `node1` ansible variables to be used by these roles are stored in [`ansible/vars/centralized_san/centralized_san_target.yml`]({{ site.git_edit_address }}/ansible/vars/centralized_san/centralized_san_target.yml)

Further details about iSCSI configurations and step-by-step manual instructions are defined in ["Cluster SAN installation"](/docs/san/).

`node1` exposes a dedicated LUN of 100 GB for each of the clusters nodes.

## DNS Installation

As described in ["PiCluster - DNS Architecture"](/docs/dns/), DNS authoritative server, based on bind9, is installed in `node1`

For automating configuration tasks, ansible role [**ricsanfre.bind9**](https://galaxy.ansible.com/ricsanfre/bind9) has been developed.

## PXE Server

As described in ["PiCluster - PXE Server"](/docs/pxe-server/), PXE server, to automate OS installation of x86 nodes, is installed in `node1`


## Vault Installation

As described in ["PiCluster - Secrets Management (Vault)"](/docs/vault/), Hashicorp Vault is installed in `node1`

For automating configuration tasks, ansible role [**ricsanfre.vault**](https://galaxy.ansible.com/ricsanfre/vault) has been developed.

## Observability

### Metrics

[Node Exporter](https://github.com/prometheus/node_exporter) is a Prometheus exporter for hardware and OS metrics exposed by UNIX kernels, written in Go with pluggable metric collectors.

Node Exporter is deployed on external node, so it exposes a Prometheus compliant metrics endpoint that can be used by Prometheus Server to collect metrics.

#### Node Exporter installation

The Prometheus Node Exporter is a single static binary that can be installed via tarball that can be downloaded from [Prometheus download website](https://prometheus.io/download/#node_exporter)

-   Step 1: Add user for node_exporter
    ```
    sudo useradd --no-create-home --shell /sbin/nologin node_exporter
    ```

-   Step 2: Download tar file and untar it

    ```shell
    cd tmp
    wget https://github.com/prometheus/node_exporter/releases/download/v<VERSION>/node_exporter-<VERSION>.linux-<ARCH>.tar.gz
    tar -xvf node_exporter-<VERSION>.linux-<ARCH>.tar.gz
    ```

    Where `<VERSION>` is the version of node exporter to be installed and `<ARCH>` is the architecture of the system (i.e.: `amd64` for x86_64 systems).
    ```

-   Step 3: Copy node_exporter binary to `/usr/local/bin`

    ```shell
    sudo cp /tmp/node_exporter-<VERSION>.linux-<ARCH>/node_exporter /usr/local/bin
    ```

-   Step 4: Create service file for systemd `/etc/systemd/system/node_exporter.service`

    ```
    [Unit]
    Description=Node Exporter
    Wants=network-online.target
    After=network-online.target

    [Service]
    User=node_exporter
    Group=node_exporter
    Type=simple
    ExecStart=/usr/local/bin/node_exporter \
        '--collector.systemd' \
        '--collector.textfile' \
        '--collector.textfile.directory=/var/lib/node_exporter' \
        '--web.listen-address=0.0.0.0:9100' \
        '--web.telemetry-path=/metrics'

    [Install]
    WantedBy=multi-user.target
    ```

-   Step 4: Reload systemd daemon

    ```shell
    sudo systemctl daemon-reload
    ```

-   Step 5: Start and enable node exporter service

    ```shell
    sudo systemctl enable node_exporter
    sudo systemctl start node_exporter
    ```

-   Step 6: Check that node_exporter has started

    ```shell
    sudo journalctl -f --unit node_exporter
    ```

Node Exporter installation and configuration can be automated with Ansible. Ansible role [**prometheus.node_exporter**](https://github.com/prometheus-community/ansible/tree/main/roles/node_exporter), which is part of Ansible Collection for Prometheus maintained by Prometehus Community, can be used to automate its deployment and configuration.

#### Integration with Kube-Prom-Stack

In case Prometheus server is deployed in Kuberentes cluster using kube-prometheus-stack (i.e Prometheus Operator), Prometheus Operator CRD `ScrapeConfig` resource can be used to automatically add configuration for scrapping metrics from node exporter.


-   Create Prometheus Operator ScrapeConfig resources

    ```yaml
    apiVersion: monitoring.coreos.com/v1alpha1
    kind: ScrapeConfig
    metadata:
      name: node-exporter
    spec:
      staticConfigs:
        - targets:
            - ${NODE_NAME}:9100
      metricsPath: /metrics
      relabelings:
        - action: replace
          targetLabel: job
          replacement: node-exporter
    ```

    Where `${NODE_NAME}`, should be replaced by DNS or IP address of the external node (i.e.: `node1.homelab.ricsanfre.com`).


#### Grafana Dashboard

Node Exporter dashboard can be donwloaded from [grafana.com](https://grafana.com): [dashboard id: 1860](https://grafana.com/grafana/dashboards/1860).

Dashboard can be automatically added using Grafana's dashboard providers configuration. See further details in ["PiCluster - Observability Visualization (Grafana): Automating installation of community dasbhoards](/docs/grafana/#automating-installation-of-grafana-community-dashboards)

Add following configuration to Grafana's helm chart values file:

```yaml
# Configure default Dashboard Provider
# https://grafana.com/docs/grafana/latest/administration/provisioning/#dashboards
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: infrastructure
        orgId: 1
        folder: "Infrastructure"
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/infrastructure-folder

# Add dashboard
# Dashboards
dashboards:
  infrastructure:
    node-exporter-full:
      # renovate: depName="Node Exporter Full"
      gnetId: 1860
      revision: 41
      datasource:
        - { name: DS_PROMETHEUS, value: Prometheus }
```


### Logs

#### Fluent-bit Agent installation

Fluentbit can be installed in external nodes and configured so logs can be forwarded to Fluentd aggregator service running within the cluster.

There are official installation packages for Ubuntu. Installation instructions can be found in [Fluentbit documentation: "Ubuntu installation"](https://docs.fluentbit.io/manual/installation/linux/ubuntu).

Fluentbit installation and configuration can be automated with Ansible. For example using Ansible role: [**ricsanfre.fluentbit**](https://galaxy.ansible.com/ricsanfre/fluentbit). This role install fluentbit and configure it.

#### Fluent bit configuration

Configuration is quite similar to the one defined for the fluentbit (See ["Collecting logs with FluentBit"](/docs/fluentbit/)), removing kubernetes logs collection and filtering and maintaining only OS-level logs collection.

`/etc/fluent-bit/fluent-bit.conf`
```
[SERVICE]
    Daemon Off
    Flush 1
    Log_Level info
    Parsers_File parsers.conf
    Parsers_File custom_parsers.conf
    HTTP_Server On
    HTTP_Listen 0.0.0.0
    HTTP_Port 2020
    Health_Check On

[INPUT]
    Name tail
    Tag host.*
    DB /run/fluentbit-state.db
    Path /var/log/auth.log,/var/log/syslog
    Parser syslog-rfc3164-nopri

[OUTPUT]
    Name forward
    Match *
    Host fluentd.${CLUSTER_DOMAIN}
    Port 24224
    Self_Hostname ${HOSTNAME}
    Shared_Key ${SHARED_KEY}
    tls true
    tls.verify false
```

{{site.data.alerts.note}}

Substitute variables (`${var}`) in the above config file before applying it.
-   Replace `${CLUSTER_DOMAIN}` by the domain used in the cluster. For example: `homelab.ricsanfre.com`
-   Replace `${HOSTNAME}` by the hostname of the server where fluent-bit is installed. For example: `node1`
-   Replace `${SHARED_KEY}` by the fluentd shared key configured for the `forward` protocol`

{{site.data.alerts.end}}


`/etc/fluent-bit/custom_parsers.conf`
```
[PARSER]
    Name syslog-rfc3164-nopri
    Format regex
    Regex /^(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\/\.\-]*)(?:\[(?<pid>[0-9]+)\])?(?:[^\:]*\:)? *(?<message>.*)$/
    Time_Key time
    Time_Format %b %d %H:%M:%S
    Time_Keep False
```


With this configuration, Fluentbit will monitoring log entries in `/var/log/auth.log` and `/var/log/syslog` files, parsing them using a custom parser `syslog-rfc3165-nopri` (syslog default parser removing priority field), and forward them to fluentd aggregator service running in K3S cluster. Fluentd destination is configured using DNS name associated to fluentd aggregator service external IP.

