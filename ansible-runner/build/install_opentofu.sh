#!/bin/bash

set -euo pipefail

# OpenTofu installer script
# This script downloads and runs the official OpenTofu installer

readonly INSTALLER_URL="https://get.opentofu.org/install-opentofu.sh"
readonly INSTALLER_SCRIPT="install-opentofu.sh"
readonly INSTALL_METHOD="deb"

# Download the installer script
echo "Downloading OpenTofu installer from ${INSTALLER_URL}..."
curl --proto '=https' --tlsv1.2 -fsSL "${INSTALLER_URL}" -o "${INSTALLER_SCRIPT}"

# Give it execution permissions
chmod +x "${INSTALLER_SCRIPT}"

echo "Downloaded installer script: ${INSTALLER_SCRIPT}"
echo "Please inspect the script before proceeding if desired"

# Run the installer
echo "Running OpenTofu installer with method: ${INSTALL_METHOD}..."
"./${INSTALLER_SCRIPT}" --install-method "${INSTALL_METHOD}"

# Clean up the installer
echo "Cleaning up installer script..."
rm -f "${INSTALLER_SCRIPT}"

echo "OpenTofu installation completed successfully"