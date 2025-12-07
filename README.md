# LDAPrep
automated LDAP server doployment tool. 
Overview
This wizard-based script installs and configures an OpenLDAP server on a Debian LXC container. It handles dependencies, security, and basic directory structure creation (People/Groups) automatically.

User Inputs Required
During installation, you will be prompted for:

Domain: (e.g., company.local) - Automatically converts to dc=company,dc=local.
Organization Name: (e.g., MyCompany).
Admin Password: Securely prompted (hidden).
New Users: Option to interactively add users during setup.
Verification Steps
The script performs the following built-in checks:

Port Check: Verifies TCP 389 is listening.
Service Status: Verifies slapd is active.
Bind Test: Attempts a real LDAP search using the provided credentials.
Manual Verification
You can manually test the server after installation with:

ldapsearch -x -b "dc=example,dc=com" -D "cn=admin,dc=example,dc=com" -W
