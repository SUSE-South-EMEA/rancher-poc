#!/bin/bash
## ============================================================================
## 05-configure-rancher-oidc.sh — Configure Rancher to use Keycloak OIDC
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
OIDC_CLIENT_SECRET=$(vault_get "$VAULT_KC_SECRET_PATH" oidc_client_secret)
RANCHER_PASSWORD=$(vault_get "secret/services/rancher" password)

KC_BASE="https://${KC_FQDN}:${KC_HTTPS_PORT}"

log_info "=== Step 5: Configure Rancher OIDC authentication ==="

# --- 1. Install self-signed CA on Rancher VM ---
log_info "Installing Keycloak CA certificate on Rancher VM..."

CERT_FILE="$SCRIPT_DIR/.certs/keycloak-ca.crt"
if [[ ! -f "$CERT_FILE" ]]; then
    log_error "Keycloak CA certificate not found at $CERT_FILE"
    log_error "Run 02-deploy-keycloak.sh first"
    exit 1
fi

SSH_RANCHER="ssh -o StrictHostKeyChecking=accept-new ${RANCHER_VM_SSH_USER}@${RANCHER_VM_HOST}"

# Transfer cert to Rancher VM
$SSH_RANCHER "cat > /tmp/keycloak-ca.crt" < "$CERT_FILE"
$SSH_RANCHER "sudo cp /tmp/keycloak-ca.crt /etc/pki/trust/anchors/keycloak-ca.crt && sudo update-ca-certificates"
log_info "CA certificate installed on Rancher VM"

# --- 2. Restart Rancher pods to pick up new CA ---
log_info "Restarting Rancher deployment to trust new CA..."
KUBECTL="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"
$SSH_RANCHER "$KUBECTL rollout restart deployment/rancher -n cattle-system"

log_info "Waiting for Rancher pods to be ready..."
for i in $(seq 1 60); do
    READY=$($SSH_RANCHER "$KUBECTL get deploy rancher -n cattle-system -o jsonpath='{.status.readyReplicas}'" 2>/dev/null || echo "0")
    if [[ "$READY" -ge 1 ]]; then
        log_info "Rancher deployment ready (${READY} replicas)"
        break
    fi
    if [[ $i -eq 60 ]]; then
        log_warn "Rancher pods still not ready after 120s, continuing anyway..."
    fi
    sleep 2
done

# --- 3. Login to Rancher API ---
log_info "Logging in to Rancher API..."
LOGIN_RESPONSE=$(curl -sk -X POST "${RANCHER_URL}/v3-public/localProviders/local?action=login" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"admin\", \"password\": \"${RANCHER_PASSWORD}\"}")

RANCHER_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || echo "")

if [[ -z "$RANCHER_TOKEN" ]]; then
    log_error "Failed to login to Rancher API"
    log_error "Response: $(echo "$LOGIN_RESPONSE" | head -c 200)"
    exit 1
fi
log_info "Rancher API login successful"

# --- 4. Configure Keycloak OIDC ---
log_info "Configuring Keycloak OIDC auth provider..."

OIDC_CONFIG=$(cat <<JSONEOF
{
    "accessMode": "unrestricted",
    "allowedPrincipalIds": [],
    "enabled": true,
    "type": "keyCloakOIDCConfig",
    "rancherUrl": "${RANCHER_URL}/verify-auth",
    "clientId": "${RANCHER_OIDC_CLIENT_ID}",
    "clientSecret": "${OIDC_CLIENT_SECRET}",
    "issuer": "${KC_BASE}/realms/${KC_REALM}",
    "authEndpoint": "${KC_BASE}/realms/${KC_REALM}/protocol/openid-connect/auth",
    "tokenEndpoint": "${KC_BASE}/realms/${KC_REALM}/protocol/openid-connect/token",
    "scope": "openid profile email groups",
    "groupSearchEnabled": true
}
JSONEOF
)

RESPONSE=$(curl -sk -X PUT "${RANCHER_URL}/v3/keyCloakOIDCConfig" \
    -H "Authorization: Bearer ${RANCHER_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$OIDC_CONFIG")

ENABLED=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('enabled', False))" 2>/dev/null || echo "")

if [[ "$ENABLED" == "True" ]]; then
    log_info "Keycloak OIDC authentication enabled in Rancher"
else
    log_warn "OIDC config response: $(echo "$RESPONSE" | head -c 300)"
    log_warn "Check Rancher UI to verify OIDC configuration"
fi

log_info "=== Step 5 complete ==="
log_info ""
log_info "Users can now log in to Rancher via:"
log_info "  ${RANCHER_URL} -> 'Log in with Keycloak'"
log_info ""
log_info "Test credentials:"
log_info "  jniedergang / changeme (group: rancher-admins)"
log_info "  demouser / changeme (group: rancher-users)"
log_info "  viewer / changeme (group: rancher-readonly)"
