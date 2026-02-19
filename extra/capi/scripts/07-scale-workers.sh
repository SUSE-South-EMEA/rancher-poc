#!/bin/bash
## ============================================================================
## 07-scale-workers.sh — Scale worker MachineDeployment up or down
## Usage: ./07-scale-workers.sh --replicas N [--config capi-homelab.sh]
## ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/00-common.sh" 2>/dev/null || true

# Parse arguments
REPLICAS=""
for arg in "$@"; do
    case "$arg" in
        --replicas=*) REPLICAS="${arg#*=}" ;;
        --replicas) shift_next_replicas=1 ;;
        --config=*) source "${arg#*=}" ;;
        *)
            [[ "${shift_next_replicas:-0}" == "1" ]] && { REPLICAS="$arg"; shift_next_replicas=0; }
            ;;
    esac
done
source "$SCRIPT_DIR/../configs/capi-vars.sh"

if ! declare -f log_info >/dev/null 2>&1; then
    log_info()  { echo "[$(date '+%H:%M:%S')] [INFO]  $*"; }
    log_error() { echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2; }
fi

if [[ -z "$REPLICAS" ]]; then
    echo "Usage: $0 --replicas N [--config=<file>]"
    echo
    echo "Examples:"
    echo "  $0 --replicas 2    # Scale to 2 workers"
    echo "  $0 --replicas 0    # Scale to zero (remove all workers)"
    exit 1
fi

mgmt_kubectl() {
    ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL $*"
}

# Check current state
current=$(mgmt_kubectl "get machinedeployment ${CAPI_WORKER_NAME} -n ${CAPI_NAMESPACE} -o jsonpath='{.spec.replicas}' 2>/dev/null" || echo "not found")

if [[ "$current" == "not found" ]]; then
    log_error "MachineDeployment '${CAPI_WORKER_NAME}' not found. Run 05-add-workers.sh first."
    exit 1
fi

log_info "=== Scaling workers: ${current} -> ${REPLICAS} ==="
echo

mgmt_kubectl "scale machinedeployment ${CAPI_WORKER_NAME} -n ${CAPI_NAMESPACE} --replicas=${REPLICAS}"

# Wait for scaling
timeout=600
interval=15
elapsed=0
while (( elapsed < timeout )); do
    ready=$(mgmt_kubectl "get machinedeployment ${CAPI_WORKER_NAME} -n ${CAPI_NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null" || echo "0")
    ready="${ready:-0}"
    updated=$(mgmt_kubectl "get machinedeployment ${CAPI_WORKER_NAME} -n ${CAPI_NAMESPACE} -o jsonpath='{.status.updatedReplicas}' 2>/dev/null" || echo "0")

    log_info "  Workers ready: ${ready}/${REPLICAS} (${elapsed}s)"

    if [[ "${ready}" == "${REPLICAS}" ]]; then
        echo
        log_info "Scaling complete: ${REPLICAS} worker(s) ready"
        break
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
done

if (( elapsed >= timeout )); then
    log_error "Timeout waiting for scaling after ${timeout}s"
fi

echo
log_info "Machine status:"
mgmt_kubectl "get machines -n ${CAPI_NAMESPACE} -o wide"
