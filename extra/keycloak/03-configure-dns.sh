#!/bin/bash
## ============================================================================
## 03-configure-dns.sh — Configure DNS entries in Pi-hole for IDP services
## ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/keycloak-vars.sh"
source "$SCRIPT_DIR/../../00-common.sh"

SSH_PIHOLE="ssh -o StrictHostKeyChecking=accept-new ${PIHOLE_SSH_USER}@${PIHOLE_HOST}"

log_info "=== Step 3: Configure DNS entries in Pi-hole ==="

# --- Get current DNS hosts from Pi-hole ---
log_info "Reading current Pi-hole DNS hosts..."
CURRENT_HOSTS=$($SSH_PIHOLE "docker exec ${PIHOLE_CONTAINER} pihole-FTL --config dns.hosts" 2>/dev/null || echo "[]")

log_info "Current hosts: $CURRENT_HOSTS"

# --- Build new hosts list ---
# Parse current hosts into array, add new entries if not present
NEW_HOSTS="$CURRENT_HOSTS"

for entry in "${DNS_ENTRIES[@]}"; do
    ENTRY_HOST=$(echo "$entry" | awk '{print $2}')
    if echo "$NEW_HOSTS" | grep -q "$ENTRY_HOST"; then
        log_info "DNS entry '$ENTRY_HOST' already exists, skipping"
    else
        log_info "Adding DNS entry: $entry"
        # Append to JSON array
        NEW_HOSTS=$(echo "$NEW_HOSTS" | sed "s/\]/, \"${entry}\"\]/")
        # Fix case where array was empty
        NEW_HOSTS=$(echo "$NEW_HOSTS" | sed 's/\[, /[/')
    fi
done

# --- Apply new DNS configuration ---
log_info "Applying DNS configuration..."
$SSH_PIHOLE "docker exec ${PIHOLE_CONTAINER} pihole-FTL --config dns.hosts '${NEW_HOSTS}'"

# --- Verify DNS resolution ---
log_info "Verifying DNS resolution..."
ERRORS=0
for entry in "${DNS_ENTRIES[@]}"; do
    ENTRY_IP=$(echo "$entry" | awk '{print $1}')
    ENTRY_HOST=$(echo "$entry" | awk '{print $2}')

    RESOLVED=$(dig +short "$ENTRY_HOST" @"${PIHOLE_HOST}" 2>/dev/null || echo "")
    if [[ "$RESOLVED" == "$ENTRY_IP" ]]; then
        log_info "  $ENTRY_HOST -> $RESOLVED (OK)"
    else
        log_warn "  $ENTRY_HOST -> '$RESOLVED' (expected $ENTRY_IP)"
        ERRORS=$((ERRORS + 1))
    fi
done

if [[ $ERRORS -eq 0 ]]; then
    log_info "All DNS entries configured and resolving correctly"
else
    log_warn "$ERRORS DNS entries did not resolve as expected (may need a few seconds to propagate)"
fi

log_info "=== Step 3 complete ==="
