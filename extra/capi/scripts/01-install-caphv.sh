#!/bin/bash
## ============================================================================
## 01-install-caphv.sh — Install or upgrade the CAPHV infrastructure provider
## ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/00-common.sh" 2>/dev/null || true

set -a
source "$SCRIPT_DIR/../configs/capi-vars.sh"
set +a

if ! declare -f log_info >/dev/null 2>&1; then
    log_info()  { echo "[$(date '+%H:%M:%S')] [INFO]  $*"; }
    log_error() { echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2; }
fi

mgmt_kubectl() {
    ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL $*"
}

log_info "=== Installing/Upgrading CAPHV on ${RANCHER_HOST} ==="
echo

# Render the CAPHV manifest with current image
MANIFEST="$SCRIPT_DIR/../provider/caphv-install.yaml"
if [[ ! -f "$MANIFEST" ]]; then
    log_error "CAPHV manifest not found: $MANIFEST"
    exit 1
fi

log_info "Rendering CAPHV manifest with image: ${CAPHV_IMAGE}"
rendered=$(envsubst < "$MANIFEST")

log_info "Applying CAPHV manifests..."
echo "$rendered" | ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL apply -f -"

log_info "Waiting for CAPHV controller to be ready..."
mgmt_kubectl "rollout status deploy/caphv-controller-manager -n ${CAPHV_NAMESPACE} --timeout=120s"

echo
log_info "CAPHV installation complete"
mgmt_kubectl "get pods -n ${CAPHV_NAMESPACE} -o wide"
