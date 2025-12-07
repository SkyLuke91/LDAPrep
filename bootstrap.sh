#!/bin/bash

# Bootstrap script for LDAP Installation
# This script ensures git is installed, pulls the repo (simulated), and runs the installer.

set -e

# Colors
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}[*] Bootstrapping LDAP Installation...${NC}"

# Check for root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Update apt and install git if missing
echo -e "${GREEN}[*] Updating package lists...${NC}"
apt-get update -qq

if ! command -v git &> /dev/null; then
    echo -e "${GREEN}[*] Installing git...${NC}"
    apt-get install -y git
fi

# In a real scenario, this would clone the repo. 
# For this workspace, we assume the files are present or strictly downloaded.
# REPO_URL="https://github.com/yourusername/ldap-installer.git"
# INSTALL_DIR="/opt/ldap-installer"

# if [ -d "$INSTALL_DIR" ]; then
#     echo -e "${GREEN}[*] Updating existing repository...${NC}"
#     cd "$INSTALL_DIR"
#     git pull
# else
#     echo -e "${GREEN}[*] Cloning repository...${NC}"
#     git clone "$REPO_URL" "$INSTALL_DIR"
#     cd "$INSTALL_DIR"
# fi

# For now, we assume we are running relative to the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

chmod +x "$SCRIPT_DIR/install_ldap.sh"

echo -e "${GREEN}[*] Launching Installation Wizard...${NC}"
exec "$SCRIPT_DIR/install_ldap.sh"
