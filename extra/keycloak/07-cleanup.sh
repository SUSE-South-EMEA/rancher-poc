#!/bin/bash
## ============================================================================
## 07-cleanup.sh — Remove Keycloak, OpenLDAP, DNS entries, and OIDC config
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

RANCHER_PASSWORD=$(vault_get "secret/services/rancher" password)

log_info "=== Cleanup: Keycloak + OpenLDAP + OIDC ==="

# --- 1. Disable OIDC in Rancher ---
log_info "Disabling OIDC authentication in Rancher..."
LOGIN_RESPONSE=$(curl -sk -X POST "${RANCHER_URL}/v3-public/localProviders/local?action=login" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"admin\", \"password\": \"${RANCHER_PASSWORD}\"}" 2>/dev/null)
RANCHER_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || echo "")

if [[ -n "$RANCHER_TOKEN" ]]; then
    curl -sk -X POST "${RANCHER_URL}/v3/keyCloakOIDCConfigs/keycloakoidc?action=disable" \
        -H "Authorization: Bearer ${RANCHER_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{}' >/dev/null 2>&1 || true
    log_info "OIDC disabled in Rancher"
else
    log_warn "Could not login to Rancher API — OIDC may need to be disabled manually"
fi

# --- 2. Remove CA cert and revert Helm privateCA ---
log_info "Removing Keycloak CA from Rancher..."
SSH_RANCHER="ssh -o StrictHostKeyChecking=accept-new ${RANCHER_VM_SSH_USER}@${RANCHER_VM_HOST}"
KUBECTL="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"
HELM="sudo KUBECONFIG=/etc/rancher/rke2/rke2.yaml /usr/local/bin/helm"

$SSH_RANCHER "sudo rm -f /etc/pki/trust/anchors/keycloak-ca.crt && sudo update-ca-certificates" 2>/dev/null || log_warn "Could not remove CA cert from VM"
$SSH_RANCHER "$KUBECTL -n cattle-system delete secret tls-ca" 2>/dev/null || log_warn "Could not delete tls-ca secret"

# Revert Helm to remove privateCA
$SSH_RANCHER "$HELM upgrade rancher rancher-prime/rancher -n cattle-system \
    --set hostname=rancher.home.zypp.fr \
    --set tls=external \
    --set replicas=1 \
    --set systemDefaultRegistry=registry.rancher.com \
    --set global.cattle.psp.enabled=false \
    --set startupProbe.failureThreshold=60" 2>/dev/null || log_warn "Could not revert Helm values"
log_info "CA and privateCA reverted"

# --- 3. Stop and remove containers on IDP VM ---
log_info "Stopping containers on IDP VM..."
SSH_CMD="ssh -o StrictHostKeyChecking=accept-new ${KC_VM_SSH_USER}@${KC_VM_HOST}"

$SSH_CMD "sudo podman stop ${KC_CONTAINER_NAME} ${LDAP_CONTAINER_NAME} 2>/dev/null || true"
$SSH_CMD "sudo podman rm ${KC_CONTAINER_NAME} ${LDAP_CONTAINER_NAME} 2>/dev/null || true"
$SSH_CMD "sudo podman network rm ${KC_PODMAN_NETWORK} 2>/dev/null || true"
$SSH_CMD "rm -rf /tmp/ldap-init /tmp/keycloak-certs 2>/dev/null || true"
log_info "Containers and network removed"

# --- 4. Remove DNS entries from Pi-hole ---
log_info "Removing DNS entries from Pi-hole..."
SSH_PIHOLE="ssh -o StrictHostKeyChecking=accept-new ${PIHOLE_SSH_USER}@${PIHOLE_HOST}"

CURRENT_HOSTS=$($SSH_PIHOLE "docker exec ${PIHOLE_CONTAINER} pihole-FTL --config dns.hosts" 2>/dev/null || echo "[]")

# Build list of hosts to remove
REMOVE_HOSTS=""
for entry in "${DNS_ENTRIES[@]}"; do
    ENTRY_HOST=$(echo "$entry" | awk '{print $2}')
    REMOVE_HOSTS+="${ENTRY_HOST};"
done

NEW_HOSTS_JSON=$(python3 -c "
import json, re

raw = '''${CURRENT_HOSTS}'''
inner = raw.strip('[] \n')
entries = [e.strip() for e in inner.split(',') if e.strip()]

remove = '${REMOVE_HOSTS}'.rstrip(';').split(';')
filtered = [e for e in entries if not any(h in e for h in remove)]

print(json.dumps(filtered))
")

echo "$NEW_HOSTS_JSON" | $SSH_PIHOLE "cat > /tmp/pihole-dns-update.json"
$SSH_PIHOLE "docker exec ${PIHOLE_CONTAINER} pihole-FTL --config dns.hosts \"\$(cat /tmp/pihole-dns-update.json)\" && rm -f /tmp/pihole-dns-update.json" 2>/dev/null || log_warn "Could not update Pi-hole DNS"
log_info "DNS entries removed"

# --- 5. Clean local files ---
rm -rf "$SCRIPT_DIR/.certs"
log_info "Local certificate files cleaned"

# --- 6. Optional: destroy VM ---
echo
log_info "Containers and configuration cleaned."
log_info "To also destroy the IDP VM, run:"
log_info "  cd /home/ju/workspace/TERRAFORM/KEYCLOAK && terraform destroy"

log_info "=== Cleanup complete ==="
