#!/usr/bin/env bash

# GPG_EMAIL expected as environment variable
pwgen -n 71 -C | head -n1 | gpg --armor --recipient ${GPG_EMAIL} -e -o ~/.vault/vault_passphrase.gpg
