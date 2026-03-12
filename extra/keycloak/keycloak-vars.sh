#!/bin/bash
## ============================================================================
## keycloak-vars.sh — Configuration variables for Keycloak + OpenLDAP extra
## ============================================================================

# VM
KC_VM_HOST="172.16.3.12"
KC_VM_SSH_USER="opensuse"

# OpenLDAP
LDAP_CONTAINER_NAME="openldap"
LDAP_IMAGE="docker.io/bitnami/openldap:2.6"
LDAP_PORT=1389
LDAP_DOMAIN="home.lo"
LDAP_BASE_DN="dc=home,dc=lo"
LDAP_ADMIN_USER="admin"
LDAP_ORG_NAME="Homelab"
LDAP_GROUPS=("rancher-admins" "rancher-users" "rancher-readonly")
LDAP_DEMO_USERS=(
    "jniedergang:Julien:Niedergang:rancher-admins"
    "demouser:Demo:User:rancher-users"
    "viewer:Read:Only:rancher-readonly"
)

# Keycloak
KC_CONTAINER_NAME="keycloak"
KC_IMAGE="quay.io/keycloak/keycloak:26.2"
KC_HTTPS_PORT=8443
KC_FQDN="keycloak.home.lo"
KC_REALM="rancher"
KC_ADMIN_USER="admin"
KC_PODMAN_NETWORK="keycloak-net"

# Rancher
RANCHER_URL="https://rancher.home.zypp.fr"
RANCHER_OIDC_CLIENT_ID="rancher"

# Vault paths
VAULT_KC_SECRET_PATH="secret/services/keycloak"

# Pi-hole
PIHOLE_HOST="172.16.3.6"
PIHOLE_SSH_USER="ju"
PIHOLE_CONTAINER="b41a7dff114c_pihole"

# DNS entries to create
DNS_ENTRIES=(
    "${KC_VM_HOST} idp.home.lo"
    "${KC_VM_HOST} keycloak.home.lo"
    "${KC_VM_HOST} ldap.home.lo"
)

# Rancher Manager
RANCHER_VM_HOST="172.16.3.20"
RANCHER_VM_SSH_USER="rancher"
