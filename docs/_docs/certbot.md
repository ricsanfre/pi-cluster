---
title: TLS Certificates (Certbot)
permalink: /docs/certbot/
description: How to use cert-bot to issue Let's Encrypt TLS certificates
last_modified_at: "31-05-2025"
---

[Cerbot](https://certbot.eff.org/) is an opensource ACME client that can be used to generate trusted TLS certificates automating the interaction with [Let's Encrypt](https://letsencrypt.org/) a free, automated, and open certificate authority (CA).

Certbot can be used to automate the issue and renewal of TLS certificates for Cluster external services (openWRT, Minio, Vault) not running within Kubernetnes cluster.

## How does it work?
Certbot uses ACME Protocol to get certificates from Let's Encrypt.

It supports both type of ACME Challenges (HTTP-01 and DNS-01)


### DNS-01 Challenge

A Certbot plugin is needed to automate DNS-01 Challenge for different DNS providers
For example,  CloudFlare provider requires `certbot-dns-cloudflare`

{{site.data.alerts.note}}

IONOS DNS provider is not one of the providers, supported out-of-the-box by `certbot`

`certbot-dns-ionos` is an implementation of such Cerbot plugin. Project repository: [cerbot-dns-ionos project](https://github.com/helgeerbe/certbot-dns-ionos).

{{site.data.alerts.end}}



## Installation

Cerbot can be installed in a python virtualenv.

Execute all the following commands from `$HOME` directory.

-   Step 1. Create Virtual Env for Letscrypt

    ```shell
    python3 -m venv letsencrypt
    ```

-   Step 2. Activate Virtual Environment

    ```shell
    source letsencrypt/bin/activate
    ```

-   Step 3. Upgrade `setuptools` and `pip` packages

    ```shell
    pip3 install --upgrade pip setuptools
    ```

-   Step 4. Install `certbot` and any plugin required (i.e. certbot-ionos-plugin

    ```shell
    pip3 install certbot certbot-dns-ionos certbot-dns-cloudflare
    ```

## Using DNS Challenge

### IONOS as DNS Provider

A Certbot plugin, [cerbot-dns-ionos](https://github.com/helgeerbe/certbot-dns-ionos), is needed to automate DNS challenge process. Plugin uses [IONOS developer API](https://developer.hosting.ionos.es/), allowing the remote configuration of the DNS using a RESTFUL API.

{{site.data.alerts.note}}

To use IONOS developer API, first API key must be created.

Follow [IONOS developer API: Get Started instructions](https://developer.hosting.ionos.es/docs/getstarted) to obtain API key.

API key is composed of two parts:  Public Prefix (public key) and Secret (private key)

{{site.data.alerts.end}}

#### Configure Certbot

To configure IONOS as DNS provider

-  Step 1: Install [cerbot-ionos-plugin](https://github.com/helgeerbe/certbot-dns-ionos)
   ```shell
   pip3 install certbot-dns-ionos
   ```
-   Step 2. Obtain IONOS Developer API
-   Step 3. Create certbot working directories

   ```shell
   mkdir -p letsencrypt/config
   mkdir -p letsencrypt/logs
   mkdir -p letsencrypt/.secrets
   chmod 700 letsencrypt/.secrets
   ```

-   Step 4. Create ionos credentials file `letsencrypt/.secrets/ionos-credentials.ini`

    ```
    dns_ionos_prefix = myapikeyprefix
    dns_ionos_secret = verysecureapikeysecret
    dns_ionos_endpoint = https://api.hosting.ionos.com
    ```
  
    In this file, IONOS API key prefix and secret need to be provided

-   Step 5. Change permission of `ionos-credentials.ini` file

    ```shell
    chmod 600 letsencrypt/.secrets/ionos-credentials.ini
    ```

#### Certificate issue/renewal

Execute the following command:

  ```shell
  letsencrypt/bin/certbot certonly \
  --config-dir letsencrypt/config \
  --work-dir letsencrypt \
  --logs-dir letsencrypt/logs \
  --authenticator dns-ionos \
  --dns-ionos-credentials letsencrypt/.secrets/ionos-credentials.ini \
  --dns-ionos-propagation-seconds 900 \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --agree-tos \
  --non-interactive \
  --rsa-key-size 4096 \
  -m <your-email> \
  -d <host_dns>
  ```
  
  Signed certificate will be stored in `letsencrypt/config`.

#### List certificates managed by Certbot

  Certificates managed by certbot can be listed using the commad:

  ```shell
  letsencrypt/bin/certbot certificates \
  --config-dir letsencrypt/config \
  --work-dir letsencrypt \
  --logs-dir letsencrypt/logs \
  ```

  Certificate and key path are showed. Also expiration date is showed.

#### Certificate renewal

  To automatic renew the certificates the following command can be executed periodically in a cron

  ```shell
  letsencrypt/bin/certbot/certbot renew
  ```
