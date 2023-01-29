#!/usr/bin/env bash

# GPG_EMAIL and GPG_NAME expected as environment variables

if [[ -n "$(gpg --list-secret-keys ${GPG_EMAIL})" ]] 
then 
  echo "GPG key already exits"
else
  echo "Generating GPG key"
  gpg --batch --full-generate-key <<EOF
Key-Type: 1
Key-Length: 4096
Subkey-Type: 1
Subkey-Length: 4096
Expire-Date: 0
Name-Real: ${GPG_NAME}
Name-Email: ${GPG_EMAIL}
EOF

fi
