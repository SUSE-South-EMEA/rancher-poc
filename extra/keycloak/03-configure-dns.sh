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

# --- Build new hosts list using Python (avoids JSON quoting issues) ---
NEW_ENTRIES=""
for entry in "${DNS_ENTRIES[@]}"; do
    NEW_ENTRIES+="${entry};"
done

NEW_HOSTS_JSON=$(python3 -c "
import json, re

raw = '''${CURRENT_HOSTS}'''
# pihole-FTL outputs: [ ip host, ip host, ... ] — not valid JSON
inner = raw.strip('[] \n')
entries = [e.strip() for e in inner.split(',') if e.strip()]

new_entries = '${NEW_ENTRIES}'.rstrip(';').split(';')
for ne in new_entries:
    ne = ne.strip()
    host = ne.split()[-1] if ne else ''
    if not any(host in e for e in entries):
        entries.append(ne)

print(json.dumps(entries))
")

log_info "Applying DNS configuration..."
# Write JSON to a temp file on rasp01, then apply (avoids shell quoting)
echo "$NEW_HOSTS_JSON" | $SSH_PIHOLE "cat > /tmp/pihole-dns-update.json"
$SSH_PIHOLE "docker exec ${PIHOLE_CONTAINER} pihole-FTL --config dns.hosts \"\$(cat /tmp/pihole-dns-update.json)\" && rm -f /tmp/pihole-dns-update.json"

# --- Verify DNS resolution ---
log_info "Verifying DNS resolution..."
sleep 2
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
