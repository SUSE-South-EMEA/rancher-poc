#!/bin/bash
## ============================================================================
## 05-add-workers.sh — Deploy MachineDeployment for worker nodes
## ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/00-common.sh" 2>/dev/null || true

for arg in "$@"; do
    case "$arg" in
        --config=*) source "${arg#*=}" ;;
    esac
done
source "$SCRIPT_DIR/../configs/capi-vars.sh"

if ! declare -f log_info >/dev/null 2>&1; then
    log_info()  { echo "[$(date '+%H:%M:%S')] [INFO]  $*"; }
    log_error() { echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2; }
fi

mgmt_kubectl() {
    ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL $*"
}

log_info "=== Adding worker nodes to '${CAPI_CLUSTER_NAME}' ==="
echo

# Verify cluster is provisioned
phase=$(mgmt_kubectl "get clusters.cluster.x-k8s.io ${CAPI_CLUSTER_NAME} -n ${CAPI_NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null" || echo "")
if [[ "$phase" != "Provisioned" ]]; then
    log_error "Cluster '${CAPI_CLUSTER_NAME}' is not Provisioned (phase: ${phase:-NotFound})"
    log_error "Run 03-deploy-cluster.sh first"
    exit 1
fi

# Apply worker manifests
log_info "Applying worker manifests (replicas: ${CAPI_WORKER_REPLICAS})..."
envsubst < "$SCRIPT_DIR/../manifests/04-workers.yaml" \
    | ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL apply -f -"

echo
log_info "MachineDeployment applied. Waiting for workers to provision..."

# Wait for workers
timeout=600
interval=15
elapsed=0
while (( elapsed < timeout )); do
    ready=$(mgmt_kubectl "get machinedeployment ${CAPI_WORKER_NAME} -n ${CAPI_NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null" || echo "0")
    desired=$(mgmt_kubectl "get machinedeployment ${CAPI_WORKER_NAME} -n ${CAPI_NAMESPACE} -o jsonpath='{.spec.replicas}' 2>/dev/null" || echo "${CAPI_WORKER_REPLICAS}")

    log_info "  Workers: ${ready:-0}/${desired} ready (${elapsed}s)"

    if [[ "${ready:-0}" == "${desired}" ]] && [[ "${ready:-0}" != "0" ]]; then
        echo
        log_info "All ${desired} worker(s) are ready!"
        break
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
done

if (( elapsed >= timeout )); then
    log_error "Timeout waiting for workers after ${timeout}s"
    mgmt_kubectl "get machinedeployment -n ${CAPI_NAMESPACE}"
    mgmt_kubectl "get machines -n ${CAPI_NAMESPACE} -o wide"
    exit 1
fi

echo
log_info "Cluster nodes:"
mgmt_kubectl "get machines -n ${CAPI_NAMESPACE} -o wide"
