#!/bin/bash
## ============================================================================
## 02-deploy-keycloak.sh — Deploy Keycloak container on IDP VM
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
KC_ADMIN_PASSWORD=$(vault_get "$VAULT_KC_SECRET_PATH" admin_password)
if [[ -z "$KC_ADMIN_PASSWORD" ]]; then
    log_error "Could not retrieve admin_password from Vault ($VAULT_KC_SECRET_PATH)"
    exit 1
fi

SSH_CMD="ssh -o StrictHostKeyChecking=accept-new ${KC_VM_SSH_USER}@${KC_VM_HOST}"

log_info "=== Step 2: Deploy Keycloak on ${KC_VM_HOST} ==="

# --- Generate self-signed certificate ---
log_info "Generating self-signed TLS certificate for ${KC_FQDN}..."
$SSH_CMD "mkdir -p /tmp/keycloak-certs"
$SSH_CMD "openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /tmp/keycloak-certs/tls.key \
    -out /tmp/keycloak-certs/tls.crt \
    -days 365 \
    -subj '/CN=${KC_FQDN}' \
    -addext 'subjectAltName=DNS:${KC_FQDN},DNS:keycloak.home.lo,DNS:idp.home.lo,IP:${KC_VM_HOST}'"

# Copy the cert locally for later use (trust store, etc.)
mkdir -p "$SCRIPT_DIR/.certs"
$SSH_CMD "cat /tmp/keycloak-certs/tls.crt" > "$SCRIPT_DIR/.certs/keycloak-ca.crt"
log_info "Self-signed certificate saved to $SCRIPT_DIR/.certs/keycloak-ca.crt"

# --- Ensure Podman network exists ---
$SSH_CMD "sudo podman network create ${KC_PODMAN_NETWORK} 2>/dev/null || true"

# --- Deploy Keycloak container ---
log_info "Deploying Keycloak container..."
$SSH_CMD "sudo podman rm -f ${KC_CONTAINER_NAME} 2>/dev/null || true"

$SSH_CMD "sudo podman run -d \
    --name ${KC_CONTAINER_NAME} \
    --network ${KC_PODMAN_NETWORK} \
    -p 0.0.0.0:${KC_HTTPS_PORT}:8443 \
    -p 127.0.0.1:9000:9000 \
    -e KC_BOOTSTRAP_ADMIN_USERNAME='${KC_ADMIN_USER}' \
    -e KC_BOOTSTRAP_ADMIN_PASSWORD='${KC_ADMIN_PASSWORD}' \
    -e KC_HTTPS_CERTIFICATE_FILE=/opt/keycloak/conf/tls.crt \
    -e KC_HTTPS_CERTIFICATE_KEY_FILE=/opt/keycloak/conf/tls.key \
    -e KC_HOSTNAME='https://${KC_FQDN}:${KC_HTTPS_PORT}' \
    -e KC_HEALTH_ENABLED=true \
    -e KC_HTTP_ENABLED=false \
    -v /tmp/keycloak-certs/tls.crt:/opt/keycloak/conf/tls.crt:Z \
    -v /tmp/keycloak-certs/tls.key:/opt/keycloak/conf/tls.key:Z \
    ${KC_IMAGE} start"

# --- Wait for Keycloak to be ready ---
log_info "Waiting for Keycloak to be ready (may take 30-60 seconds)..."
for i in $(seq 1 90); do
    HEALTH=$($SSH_CMD "curl -sk https://127.0.0.1:${KC_HTTPS_PORT}/realms/master 2>/dev/null" || echo "")
    if echo "$HEALTH" | grep -q '"realm":"master"'; then
        log_info "Keycloak is ready"
        break
    fi
    if [[ $i -eq 90 ]]; then
        log_error "Keycloak did not become ready in 90 seconds"
        $SSH_CMD "sudo podman logs --tail 50 ${KC_CONTAINER_NAME}" || true
        exit 1
    fi
    sleep 2
done

# --- Verify ---
log_info "Verifying Keycloak HTTPS endpoint..."
MASTER_REALM=$($SSH_CMD "curl -sk https://127.0.0.1:${KC_HTTPS_PORT}/realms/master 2>/dev/null" || echo "")
if echo "$MASTER_REALM" | grep -q '"realm":"master"'; then
    log_info "Keycloak master realm accessible via HTTPS"
else
    log_warn "Could not verify master realm endpoint"
fi

log_info "Keycloak UI: https://${KC_FQDN}:${KC_HTTPS_PORT}"
log_info "Admin console: https://${KC_FQDN}:${KC_HTTPS_PORT}/admin"

log_info "=== Step 2 complete ==="
