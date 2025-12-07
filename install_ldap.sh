#!/bin/bash

# LDAP Installation Wizard for Debian LXC
# Author: Antigravity
# Description: Interactive script to deploy OpenLDAP

set -e

# --- Configuration & Colors ---
LOG_FILE="/var/log/ldap_install.log"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Redirect output to log file (keeping stdout/stderr visible for now, or selective logging)
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

# --- 1. Check Root ---
if [ "$EUID" -ne 0 ]; then
  error "This script must be run as root."
fi

# --- 2. User Inputs ---
clear
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}       LDAP Server Installation Wizard        ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo ""

# Domain
read -p "Enter LDAP Domain (e.g., example.com): " LDAP_DOMAIN_INPUT
if [ -z "$LDAP_DOMAIN_INPUT" ]; then error "Domain cannot be empty"; fi

# Convert domain to DC syntax (example.com -> dc=example,dc=com)
IFS='.' read -r -a DOMAIN_PARTS <<< "$LDAP_DOMAIN_INPUT"
LDAP_BASE_DN=""
for part in "${DOMAIN_PARTS[@]}"; do
    LDAP_BASE_DN="${LDAP_BASE_DN}dc=${part},"
done
LDAP_BASE_DN=${LDAP_BASE_DN%,} # Remove trailing comma

echo -e "Base DN derived: ${GREEN}${LDAP_BASE_DN}${NC}"

# Organization
read -p "Enter Organization Name (e.g., Example Corp): " LDAP_ORG
if [ -z "$LDAP_ORG" ]; then LDAP_ORG="My Organization"; fi

# Admin Password
while true; do
    echo -n "Enter LDAP Admin Password: "
    read -s LDAP_ADMIN_PASS
    echo ""
    echo -n "Confirm LDAP Admin Password: "
    read -s LDAP_ADMIN_PASS_CONFIRM
    echo ""
    
    if [ "$LDAP_ADMIN_PASS" == "$LDAP_ADMIN_PASS_CONFIRM" ] && [ -n "$LDAP_ADMIN_PASS" ]; then
        break
    else
        echo -e "${RED}Passwords do not match or are empty. Try again.${NC}"
    fi
done

log "Configuration inputs received."

# --- 3. Install Packages ---
log "Installing slapd and ldap-utils..."
export DEBIAN_FRONTEND=noninteractive

# Pre-seed answers to avoid popups
# effective way to set password is to use debconf-set-selections
echo "slapd slapd/root_password password $LDAP_ADMIN_PASS" | debconf-set-selections
echo "slapd slapd/root_password_again password $LDAP_ADMIN_PASS" | debconf-set-selections
echo "slapd slapd/domain string $LDAP_DOMAIN_INPUT" | debconf-set-selections

apt-get update -qq
apt-get install -y slapd ldap-utils

# Verify Service
if ! systemctl is-active --quiet slapd; then
    error "slapd service failed to start."
fi
log "Packages installed and service is running."

# --- 4. Configure LDAP (Post-Install) ---
log "Configuring LDAP Base Structure..."

# Since debconf might not set everything perfectly for custom needs, we enforce via ldapmodify if needed.
# But for a basic setup, the pre-seed usually works for the suffix.
# Let's double check the suffix matches what we want.

CURRENT_SUFFIX=$(slapcat -n 0 | grep olcSuffix | awk '{print $2}')

# Note: Changing suffix after install is complex. 
# `dpkg-reconfigure -p critical slapd` is often safer if we want to enforce the domain map.
# However, let's assume the pre-seed worked or we perform a reconfiguration.

# Force reconfiguration to ensure our variables are respected if pre-seed missed
# Using debconf non-interactive reconfigure with our values
echo "slapd slapd/dns_domain string $LDAP_DOMAIN_INPUT" | debconf-set-selections
echo "slapd slapd/organization string $LDAP_ORG" | debconf-set-selections
# Allow ignoring failures here if it's already set
dpkg-reconfigure -f noninteractive slapd || true

# Wait a moment for slapd to restart
sleep 3

# --- 5. Add Base OUs (People, Groups) ---
log "Creating base Organizational Units (People, Groups)..."

LDIF_FILE="/tmp/base_structure.ldif"

cat > "$LDIF_FILE" <<EOF
dn: ou=people,$LDAP_BASE_DN
objectClass: organizationalUnit
ou: people

dn: ou=groups,$LDAP_BASE_DN
objectClass: organizationalUnit
ou: groups
EOF

# Attempt to add. If they exist, it will fail harmlessly (we can grep for error)
ldapadd -x -D "cn=admin,$LDAP_BASE_DN" -w "$LDAP_ADMIN_PASS" -f "$LDIF_FILE" > /dev/null 2>&1 || log "Base OUs might already exist."

# --- 6. Interactive User Creation ---
while true; do
    echo ""
    read -p "Do you want to add a user now? (y/n): " ADD_USER_CHOICE
    case $ADD_USER_CHOICE in
        [Yy]* ) 
            read -p "Username (uid): " NEW_USER_UID
            read -p "First Name (cn): " NEW_USER_CN
            read -p "Last Name (sn): " NEW_USER_SN
            echo -n "User Password: "
            read -s NEW_USER_PASS
            echo ""
            
            USER_LDIF="/tmp/user_${NEW_USER_UID}.ldif"
            # Hashing password
            HASHED_PASS=$(slappasswd -s "$NEW_USER_PASS")
            
            cat > "$USER_LDIF" <<EOF
dn: uid=$NEW_USER_UID,ou=people,$LDAP_BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: $NEW_USER_UID
sn: $NEW_USER_SN
givenName: $NEW_USER_CN
cn: $NEW_USER_CN $NEW_USER_SN
displayName: $NEW_USER_CN $NEW_USER_SN
uidNumber: 10000
gidNumber: 10000
userPassword: $HASHED_PASS
gecos: $NEW_USER_CN $NEW_USER_SN
loginShell: /bin/bash
homeDirectory: /home/$NEW_USER_UID
EOF
            # Note: uidNumber/gidNumber handling needs to be dynamic in a real robust script 
            # (check max used ID), but for a basic wizard, we'll just warn or use a random high number/logic.
            # For this MVP, let's grab the highest uid + 1 or start at 10000.
            
            # Simple dynamic ID logic
            LAST_UID=$(ldapsearch -x -D "cn=admin,$LDAP_BASE_DN" -w "$LDAP_ADMIN_PASS" -b "ou=people,$LDAP_BASE_DN" "(objectClass=posixAccount)" uidNumber | grep uidNumber | awk '{print $2}' | sort -nr | head -n1)
            if [ -z "$LAST_UID" ]; then LAST_UID=10000; fi
            NEXT_UID=$((LAST_UID + 1))
            
            # Fix the LDIF with correct UID
            sed -i "s/uidNumber: 10000/uidNumber: $NEXT_UID/" "$USER_LDIF"
            sed -i "s/gidNumber: 10000/gidNumber: $NEXT_UID/" "$USER_LDIF"

            ldapadd -x -D "cn=admin,$LDAP_BASE_DN" -w "$LDAP_ADMIN_PASS" -f "$USER_LDIF"
            if [ $? -eq 0 ]; then
                log "User $NEW_USER_UID added successfully."
            else
                log "Failed to add user $NEW_USER_UID."
            fi
            ;;
        [Nn]* ) break;;
        * ) echo "Please answer yes or no.";;
    esac
done

# --- 7. Verification ---
echo ""
log "Running connectivity tests..."

# Check Port 389
if ss -tunl | grep -q ":389"; then
    echo -e "${GREEN}[PASS] Port 389 is open.${NC}"
else
    echo -e "${RED}[FAIL] Port 389 is not listening.${NC}"
fi

# Service Status
if systemctl is-active --quiet slapd; then
    echo -e "${GREEN}[PASS] slapd service is active.${NC}"
else
    echo -e "${RED}[FAIL] slapd service is not active.${NC}"
fi

# LDAP Search Functionality
echo -e "${BLUE}Attempting LDAP bind and search...${NC}"
ldapsearch -x -D "cn=admin,$LDAP_BASE_DN" -w "$LDAP_ADMIN_PASS" -b "$LDAP_BASE_DN" "(objectclass=*)" namingContexts > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[PASS] LDAP Bind and Search successful!${NC}"
    log "Installation and Verification Complete. Server is ready."
    echo -e "Your Base DN: ${GREEN}$LDAP_BASE_DN${NC}"
    echo -e "Admin DN:     ${GREEN}cn=admin,$LDAP_BASE_DN${NC}"
else
    echo -e "${RED}[FAIL] LDAP Bind/Search failed. Check logs.${NC}"
fi

echo -e "${GREEN}Installation Wizard Finished.${NC}"
