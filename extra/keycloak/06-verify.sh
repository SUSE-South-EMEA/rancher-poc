#!/bin/bash
## ============================================================================
## 06-verify.sh — End-to-end verification of Keycloak + OIDC setup
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

LDAP_ADMIN_PASSWORD=$(vault_get "$VAULT_KC_SECRET_PATH" ldap_admin_password)
RANCHER_PASSWORD=$(vault_get "secret/services/rancher" password)

SSH_CMD="ssh -o StrictHostKeyChecking=accept-new ${KC_VM_SSH_USER}@${KC_VM_HOST}"
KC_BASE="https://${KC_FQDN}:${KC_HTTPS_PORT}"

log_info "=== Verification: Keycloak + OpenLDAP + Rancher OIDC ==="

ERRORS=0
CHECKS=0

check() {
    local name="$1"
    local result="$2"
    CHECKS=$((CHECKS + 1))
    if [[ "$result" == "OK" ]]; then
        log_info "[PASS] $name"
    else
        log_error "[FAIL] $name — $result"
        ERRORS=$((ERRORS + 1))
    fi
}

# --- 1. VM reachable ---
if $SSH_CMD "hostname" >/dev/null 2>&1; then
    check "VM SSH reachable" "OK"
else
    check "VM SSH reachable" "Cannot connect to ${KC_VM_HOST}"
fi

# --- 2. Containers running ---
CONTAINERS=$($SSH_CMD "sudo podman ps --format '{{.Names}}'" 2>/dev/null || echo "")
if echo "$CONTAINERS" | grep -q "${LDAP_CONTAINER_NAME}"; then
    check "OpenLDAP container running" "OK"
else
    check "OpenLDAP container running" "Container not found"
fi
if echo "$CONTAINERS" | grep -q "${KC_CONTAINER_NAME}"; then
    check "Keycloak container running" "OK"
else
    check "Keycloak container running" "Container not found"
fi

# --- 3. LDAP populated ---
LDAP_USERS=$($SSH_CMD "ldapsearch -x -H ldap://127.0.0.1:${LDAP_PORT} -D 'cn=${LDAP_ADMIN_USER},${LDAP_BASE_DN}' -w '${LDAP_ADMIN_PASSWORD}' -b 'ou=People,${LDAP_BASE_DN}' '(uid=*)' uid 2>/dev/null" | grep -c "^uid:" || echo 0)
if [[ "$LDAP_USERS" -ge 1 ]]; then
    check "LDAP users present ($LDAP_USERS)" "OK"
else
    check "LDAP users present" "No users found"
fi

# --- 4. Keycloak health ---
HEALTH=$($SSH_CMD "curl -sk https://127.0.0.1:9000/health/ready 2>/dev/null" || echo "")
# Fallback: try main port if management port didn't work
if ! echo "$HEALTH" | grep -q '"status"'; then
    HEALTH=$($SSH_CMD "curl -sk https://127.0.0.1:${KC_HTTPS_PORT}/realms/master 2>/dev/null" || echo "")
fi
if echo "$HEALTH" | grep -q '"status"'; then
    check "Keycloak health" "OK"
else
    check "Keycloak health" "Not healthy"
fi

# --- 5. OIDC discovery ---
DISCOVERY=$(curl -sk "${KC_BASE}/realms/${KC_REALM}/.well-known/openid-configuration" 2>/dev/null || echo "")
if echo "$DISCOVERY" | grep -q "authorization_endpoint"; then
    check "OIDC discovery endpoint" "OK"
else
    check "OIDC discovery endpoint" "Not available"
fi

# --- 6. DNS resolution ---
for entry in "${DNS_ENTRIES[@]}"; do
    ENTRY_IP=$(echo "$entry" | awk '{print $1}')
    ENTRY_HOST=$(echo "$entry" | awk '{print $2}')
    RESOLVED=$(dig +short "$ENTRY_HOST" @"${PIHOLE_HOST}" 2>/dev/null || echo "")
    if [[ "$RESOLVED" == "$ENTRY_IP" ]]; then
        check "DNS $ENTRY_HOST" "OK"
    else
        check "DNS $ENTRY_HOST" "Resolves to '$RESOLVED', expected $ENTRY_IP"
    fi
done

# --- 7. Rancher OIDC status ---
LOGIN_RESPONSE=$(curl -sk -X POST "${RANCHER_URL}/v3-public/localProviders/local?action=login" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"admin\", \"password\": \"${RANCHER_PASSWORD}\"}" 2>/dev/null)
RANCHER_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || echo "")

if [[ -n "$RANCHER_TOKEN" ]]; then
    OIDC_STATUS=$(curl -sk -H "Authorization: Bearer ${RANCHER_TOKEN}" \
        "${RANCHER_URL}/v3/authConfigs/keycloakoidc" 2>/dev/null)
    OIDC_ENABLED=$(echo "$OIDC_STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('enabled', False))" 2>/dev/null || echo "")
    if [[ "$OIDC_ENABLED" == "True" ]]; then
        check "Rancher OIDC enabled" "OK"
    else
        check "Rancher OIDC enabled" "OIDC not enabled in Rancher"
    fi
else
    check "Rancher OIDC enabled" "Cannot login to Rancher API"
fi

# --- Summary ---
echo
log_info "=== Results: ${CHECKS} checks, $((CHECKS - ERRORS)) passed, ${ERRORS} failed ==="
if [[ $ERRORS -eq 0 ]]; then
    log_info "All checks passed"
else
    log_error "${ERRORS} check(s) failed — review output above"
fi
exit $ERRORS
