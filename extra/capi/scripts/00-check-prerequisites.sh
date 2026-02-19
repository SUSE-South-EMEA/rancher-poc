#!/bin/bash
## ============================================================================
## 00-check-prerequisites.sh — Verify CAPI infrastructure prerequisites
## Checks that Rancher Turtles, CAPI core, bootstrap/CP providers, and CAPHV
## are all running on the management cluster.
## ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source common functions
source "$REPO_ROOT/00-common.sh" 2>/dev/null || true

# Source CAPI config
CONFIG="${1:---config}"
if [[ "$CONFIG" == "--config" ]] && [[ -n "${2:-}" ]]; then
    source "$2"
fi
source "$SCRIPT_DIR/../configs/capi-vars.sh"

# Override log functions if 00-common.sh was not sourced
if ! declare -f log_info >/dev/null 2>&1; then
    log_info()  { echo "[$(date '+%H:%M:%S')] [INFO]  $*"; }
    log_error() { echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2; }
    log_warn()  { echo "[$(date '+%H:%M:%S')] [WARN]  $*" >&2; }
fi

# --- Helper: run kubectl on management cluster ---
mgmt_kubectl() {
    ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL $*"
}

errors=0

log_info "=== Checking CAPI prerequisites on ${RANCHER_HOST} ==="
echo

# 1. SSH connectivity
log_info "1. Testing SSH connectivity..."
if ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "hostname" >/dev/null 2>&1; then
    log_info "   SSH to ${RANCHER_HOST}: OK"
else
    log_error "   Cannot SSH to ${RANCHER_HOST}"
    exit 1
fi

# 2. Rancher Turtles (CAPI integration)
log_info "2. Checking Rancher Turtles (CAPI integration)..."
turtles_ns=$(mgmt_kubectl "get ns cattle-turtles-system --no-headers -o name 2>/dev/null" || true)
if [[ -n "$turtles_ns" ]]; then
    turtles_pods=$(mgmt_kubectl "get pods -n cattle-turtles-system --no-headers 2>/dev/null | grep -c Running" || echo "0")
    log_info "   Rancher Turtles: ${turtles_pods} pod(s) running"
else
    log_warn "   Rancher Turtles namespace not found (may be built into Rancher v2.13+)"
fi

# 3. CAPI Core
log_info "3. Checking CAPI Core provider..."
capi_pods=$(mgmt_kubectl "get pods -n cattle-capi-system --no-headers 2>/dev/null | grep -c Running" || echo "0")
if [[ "$capi_pods" -gt 0 ]]; then
    capi_version=$(mgmt_kubectl "get deploy -n cattle-capi-system capi-controller-manager -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null" | grep -oP 'v[\d.]+' || echo "unknown")
    log_info "   CAPI Core: ${capi_pods} pod(s) running (${capi_version})"
else
    log_error "   CAPI Core not running in cattle-capi-system"
    errors=$((errors + 1))
fi

# 4. RKE2 Bootstrap provider
log_info "4. Checking RKE2 Bootstrap provider..."
bootstrap_pods=$(mgmt_kubectl "get pods -n rke2-bootstrap-system --no-headers 2>/dev/null | grep -c Running" || echo "0")
if [[ "$bootstrap_pods" -gt 0 ]]; then
    log_info "   RKE2 Bootstrap: ${bootstrap_pods} pod(s) running"
else
    log_error "   RKE2 Bootstrap provider not running"
    errors=$((errors + 1))
fi

# 5. RKE2 ControlPlane provider
log_info "5. Checking RKE2 ControlPlane provider..."
cp_pods=$(mgmt_kubectl "get pods -n rke2-control-plane-system --no-headers 2>/dev/null | grep -c Running" || echo "0")
if [[ "$cp_pods" -gt 0 ]]; then
    log_info "   RKE2 ControlPlane: ${cp_pods} pod(s) running"
else
    log_error "   RKE2 ControlPlane provider not running"
    errors=$((errors + 1))
fi

# 6. CAPHV (Infrastructure provider)
log_info "6. Checking CAPHV infrastructure provider..."
caphv_pods=$(mgmt_kubectl "get pods -n ${CAPHV_NAMESPACE} --no-headers 2>/dev/null | grep -c Running" || echo "0")
if [[ "$caphv_pods" -gt 0 ]]; then
    caphv_image=$(mgmt_kubectl "get deploy -n ${CAPHV_NAMESPACE} caphv-controller-manager -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null" || echo "unknown")
    log_info "   CAPHV: ${caphv_pods} pod(s) running (${caphv_image})"
else
    log_warn "   CAPHV not running in ${CAPHV_NAMESPACE} — install with 01-install-caphv.sh"
    errors=$((errors + 1))
fi

# 7. ClusterResourceSet CRD
log_info "7. Checking ClusterResourceSet CRD..."
crs_crd=$(mgmt_kubectl "get crd clusterresourcesets.addons.cluster.x-k8s.io --no-headers -o name 2>/dev/null" || true)
if [[ -n "$crs_crd" ]]; then
    log_info "   ClusterResourceSet CRD: present"
else
    log_error "   ClusterResourceSet CRD not found — CAPI addons controller may not be installed"
    errors=$((errors + 1))
fi

# 8. Harvester CRDs
log_info "8. Checking Harvester CRDs..."
hv_crds=$(mgmt_kubectl "get crd -o name 2>/dev/null | grep -c 'infrastructure.cluster.x-k8s.io'" || echo "0")
log_info "   Harvester infrastructure CRDs: ${hv_crds}"

echo
if [[ $errors -gt 0 ]]; then
    log_error "Prerequisites check completed with ${errors} error(s)"
    exit 1
else
    log_info "All prerequisites OK"
fi
