#!/bin/bash
## ============================================================================
## 04-configure-keycloak-ldap.sh — Configure Keycloak realm, LDAP federation,
##    and OIDC client via Admin REST API
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

KC_ADMIN_PASSWORD=$(vault_get "$VAULT_KC_SECRET_PATH" admin_password)
LDAP_ADMIN_PASSWORD=$(vault_get "$VAULT_KC_SECRET_PATH" ldap_admin_password)
OIDC_CLIENT_SECRET=$(vault_get "$VAULT_KC_SECRET_PATH" oidc_client_secret)

KC_BASE="https://${KC_FQDN}:${KC_HTTPS_PORT}"

log_info "=== Step 4: Configure Keycloak (realm, LDAP, OIDC client) ==="

# --- Helper: get admin token ---
get_admin_token() {
    local token
    token=$(curl -sk -X POST "${KC_BASE}/realms/master/protocol/openid-connect/token" \
        -d "client_id=admin-cli" \
        -d "username=${KC_ADMIN_USER}" \
        -d "password=${KC_ADMIN_PASSWORD}" \
        -d "grant_type=password" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
    if [[ -z "$token" ]]; then
        log_error "Failed to get admin token from Keycloak"
        exit 1
    fi
    echo "$token"
}

TOKEN=$(get_admin_token)

# --- 1. Create realm ---
log_info "Creating realm '${KC_REALM}'..."
REALM_EXISTS=$(curl -sk -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "${KC_BASE}/admin/realms/${KC_REALM}")

if [[ "$REALM_EXISTS" == "200" ]]; then
    log_info "Realm '${KC_REALM}' already exists"
else
    curl -sk -X POST "${KC_BASE}/admin/realms" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"realm\": \"${KC_REALM}\",
            \"enabled\": true,
            \"displayName\": \"Rancher SSO\"
        }"
    log_info "Realm '${KC_REALM}' created"
fi

# Refresh token (realm creation may take a moment)
TOKEN=$(get_admin_token)

# --- 2. Configure LDAP User Federation ---
log_info "Configuring LDAP User Federation..."

# Check if federation already exists
EXISTING_FED=$(curl -sk -H "Authorization: Bearer $TOKEN" \
    "${KC_BASE}/admin/realms/${KC_REALM}/components?type=org.keycloak.storage.UserStorageProvider" 2>/dev/null)

FED_EXISTS=$(echo "$EXISTING_FED" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for c in data:
    if c.get('name') == 'openldap':
        print(c['id'])
        break
" 2>/dev/null || echo "")

if [[ -n "$FED_EXISTS" ]]; then
    log_info "LDAP federation 'openldap' already exists (id: $FED_EXISTS)"
    LDAP_FED_ID="$FED_EXISTS"
else
    LDAP_FED_RESPONSE=$(curl -sk -X POST "${KC_BASE}/admin/realms/${KC_REALM}/components" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -D - \
        -d "{
            \"name\": \"openldap\",
            \"providerId\": \"ldap\",
            \"providerType\": \"org.keycloak.storage.UserStorageProvider\",
            \"config\": {
                \"vendor\": [\"other\"],
                \"connectionUrl\": [\"ldap://${LDAP_CONTAINER_NAME}:389\"],
                \"bindDn\": [\"cn=${LDAP_ADMIN_USER},${LDAP_BASE_DN}\"],
                \"bindCredential\": [\"${LDAP_ADMIN_PASSWORD}\"],
                \"usersDn\": [\"ou=People,${LDAP_BASE_DN}\"],
                \"usernameLDAPAttribute\": [\"uid\"],
                \"rdnLDAPAttribute\": [\"uid\"],
                \"uuidLDAPAttribute\": [\"entryUUID\"],
                \"userObjectClasses\": [\"inetOrgPerson\"],
                \"editMode\": [\"READ_ONLY\"],
                \"syncRegistrations\": [\"false\"],
                \"searchScope\": [\"1\"],
                \"pagination\": [\"true\"],
                \"importEnabled\": [\"true\"],
                \"batchSizeForSync\": [\"1000\"],
                \"fullSyncPeriod\": [\"-1\"],
                \"changedSyncPeriod\": [\"-1\"]
            }
        }")

    # Extract component ID from Location header
    LDAP_FED_ID=$(echo "$LDAP_FED_RESPONSE" | grep -i "^location:" | sed 's|.*/||' | tr -d '\r\n')
    if [[ -z "$LDAP_FED_ID" ]]; then
        # Try to get it from the components list
        TOKEN=$(get_admin_token)
        LDAP_FED_ID=$(curl -sk -H "Authorization: Bearer $TOKEN" \
            "${KC_BASE}/admin/realms/${KC_REALM}/components?type=org.keycloak.storage.UserStorageProvider" | \
            python3 -c "import sys,json; [print(c['id']) for c in json.load(sys.stdin) if c.get('name')=='openldap']" 2>/dev/null | head -1)
    fi
    log_info "LDAP federation created (id: $LDAP_FED_ID)"
fi

TOKEN=$(get_admin_token)

# --- 3. Add Group Mapper ---
log_info "Adding LDAP group mapper..."

# Check if mapper exists
EXISTING_MAPPERS=$(curl -sk -H "Authorization: Bearer $TOKEN" \
    "${KC_BASE}/admin/realms/${KC_REALM}/components?parent=${LDAP_FED_ID}&type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper" 2>/dev/null)

GROUP_MAPPER_EXISTS=$(echo "$EXISTING_MAPPERS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for c in data:
    if c.get('name') == 'group-mapper':
        print('yes')
        break
" 2>/dev/null || echo "")

if [[ "$GROUP_MAPPER_EXISTS" == "yes" ]]; then
    log_info "Group mapper already exists"
else
    curl -sk -X POST "${KC_BASE}/admin/realms/${KC_REALM}/components" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"group-mapper\",
            \"providerId\": \"group-ldap-mapper\",
            \"providerType\": \"org.keycloak.storage.ldap.mappers.LDAPStorageMapper\",
            \"parentId\": \"${LDAP_FED_ID}\",
            \"config\": {
                \"groups.dn\": [\"ou=Groups,${LDAP_BASE_DN}\"],
                \"group.name.ldap.attribute\": [\"cn\"],
                \"group.object.classes\": [\"groupOfNames\"],
                \"membership.ldap.attribute\": [\"member\"],
                \"membership.attribute.type\": [\"DN\"],
                \"membership.user.ldap.attribute\": [\"uid\"],
                \"mode\": [\"READ_ONLY\"],
                \"user.roles.retrieve.strategy\": [\"LOAD_GROUPS_BY_MEMBER_ATTRIBUTE\"],
                \"groups.ldap.filter\": [\"(cn=rancher-*)\"],
                \"drop.non.existing.groups.during.sync\": [\"true\"]
            }
        }"
    log_info "Group mapper created"
fi

TOKEN=$(get_admin_token)

# --- 4. Trigger LDAP Sync ---
log_info "Triggering full LDAP sync..."
curl -sk -X POST "${KC_BASE}/admin/realms/${KC_REALM}/user-storage/${LDAP_FED_ID}/sync?action=triggerFullSync" \
    -H "Authorization: Bearer $TOKEN" || log_warn "LDAP sync trigger returned an error (may be normal on first run)"

sleep 3

# Verify users synced
TOKEN=$(get_admin_token)
SYNCED_USERS=$(curl -sk -H "Authorization: Bearer $TOKEN" \
    "${KC_BASE}/admin/realms/${KC_REALM}/users?max=100" | \
    python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
log_info "Users synced in Keycloak realm: $SYNCED_USERS"

# --- 5. Create OIDC Client ---
log_info "Creating OIDC client '${RANCHER_OIDC_CLIENT_ID}'..."

TOKEN=$(get_admin_token)
EXISTING_CLIENT=$(curl -sk -H "Authorization: Bearer $TOKEN" \
    "${KC_BASE}/admin/realms/${KC_REALM}/clients?clientId=${RANCHER_OIDC_CLIENT_ID}" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null || echo "")

if [[ -n "$EXISTING_CLIENT" ]]; then
    log_info "OIDC client '${RANCHER_OIDC_CLIENT_ID}' already exists (id: $EXISTING_CLIENT)"
    CLIENT_UUID="$EXISTING_CLIENT"
else
    curl -sk -X POST "${KC_BASE}/admin/realms/${KC_REALM}/clients" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"clientId\": \"${RANCHER_OIDC_CLIENT_ID}\",
            \"name\": \"Rancher Manager\",
            \"enabled\": true,
            \"protocol\": \"openid-connect\",
            \"publicClient\": false,
            \"clientAuthenticatorType\": \"client-secret\",
            \"secret\": \"${OIDC_CLIENT_SECRET}\",
            \"redirectUris\": [\"${RANCHER_URL}/verify-auth\"],
            \"webOrigins\": [\"${RANCHER_URL}\"],
            \"standardFlowEnabled\": true,
            \"directAccessGrantsEnabled\": true,
            \"serviceAccountsEnabled\": false,
            \"authorizationServicesEnabled\": false
        }"

    TOKEN=$(get_admin_token)
    CLIENT_UUID=$(curl -sk -H "Authorization: Bearer $TOKEN" \
        "${KC_BASE}/admin/realms/${KC_REALM}/clients?clientId=${RANCHER_OIDC_CLIENT_ID}" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null || echo "")
    log_info "OIDC client created (uuid: $CLIENT_UUID)"
fi

# --- 6. Add Groups Protocol Mapper to client ---
log_info "Adding 'groups' protocol mapper to client..."

TOKEN=$(get_admin_token)
EXISTING_PROTO_MAPPERS=$(curl -sk -H "Authorization: Bearer $TOKEN" \
    "${KC_BASE}/admin/realms/${KC_REALM}/clients/${CLIENT_UUID}/protocol-mappers/models" 2>/dev/null)

GROUPS_MAPPER_EXISTS=$(echo "$EXISTING_PROTO_MAPPERS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data:
    if m.get('name') == 'groups':
        print('yes')
        break
" 2>/dev/null || echo "")

if [[ "$GROUPS_MAPPER_EXISTS" == "yes" ]]; then
    log_info "Groups protocol mapper already exists"
else
    curl -sk -X POST "${KC_BASE}/admin/realms/${KC_REALM}/clients/${CLIENT_UUID}/protocol-mappers/models" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "groups",
            "protocol": "openid-connect",
            "protocolMapper": "oidc-group-membership-mapper",
            "config": {
                "full.path": "false",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "claim.name": "groups",
                "userinfo.token.claim": "true"
            }
        }'
    log_info "Groups protocol mapper added"
fi

# --- Verify ---
log_info "Verifying OIDC discovery endpoint..."
DISCOVERY=$(curl -sk "${KC_BASE}/realms/${KC_REALM}/.well-known/openid-configuration" 2>/dev/null)
ISSUER=$(echo "$DISCOVERY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('issuer',''))" 2>/dev/null || echo "")

if [[ -n "$ISSUER" ]]; then
    log_info "OIDC Issuer: $ISSUER"
else
    log_warn "Could not retrieve OIDC discovery endpoint"
fi

log_info "=== Step 4 complete ==="
