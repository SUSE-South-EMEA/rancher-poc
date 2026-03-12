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
SSH_RANCHER="ssh -o StrictHostKeyChecking=accept-new ${RANCHER_VM_SSH_USER}@${RANCHER_VM_HOST}"
KUBECTL="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"
HELM="sudo KUBECONFIG=/etc/rancher/rke2/rke2.yaml /usr/local/bin/helm"

log_info "=== Step 5: Configure Rancher OIDC authentication ==="

# --- 1. Install self-signed CA on Rancher VM trust store ---
log_info "Installing Keycloak CA certificate on Rancher VM..."

CERT_FILE="$SCRIPT_DIR/.certs/keycloak-ca.crt"
if [[ ! -f "$CERT_FILE" ]]; then
    log_error "Keycloak CA certificate not found at $CERT_FILE"
    log_error "Run 02-deploy-keycloak.sh first"
    exit 1
fi

# Transfer cert to Rancher VM (host-level trust)
$SSH_RANCHER "cat > /tmp/keycloak-ca.crt" < "$CERT_FILE"
$SSH_RANCHER "sudo cp /tmp/keycloak-ca.crt /etc/pki/trust/anchors/keycloak-ca.crt && sudo update-ca-certificates"
log_info "CA certificate installed on Rancher VM trust store"

# --- 2. Inject CA into Rancher pods via tls-ca secret + Helm privateCA ---
log_info "Creating tls-ca secret for Rancher pods..."

# Check if secret already exists with correct content
EXISTING_CA=$($SSH_RANCHER "$KUBECTL -n cattle-system get secret tls-ca -o jsonpath='{.data.cacerts\.pem}'" 2>/dev/null | base64 -d 2>/dev/null || echo "")
LOCAL_CA=$(cat "$CERT_FILE")

if [[ "$EXISTING_CA" == "$LOCAL_CA" ]]; then
    log_info "tls-ca secret already up to date"
else
    # Delete if exists with wrong content
    $SSH_RANCHER "$KUBECTL -n cattle-system delete secret tls-ca 2>/dev/null || true"
    # Create secret with Keycloak CA
    cat "$CERT_FILE" | $SSH_RANCHER "cat > /tmp/keycloak-ca.pem"
    $SSH_RANCHER "$KUBECTL -n cattle-system create secret generic tls-ca --from-file=cacerts.pem=/tmp/keycloak-ca.pem"
    $SSH_RANCHER "rm -f /tmp/keycloak-ca.pem"
    log_info "tls-ca secret created"
fi

# --- 3. Helm upgrade with privateCA=true (injects CA into pods) ---
# Check current Helm values
CURRENT_PCA=$($SSH_RANCHER "$HELM get values rancher -n cattle-system" 2>/dev/null | grep "privateCA:" || echo "")
if echo "$CURRENT_PCA" | grep -q "true"; then
    log_info "privateCA already enabled in Helm"
else
    log_info "Enabling privateCA in Rancher Helm release..."
    $SSH_RANCHER "$HELM upgrade rancher rancher-prime/rancher -n cattle-system \
        --set hostname=rancher.home.zypp.fr \
        --set tls=external \
        --set privateCA=true \
        --set replicas=1 \
        --set systemDefaultRegistry=registry.rancher.com \
        --set global.cattle.psp.enabled=false \
        --set startupProbe.failureThreshold=60"
    log_info "Helm upgrade complete"
fi

# --- 4. Wait for Rancher to be ready ---
log_info "Waiting for Rancher rollout..."
$SSH_RANCHER "$KUBECTL -n cattle-system rollout status deploy/rancher --timeout=300s" 2>/dev/null || true

log_info "Waiting for Rancher API to respond..."
for i in $(seq 1 90); do
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "${RANCHER_URL}/ping" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        log_info "Rancher API is responding"
        break
    fi
    if [[ $i -eq 90 ]]; then
        log_warn "Rancher API still not responding after 180s, continuing anyway..."
    fi
    sleep 2
done

# --- 5. Verify pod can reach Keycloak ---
log_info "Verifying Keycloak reachability from Rancher pod..."
POD_CHECK=$($SSH_RANCHER "$KUBECTL exec -n cattle-system deploy/rancher -- curl -sf https://${KC_FQDN}:${KC_HTTPS_PORT}/realms/${KC_REALM}/.well-known/openid-configuration 2>/dev/null | head -c 50" || echo "")
if echo "$POD_CHECK" | grep -q "issuer"; then
    log_info "Rancher pod can reach Keycloak OIDC (TLS validated)"
else
    log_warn "Rancher pod cannot reach Keycloak — OIDC login may fail"
    log_warn "Check that tls-ca secret is mounted and DNS resolves inside the pod"
fi

# --- 6. Login to Rancher API ---
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

# --- 7. Configure Keycloak OIDC via PUT ---
log_info "Configuring Keycloak OIDC auth provider..."

OIDC_CONFIG=$(cat <<JSONEOF
{
    "accessMode": "unrestricted",
    "enabled": true,
    "type": "keyCloakOIDCConfig",
    "rancherUrl": "${RANCHER_URL}/verify-auth",
    "clientId": "${RANCHER_OIDC_CLIENT_ID}",
    "clientSecret": "${OIDC_CLIENT_SECRET}",
    "issuer": "${KC_BASE}/realms/${KC_REALM}",
    "authEndpoint": "${KC_BASE}/realms/${KC_REALM}/protocol/openid-connect/auth",
    "tokenEndpoint": "${KC_BASE}/realms/${KC_REALM}/protocol/openid-connect/token",
    "scope": "openid profile email",
    "groupSearchEnabled": true
}
JSONEOF
)

RESPONSE=$(curl -sk -X PUT "${RANCHER_URL}/v3/keyCloakOIDCConfigs/keycloakoidc" \
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
