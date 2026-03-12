#!/bin/bash
## ============================================================================
## 01-deploy-openldap.sh — Deploy OpenLDAP container on IDP VM
## ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/keycloak-vars.sh"
source "$SCRIPT_DIR/../../00-common.sh"

# Load Vault helper
VAULT_ENV="${HOME}/workspace/infra-dotfiles/vault/vault-env.sh"
if [[ -f "$VAULT_ENV" ]]; then
    source "$VAULT_ENV"
else
    log_error "Vault helper not found at $VAULT_ENV"
    exit 1
fi

# Retrieve secrets from Vault
LDAP_ADMIN_PASSWORD=$(vault_get "$VAULT_KC_SECRET_PATH" ldap_admin_password)
if [[ -z "$LDAP_ADMIN_PASSWORD" ]]; then
    log_error "Could not retrieve ldap_admin_password from Vault ($VAULT_KC_SECRET_PATH)"
    exit 1
fi

SSH_CMD="ssh -o StrictHostKeyChecking=accept-new ${KC_VM_SSH_USER}@${KC_VM_HOST}"

log_info "=== Step 1: Deploy OpenLDAP on ${KC_VM_HOST} ==="

# --- Generate LDIF files from templates ---
log_info "Generating LDIF files..."

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Generate groups block
GROUPS_BLOCK=""
for group in "${LDAP_GROUPS[@]}"; do
    GROUPS_BLOCK+="dn: cn=${group},ou=Groups,${LDAP_BASE_DN}
objectClass: groupOfNames
cn: ${group}
member: cn=placeholder

"
done

# Generate base LDIF
sed -e "s|__LDAP_BASE_DN__|${LDAP_BASE_DN}|g" \
    -e "/__GROUPS__/{
r /dev/stdin
d
}" "$SCRIPT_DIR/templates/00-base.ldif.tpl" <<< "$GROUPS_BLOCK" > "$TMPDIR/00-base.ldif"

# Generate users block
USERS_BLOCK=""
for user_entry in "${LDAP_DEMO_USERS[@]}"; do
    IFS=':' read -r uid first last group <<< "$user_entry"
    USERS_BLOCK+="dn: uid=${uid},ou=People,${LDAP_BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: ${uid}
sn: ${last}
givenName: ${first}
cn: ${first} ${last}
displayName: ${first} ${last}
mail: ${uid}@${LDAP_DOMAIN}
uidNumber: $((10000 + RANDOM % 50000))
gidNumber: 10000
homeDirectory: /home/${uid}
userPassword: changeme

"
done

sed "s|__USERS__|${USERS_BLOCK}|" "$SCRIPT_DIR/templates/01-users.ldif.tpl" > "$TMPDIR/01-users.ldif"

# Generate group membership LDIF (modify operations to add real members)
cat > "$TMPDIR/02-memberships.ldif" <<LDIFEOF
# Group memberships — add users to their groups
LDIFEOF

for user_entry in "${LDAP_DEMO_USERS[@]}"; do
    IFS=':' read -r uid first last group <<< "$user_entry"
    cat >> "$TMPDIR/02-memberships.ldif" <<LDIFEOF

dn: cn=${group},ou=Groups,${LDAP_BASE_DN}
changetype: modify
add: member
member: uid=${uid},ou=People,${LDAP_BASE_DN}

LDIFEOF
done

log_info "LDIF files generated in $TMPDIR"

# --- Create Podman network on VM ---
log_info "Creating Podman network on VM..."
$SSH_CMD "sudo podman network create ${KC_PODMAN_NETWORK} 2>/dev/null || true"

# --- Transfer LDIF files ---
log_info "Transferring LDIF files to VM..."
$SSH_CMD "mkdir -p /tmp/ldap-init"
for f in "$TMPDIR"/*.ldif; do
    fname=$(basename "$f")
    ssh -o StrictHostKeyChecking=accept-new "${KC_VM_SSH_USER}@${KC_VM_HOST}" "cat > /tmp/ldap-init/${fname}" < "$f"
done

# --- Deploy OpenLDAP container ---
log_info "Deploying OpenLDAP container..."
$SSH_CMD "sudo podman rm -f ${LDAP_CONTAINER_NAME} 2>/dev/null || true"

$SSH_CMD "sudo podman run -d \
    --name ${LDAP_CONTAINER_NAME} \
    --network ${KC_PODMAN_NETWORK} \
    -p 127.0.0.1:${LDAP_PORT}:1389 \
    -e LDAP_ROOT='${LDAP_BASE_DN}' \
    -e LDAP_ADMIN_USERNAME='${LDAP_ADMIN_USER}' \
    -e LDAP_ADMIN_PASSWORD='${LDAP_ADMIN_PASSWORD}' \
    -e LDAP_CUSTOM_LDIF_DIR=/ldifs \
    -v /tmp/ldap-init:/ldifs:Z \
    ${LDAP_IMAGE}"

# --- Wait for OpenLDAP to be ready ---
log_info "Waiting for OpenLDAP to be ready..."
for i in $(seq 1 30); do
    if $SSH_CMD "ldapsearch -x -H ldap://127.0.0.1:${LDAP_PORT} -D 'cn=${LDAP_ADMIN_USER},${LDAP_BASE_DN}' -w '${LDAP_ADMIN_PASSWORD}' -b '${LDAP_BASE_DN}' '(objectClass=organizationalUnit)'" >/dev/null 2>&1; then
        log_info "OpenLDAP is ready"
        break
    fi
    if [[ $i -eq 30 ]]; then
        log_error "OpenLDAP did not become ready in 30 seconds"
        $SSH_CMD "sudo podman logs ${LDAP_CONTAINER_NAME}" || true
        exit 1
    fi
    sleep 1
done

# --- Apply membership modifications ---
log_info "Applying group memberships..."
$SSH_CMD "ldapmodify -x -H ldap://127.0.0.1:${LDAP_PORT} -D 'cn=${LDAP_ADMIN_USER},${LDAP_BASE_DN}' -w '${LDAP_ADMIN_PASSWORD}' -f /tmp/ldap-init/02-memberships.ldif" || log_warn "Some membership modifications may have failed (expected if already applied)"

# --- Verify ---
log_info "Verifying LDAP entries..."
USERS_FOUND=$($SSH_CMD "ldapsearch -x -H ldap://127.0.0.1:${LDAP_PORT} -D 'cn=${LDAP_ADMIN_USER},${LDAP_BASE_DN}' -w '${LDAP_ADMIN_PASSWORD}' -b 'ou=People,${LDAP_BASE_DN}' '(uid=*)' uid" 2>/dev/null | grep -c "^uid:" || echo 0)
GROUPS_FOUND=$($SSH_CMD "ldapsearch -x -H ldap://127.0.0.1:${LDAP_PORT} -D 'cn=${LDAP_ADMIN_USER},${LDAP_BASE_DN}' -w '${LDAP_ADMIN_PASSWORD}' -b 'ou=Groups,${LDAP_BASE_DN}' '(objectClass=groupOfNames)' cn" 2>/dev/null | grep -c "^cn:" || echo 0)

log_info "Found ${USERS_FOUND} users and ${GROUPS_FOUND} groups in LDAP"

if [[ "$USERS_FOUND" -ge 1 ]] && [[ "$GROUPS_FOUND" -ge 1 ]]; then
    log_info "OpenLDAP deployment successful"
else
    log_warn "Expected at least 1 user and 1 group. Check LDIF files."
fi

log_info "=== Step 1 complete ==="
