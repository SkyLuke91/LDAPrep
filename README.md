# LDAP Installation Wizard for Debian LXC

This project provides an interactive wizard to deploy and configure an OpenLDAP server on a Debian LXC container (Proxmox compatible).

## Features
- **Interactive Setup**: Simple prompts for Domain, Organization, and Administrator credentials.
- **Automated Config**: Handles `slapd` installation and base DN configuration (`dc=example,dc=com`).
- **User Management**: Integrated option to create initial users and groups.
- **Verification**: Built-in connectivity and service health checks.

## Prerequisites
- **OS**: Debian 11 / 12 (LXC Container recommended)
- **User**: Root privileges required

## Installation

Run the following commands inside your LXC container:

```bash
# 1. Update and install connectivity tools
apt-get update && apt-get install -y git

# 2. Clone the repository
git clone https://github.com/SkyLuke91/LDAPrep.git
cd LDAPrep

# 3. Make scripts executable
chmod +x bootstrap.sh install_ldap.sh

# 4. Run the Bootstrap Wizard
./bootstrap.sh
```

## specific usage
The wizard will ask for:
1. **LDAP Domain**: The domain for your directory (e.g., `intra.company.com`).
2. **Organization**: A descriptive name for your organization.
3. **Admin Password**: The root password for the LDAP `cn=admin` account.

## Verification
The script runs self-tests at the end. You can also manually verify from another machine using `ldapsearch`:

```bash
ldapsearch -x -H ldap://<LXC_IP> -b "dc=example,dc=com" -D "cn=admin,dc=example,dc=com" -W
```
*(Replace the Base DN `dc=example,dc=com` with the one you configured)*https://github.com/SkyLuke91/LDAPrep.git
