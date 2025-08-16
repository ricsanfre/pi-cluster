---
title: Cluster Gateway (OpenWrt)
permalink: /docs/openwrt/
description: How to configure a router/firewall for our homelab Cluster, running OpenWRT OS and providing connectivity and basic networking services (DNS, DHCP, NTP). 
last_modified_at: "16-08-2025"
---

To isolate my kubernetes cluster from my home network, a Router/Firewall running OpenWRT will be used, **gateway** node.

**OpenWrt** (from *open wireless router*) is a highly extensible GNU/Linux distribution for embedded devices to route traffic. 
OpenWrt can run on various types of devices, including CPE routers, residential gateways, smartphones and SBC (like Raspeberry Pis). It is also possible to run OpenWrt on personal computers.

For my homelab, the router need to be able to support WiFi connectivity as uplink (Wan interface), so Raspberry Pi 4B can be used to run OpenWRT-based router/firewall. Raspberry PI will be connected to my home network using its WIFI interface (`wlan0`) and to the LAN Switch using the eth interface (`eth0`).

As an alternative to Raspberry PI, a wifi pocket-sized travel router running OpenWRT as OS can be used. For example, [Slate Plus (GL-A1300)](https://www.gl-inet.com/products/gl-a1300/) from GL-Inet can be used for this purpose.


## OpenWRT installation in Raspberry Pi

This is the process to flash OpenWRT into SD-Card that can be used to boot Raspberry Pi


- Step 1. Download the appropriate bcm27xx image for your Raspberry Pi and desired OpenWrt release from [Firmware Selector](https://firmware-selector.openwrt.org/).

  ![openwrt-firmware-selector-rpi4](/assets/img/openwrt-firmware-selector-rpi4.png)

  {{site.data.alerts.note}}
  Supported versions per Raspberry PI model can be found in [https://openwrt.org/toh/raspberry_pi_foundation/raspberry_pi](https://openwrt.org/toh/raspberry_pi_foundation/raspberry_pi)
  {{site.data.alerts.end}}

  {{site.data.alerts.important}}
  Download `factory` image that allows to install OpenWRT for the first time: 
  For example, this is the image name to install OpenWRT 23.05.5: `openwrt-23.05.5-bcm27xx-bcm2711-rpi-4-ext4-factory.img.gz`
  {{site.data.alerts.end}}

- Step 2. Flash the image to a micro SD card using a disk imager, such as the open source one from the Raspberry Pi team

  Use Raspberry PI Imager to flash the OpenWrt image to an SD card
  Unzip downloaded image
  ```shell
  gunzip openwrt-23.05.5-bcm27xx-bcm2711-rpi-4-ext4-factory.img.gz
  ```
  Open RpI Imager
  - Select Raspberry Pi Model

    ![rpi-imager-1](/assets/img/rpi-imager-openwrt-1.png)

  - Select "Use Custom" when specifying "Operating System", and the `.img` file previously unzipped.

    ![rpi-imager-2](/assets/img/rpi-imager-openwrt-2.png)

  - Select SD Card when choosing "Storage"
  - Click on "Write" to start the SD-card flashing

- Step 3. Once SD Card flash is complete, insert the SD card into your Raspberry Pi and power up. OpenWrt will boot.

- Step 4. Connect laptop directly to Raspberry PI ethernet port or via LAN switch
  OpenWRT will assign the laptop a IP via DHCP

- Step 5: Open Luci interface at [http://192.168.1.1](http://192.168.1.1)
  
  Login as `root` user, no password is needed the first time.

  ![openwrt-rpi4-luci-first-login](/assets/img/openwrt-rpi4-luci-first-login.png)

- Step 6. Configure a password for `root` user.


{{site.data.alerts.note}} SSH Acces

SSH access is also enabled by default using `root` user.

```shell
ssh root@192.168.1.1
```
Password is the same configured through LuCI UI.

{{site.data.alerts.end}}

## OpenWRT installation in GL-iNet hardware

Gl Inet A-1300 support latest release of OpenWrt (23.05) but latest GL Inet firmware (4.17.5) comes with old version of OpenWrt (21.02) which is EOL release.
Latest firmware version available can be downloaded from here: [https://dl.gl-inet.com/router/a1300/](https://dl.gl-inet.com/router/a1300/)

OpenWRT firmware cannot be upgraded without losing GL Inet customized version and functionalities provided on top of OpenWrt.

### Reinstall Router with Updated version of OpenWRT

The procedure is the following

1. Download firmware from [https://openwrt.org/toh/gl.inet/gl-a1300](https://openwrt.org/toh/gl.inet/gl-a1300)
	 {{site.data.alerts.note}}
 	 Download Uboot firmware image
	 In following image: **Firmware OpenWrt Install URL**
	 ![openwrt-gl-a1300-uboot-firmware](/assets/img/openwrt-gl-a1300-uboot-firmware.png)
   {{site.data.alerts.end}}
1. Remove the power of router.
2. Connect your computer to the **Ethernet port (either LAN or WAN)** of the router. All other ports **MUST** remain **unconnected**. 
3. Press and hold the Reset button firmly, and then power up the router.
  **GL-A1300(Slate Plus)**  the LED flashes slowly 5 times, then stays on for a short while, then flashes quickly all the time. Release reset button after flashing sequence changes.
5. Manually set the IP address of your computer to **192.168.1.2**.
6. Use browser to visit **http://192.168.1.1**, this is the Uboot Web UI
7. Click **Choose file** button to find the firmware file. Then click **Update firmware** button and select firmware image downloaded in 1.
8. Wait for around 3 minutes. Don't power off your device when updating. The router is ready when both power and Wi-Fi LED are on or you can find its SSID on your device.
9. Revert the IP setting you did in step 4 and connect your device to the LAN or Wi-Fi of the router. You will be able to access the router via **192.168.8.1** again.
10. OpenWrt admin console is opened.


{{site.data.alerts.tip}} **Reinstalling GL-Inet firmware**

In case the router has been bricked because doing some DIY projects, like installing vanilla OpenWrt or flashing a wrong firmware and the access to the router is lost firmware can be re-can re-installed using Uboot failsafe.

See futher details in [https://docs.gl-inet.com/router/en/4/faq/debrick/](https://docs.gl-inet.com/router/en/4/faq/debrick/)

{{site.data.alerts.end}}

## OpenWRT configuration

### Configuring hostname

- Go to "System" -> "System"
- Select "General Settings" tab
- Update hostname and apply changes

![openwrt-hostname](/assets/img/openwrt-hostname.png)

### Securing access

#### Securing SSH acess

##### Configure SSH keys

- Go to System-> Administrator
- Select "SSH Keys" tab
- Copy and paste SSH public key

![openwrt-ssh-access-key](/assets/img/openwrt-ssh-access-key.png)

Try ssh connection using SSH private key

```shell
ssh root@10.0.0.1 -i <ssh_private_key_file>
```

##### Disabling SSH using password

- Go to System -> Administrator
- Select "SSH Access" tab
  - Uncheck "Password Authentication" and "Allows root login with password"

  ![openwrt-ssh-disable-password-access](/assets/img/openwrt-ssh-disable-password-access.png)

#### Securing LuCi console access

LuCi HTTP access can be secured applying the following configuration[^1].

##### Enable HTTPs

- Go to "System" -> "Administration"
- Select "HTTP(S) Access" tab
- Click on "Redirect to HTTPS"

![openwrt-https-access.png](/assets/img/openwrt-https-access.png)


##### Install a valid TLS certificate

- Generate a TLS certificate. Self-signed TLS or signed by LetsEncrypt.

  {{site.data.alerts.tip}}
  Certbot tool can be used for this purpose
  {{site.data.alerts.end}}


- Copy private key and public key into `/etc`

  ```shell
  rsync /tmp/gateway.homelab.ricsanfre.key gateway:/etc/uhttpd.key
  rsync /tmp/gateway.homelab.ricsanfre.crt gateway:/etc/uhttpd.crt
  ```

- Restart `uhttp` process

  ```shell
  /etc/init.d/uhttpd restart
  ```

See further details in ["OpenWrt documentation: How to get rid of LuCI HTTPS certificate warnings"](https://openwrt.org/docs/guide-user/luci/getting_rid_of_luci_https_certificate_warnings)


### Configuring LAN

By default Router LAN IP is configured to use 192.168.1.0/24, network and 192.168.1.1 as router IP address in LAN.

Default LAN subnet and router IP addresseed must be changed to use homelab LAN subnetwork.

- Go to System -> Interfaces
- Edit  **lan (lan-br)** interface
- In General settings, this interface is configured with a static address 192.168.1.1
- Assign an IP address in a **different** subnet (e.g. 10.0.0.1). Click Save.
- Click **Save and Apply**.

![openwrt-lan-interface-config](/assets/img/openwrt-lan-interface-config.png)

- Reconnect to Luci web UI using new IP 10.0.0.1

### Configuring wireless WAN

Use one of the wifi interfaces to connect to home wifi[^2]

- Go to Network -> Wireless

  The list of available wifi interfaces is displayed. The number and type of wifi-interfaces depends on the hardware used to run OpenWrt.

  **GL.iNet GL-A1300(SlatePlus) Wifi Interfaces**
  
  ![openwrt-wireless-interfaces](/assets/img/openwrt-wireless-interfaces.png)

  GL.iNet GL-A1300 (Slate Plus) has two wifi interfaces:
  1. `radio0`: 802.11 a/b/g/n, 400Mbps (2.4GHz) 
  2. `radio1`: 802.11 ac, 867Mbps (5GHz) 
  
  For the wan up-link we can select 5GHz interface to connect to my home network. Other wifi interface can be used to access vi WiFi to the homelab.

  **Raspberry Pi (4B) Wifi Interface**

  Raspberry Pi 4B model only has one wifi interface:

  1. `radio0`: 802.11 a/b/g/n, 400Mbps (2.4GHz) 

  ![openwrt-wireless-interfaces-rpi4](/assets/img/openwrt-wireless-interfaces-rpi4.png)


- Select radio interface and click on "Scan"
  The available list of Wifi networks is displayed:

  ![openwrt-wireless-join-network](/assets/img/openwrt-wireless-join-network.png)

- Choose the Wi-Fi network you want to connect to from the page and click “Join Network”.

- Wifi connection configuration window is displayed
  
  ![openwrt-wireless-joining-network-config](/assets/img/openwrt-wireless-joining-network-config.png)

  - Recommend to tick the 'Replace wireless configuration' to delete the wireless access point (Master) for the chosen radio.
  - Enter the Wi-Fi password, leave the “name of new network” as “wwan” and select **wan** firewall zone.
  - Click Save. 
  
- Client Wi-Fi settings page is opened.
  - Leave default values
  - Click in Save and apply
  
  ![openwrt-wireless-client-connection](/assets/img/openwrt-wireless-client-connection.png)


#### Configure static IP for wireless WAN

After connecting OpenWRT to a WIFI network as a client, a new `wwan (phy1-sta0)` interface is created in System->Interfaces

{{site.data.alerts.note}}
By default the new interface is configured to use DHCP to obtain automatically a IP address
{{site.data.alerts.end}}


![openwrt-wwan-interface](/assets/img/openwrt-wwan-interface.png)

- Click on Edit to set a static IP address
- Select static IP address, and click on Switch Protocol confirmation button
- Select wwan (phy1-sta0) Device
- Set a static IP address that is available in your home network (i.e. 192.168.1.21)
- Click on Save and Save and apply

#### Configuring Default route

A default route need to be configured so Router can access to internet

- Go to Network->Routing
- Click on Add.
- Specify default route (0.0.0.0/0) through home router ip gateway (192.168.1.1 in my case) assigned to `wwan` interface

![openwrt-default-route](/assets/img/openwrt-default-route.png)


### Firewall

OpenWrt uses the `firewallX` application netfilter/nftables rule builder application. It runs in user-space to parse a configuration file into a set of `nftables` rules, sending each to the kernel netfilter modules.

{{site.data.alerts.note}}
OpenWRT firewall application is based on nftables,  same firewall solution used before when `gateway` node was running in Ubuntu OS (["PiCluster: Cluster Gateway (Ubuntu)"](/docs/gateway/)).
 - OpenWrt release 22.01 uses firewall3 (`fw3` command)
 - OpenWrt latest releases uses firewall4 (`fw4` command)
{{site.data.alerts.end}}

#### Default configuration
##### Zones 
A `zone` groups one or more *interfaces* and serves as *source* or *destination* for *forwardings*, *rules* and *redirects*
.
Two zones are configured by default:

- `lan`: all LAN interfaces belong to this zone
  - All traffic from LAN to WAN is ACCEPTED by default
- `wan`: all WAN interfaces belong to this zone
  - All traffic from WAN to LAN is REJECTED by default


#### Configure firewall rules
Go to "Network" -> "Traffic Rules"

##### Enabling HTTP/HTTPS traffic WAN to LAN

Enabling HTTP/HTTPS traffic (TCP 80/443) to cluster nodes from WAN interface

![openwrt-firewall-http-from-wan](/assets/img/openwrt-firewall-http-from-wan.png)

##### Enabling SSH traffic WAN to LAN

Enabling SSH traffic (tcp port:22) to cluster nodes from WAN interface

![openwrt-firewall-ssh-traffic-from-wan](/assets/img/openwrt-firewall-ssh-traffic-from-wan.png)

##### Enabling HTTPs traffic to Kube API

Enabling HTTPS traffic to Kube API (TCP 6443) running in 10.0.0.11 (HA Proxy load balancer)

![openwrt-firewall-kube-api-from-wan](/assets/img/openwrt-firewall-kube-api-from-wan.png)

##### Enabling SSH connection to OpenWRT device from WAN

This is needed to enable SSH connections to OpenWRT router from WAN interfaces

![openwrt-firewall-allow-ssh-device](/assets/img/openwrt-firewall-allow-ssh-device.png)

##### Enabling HTTPS connection to OpenWRT device from WAN

This is needed to enable HTTPS connections to OpenWRT router from WAN interface

![openwrt-allow-https-traffic-to-device](/assets/img/openwrt-allow-https-traffic-to-device.png)

##### Enabling DNS connection to OpenWRT device from WAN

Enable DNS traffic to OpenWRT router from WAN interface. Use Homelab DNS from my home lab network

![openwrt-allow-dns-traffic-to-device](/assets/img/openwrt-allow-dns-traffic-to-device.png)

##### Summary of firewall rules added

![openwrt-firewall-added-rules](/assets/img/openwrt-firewall-added-rules.png)

### DNS/DHCP service

{{site.data.alerts.note}}
OpenWRT DNS/DHCP service is based on [[Dnsmasq]], same DNS/DHCP solution used before when `gateway` node was running in Ubuntu OS (["PiCluster: Cluster Gateway (Ubuntu)"](/docs/gateway/))
{{site.data.alerts.end}}

Configuration is stored in `/etc/config/dhcp`/

Further details in [OpenWrt-DNS/DHCP configuration documentation](https://openwrt.org/docs/guide-user/base-system/dhcp)

#### DNS server configuration

##### Configure Local domain
- Go to Network -> DHCP and DNS
- In Tab "General" 
    - Set  "Local Domain" to internal DNS subdomain (`homelab.ricsanfre.com`) 
     - Set "Resolve this locally" to empty

  Local DNS domain will be added to DHCP DNS search domain

![openwrt-dns-local-domain](/assets/img/openwrt-dns-local-domain.png) 

##### Configure DNS Forwarders

- Go to Network -> DHCP and DNS
- In Tab "Forwarders" add all upstream DNS servers
  - Forward DNS queries for domain `homelab.ricsanfre.com` to internal DNS server (Bind9)
  - Use CloudFlare (`1.1.1.1`) and Google DNS (`8.8.8.8`) servers

   ![openwrt-dns-forwarders](/assets/img/openwrt-dns-forwarders.png)

- In Tab "Filter" configure Rebind protection

  Add `homelab.ricsanfre.com` to "Domain Whitelist"

  ![openwrt-dns-rebind-whitelist](/assets/img/openwrt-dns-rebind-whitelist.png)

  {{site.data.alerts.important}}

  OpenWRT, by default, configures DNS Rebind protection. This is designed to protect against this type of attack by blocking DNS resolution for domains that point to private IP addresses. 
  All request to `homelab.ricsanfre.com`, since resolve private IP address, are rejected unless "rebind protection" is disabled or `homelab.ricsanfre.com` domain is added to the whitelist.
  
  {{site.data.alerts.end}}

#### DHCP interfaces configuration

Enable DHCPv4 and disable DHCPv6 in `lan` interface

- Go to System -> Interfaces and edit `lan (lan-br)` interface
  - Go to "DHCP Server" Tab and "General Settings" subtab
    - "Ignore Interface" option has to be unchecked. This is default option
    - Set "Start", "Limit" and "Lease time" options
      Start option set to 100 and limit set to 150 => pool IP  (10.0.0.100-10.0.0.249)

    ![openwrt-lan-dhcp](/assets/img/openwrt-lan-dhcp.png)

  - Go to "DHCP Server" tab and "IPv6 Settings" 
    - Select "RA Service" and "DHCPv6 Service" as disabled
    
    ![openwrt-lan-disable-dhcpv6](/assets/img/openwrt-lan-disable-dhcpv6.png)

#### Configure DHCP Boot/PXE options

- Go to Network -> DHCP and DNS
- In Tab "PXE/TFPT" configure
  - Configure `dnsmasq` PXE boot options
  - Do not enable TFTP server

{{site.data.alerts.important}}
Multiarchitecture boot options cannot be configured using LuCI
dnsmasq `dhcp-match` options cannot be configured
```shell
# UEFI boot
dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-boot=tag:efi-x86_64,bootx64.efi
```
UCI cli can be used instead[^3]
{{site.data.alerts.end}}

- Connect to OpenWrt through SSH

- Execute the following UCI commands

  ```shell
  uci set dhcp.@match[-1].networkid='bios'
  uci set dhcp.@match[-1].match='60,PXEClient:Arch:00000'
  uci add dhcp match
  uci set dhcp.@match[-1].networkid='efi64'
  uci set dhcp.@match[-1].match='60,PXEClient:Arch:00007'
  uci add dhcp boot
  uci set dhcp.@boot[-1].filename='tag:bios,bios/pxelinux.0'
  uci set dhcp.@boot[-1].serveraddress=10.0.0.11
  uci set dhcp.@boot[-1].servername=node1
  uci add dhcp boot
  uci set dhcp.@boot[-1].filename='tag:efi64,efi64/bootx64.efi'
  uci set dhcp.@boot[-1].serveraddress=10.0.0.11
  uci set dhcp.@boot[-1].servername=node1
  uci commit dhcp
  service dnsmasq reload
  ```

{{site.data.alerts.tip}} **dnsmasq configuration**

After applying the changes the dnsmasq configuration that is really configured can be checked in directory `/tmp/etc/dnsmasq.conf.x`

{{site.data.alerts.end}}

### NTP Configuration

NTP configuration can be updated in "System" -> "System" Menu -> "Time Synchronization" tab

![openwrt-ntp](/assets/img/openwrt-ntp.png)

By default only NTP client is configured.

#### Enable NTP Server

To enable NTP server click on "Provide NTP server". NTP server can be enabled only in a specific interface (i.e `lan` interface)

![openwrt-ntp-server](/assets/img/openwrt-ntp-server.png)

#### How OpenWrt keeps track of time

Most of OpenWrt hardware, including Raspberry PI or GL-A1300 does not have a RTC (Real Time clock), that means that it uses NTP to keep system time updated.

Even when NTP is used to synchronize the time and date, when NTP boots, it takes as current-time the time of the first-installation.
As time goes after any reboot, NTP synchronization takes longer and longer because NTP adjust the time in small steps and the starting date to be synchronized is more distant in the past.

To remediate this, OpenWRT when booting updates system time to the most recently changed file in `/etc` directory.
Script implementing this behavior is (`/etc/init.d/sysfixtime`).
The problem is that if there is no configuration changes, the last update time won't change between reboots.
To mitigate this problem, a script to update a dummy file in (`/etc`) can be scheduled.

Go to "System" -> "Scheduled Tasks" 

Add the following crontab task and apply save:

```shell
# Keeping time track file so sysfixtime can find a recent timestamp when rebooting 
*/5 * * * *  touch /etc/keepingtime
```

Scheduled tasks can be listed:

```shell
crontab -l
```

## OpenWRT Operation

### Software Management

Additional software packages can be installed in OpenWRT using OPKG packet manager[^4].

{{site.data.alerts.note}} 
Wireless/wired wan interface need to be configured with Internet Access (Default route and DNS need to be configured in the interface)
{{site.data.alerts.end}}

OpenWRT packages can be updated or new packages can be installed through LuCi:

- Go to System->Software
- Click on "Update List" to obtain list of packages

Packages can also be updated installed through command line:

All packages can be automatically uploaded with the following command

```shell
opkg list-upgradable | cut -f 1 -d ' ' | xargs opkg upgrade
```

### Firmware Upgrade

Check latest version available for your hardware

Example:
- For Raspberry Pi: https://openwrt.org/toh/raspberry_pi_foundation/raspberry_pi
- For GL-Inet A1300 model: https://openwrt.org/toh/gl.inet/gl-a1300

- Step 1. Download the appropriate Image for your Model and desired OpenWrt release from [Firmware Selector](https://firmware-selector.openwrt.org/).

  For example: For Rapsberry PI

  ![openwrt-firmware-selector-rpi4](/assets/img/openwrt-firmware-selector-rpi4.png)

  For GL. iNet A-1300:

  ![openwrt-firmware-selector-gl-inet-a1300](/assets/img/openwrt-firmware-selector-gl-inet-a1300.png)

- Step 2. Download "system Upgrade" image to update a router that already runs OpenWrt. The image can be used with the LuCI web interface or the terminal

- Step 3: Connect to LuCI Interface

- Step 4:  Go to System->Backup/Flash Firmware

  ![openwrt-firmware-upgrade](/assets/img/openwrt-firmware-upgrade.png)

- Step 5: In Section "Flash new firmware image" Click on "Flash Image" and upload the new image.

### Backup and Restore

- Configuration files can be backup up through console

  Go to "System" -> "Backup/Flash Firmware"
  
- To download backup files in tar file, Go to "Backup"  section "Download backup" and click on "Generate Archive"

- To restore backup from archive file, Go to "Restore" section "Restore backup" and click "Upload archive..."

![openwrt-backup-restore](/assets/img/openwrt-backup-restore.png)

### OpenWRT configuration files

OpenWrt's central configuration is split into several files located in the `/etc/config/` directory[^5]. Each file relates roughly to the part of the system it configures. 
Configuration files can be edited:
- Using a text editor
- Using CLI `uci`
- Using various programming APIs (shell, Lua and C)
- Using LuCi web interface.

Upon changing a UCI configuration file, whether through a text editor or the command line, the services or executables that are affected must be (re)started (or, in some cases, simply reloaded) by an [init.d call](https://openwrt.org/docs/techref/initscripts "docs:techref:initscripts")

## OpenWRT Observability

### Metrics

#### Prometheus Integration

OpenWRT metrics can be exported deploying Prometheus node exporter packages

-   Step 1: Connect via SSH

    ```shell
    ssh root@192.168.1.1
    ```

-   Step 2: Update packages

    ```shell
    opkg update
    ```

-  Step 3: Install prometheus node exporter packages

    ```shell
    opkg install prometheus-node-exporter-lua \
    prometheus-node-exporter-lua-nat_traffic \
    prometheus-node-exporter-lua-netstat \
    prometheus-node-exporter-lua-openwrt \
    prometheus-node-exporter-lua-wifi \
    prometheus-node-exporter-lua-wifi_stations
    ```

-   Step 4: Check metrics are exposed

    By default, the node exporter we installed will export data to localhost at port 9100 to /metrics.
    To test that metrics are exposed execute the following command
    ```shell
    curl localhost:9100/metrics
    ```
    {{site.data.alerts.note}}

    curl command might be not installed
    Install curl command with
    ```shell
    opkg install curl
    ```
    {{site.data.alerts.end}}

-   Step 4: Make metrics endpoint available through LAN interface

    Edit `/etc/config/prometheus-node-exporter-lua` file.

    ```
    config prometheus-node-exporter-lua 'main'
      option listen_interface 'lan'
      option listen_port '9100'
      option listen_ipv6 '0'
      #option cert '/etc/uhttpd.crt'
      #option key '/etc/uhttpd.key'
    ```
-   Step 5: Restart prometheus-node-exporter-lua service
    ```shell
    /etc/init.d/prometheus-node-exporter-lua restart
    ```

-   Step 6: Configure Prometheus to scrape openWRT node-exporter endpoint

    In Prometheus you need to add a new job scrape config (at the end of the file) `/etc/prometheus/prometheus.yml`

    ```
    - job_name: "OpenWRT"
      static_configs:
        - targets: ["${ROUTER}:9100"]
    ```
    Replacing `${ROUTER}` by IP address/FQDN of the openWRT router.

##### Integration with Kube-Prom-Stack

In case Prometheus server is deployed in Kuberentes cluster using kube-prometheus-stack (i.e Prometheus Operator), Prometheus Operator CRD `ScrapeConfig` resource can be used to automatically add configuration for scrapping metrics from node exporter.


-   Create Prometheus Operator ScrapeConfig resources

    ```yaml
    apiVersion: monitoring.coreos.com/v1alpha1
    kind: ScrapeConfig
    metadata:
      name: openwrt-node-exporter
    spec:
      staticConfigs:
        - targets:
            - gateway.${CLUSTER_DOMAIN}:9100
      metricsPath: /metrics
      relabelings:
        - action: replace
          targetLabel: job
          replacement: openwrt-exporter
    ```

    Where `${CLUSTER_DOMAIN}` has to be replaced by the domain name used in the cluster. For example: `homelab.ricsanfre.com`. (i.e.: target = `gateway.homelab.ricsanfre.com`).

#### Grafana Dashboard

OpenWRTr dashboard can be donwloaded from [grafana.com](https://grafana.com): [dashboard id: 18153](https://grafana.com/grafana/dashboards/18153).

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
    openWRT:
      # https://grafana.com/grafana/dashboards/18153-asus-openwrt-router/
      # renovate: depName="OpenWRT Exporter Dashboard"
      gnetId: 18153
      revision: 4
      datasource:
        - { name: DS_PROMETHEUS, value: Prometheus }
```

### Logs

OpenWRT can be configure to forward syslogs to external Syslog server

- Go to "System" -> "System"
- Select "Logging" tab
- Update external syslog server and port and apply changes

![openwrt-syslog-config](/assets/img/openwrt-syslog-config.png)

Integration with syslog server can be tested generating a syslog message with the `logger` utility

```shell
logger "Testing syslog"
```

Fluentd service running in kubernetes cluster exposes a syslog endpoint to collect OpenWRT syslogs.

---

[^1]: [OpenWrt - Accessing LuCI web interface securely](https://openwrt.org/docs/guide-user/luci/luci.secure)
[^2]: [OpenWrt - Connect Client Wifi](https://openwrt.org/docs/guide-user/network/wifi/connect_client_wifi)
[^3]: [OpenWrt - DHCP Configuration - Multi Architecture TFTP boot](https://openwrt.org/docs/guide-user/base-system/dhcp_configuration#multi-arch_tftp_boot)
[^4]: [OpenWrt - Additional Packages](https://openwrt.org/docs/guide-user/additional-software/opkg)
[^5]: [OpenWrt UCI System](https://openwrt.org/docs/guide-user/base-system/uci)