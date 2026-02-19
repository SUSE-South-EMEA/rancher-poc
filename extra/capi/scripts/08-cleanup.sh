#!/bin/bash
## ============================================================================
## 08-cleanup.sh — Delete the CAPI downstream cluster and all resources
## WARNING: This will delete all VMs, volumes, and secrets for the cluster.
## ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/00-common.sh" 2>/dev/null || true

for arg in "$@"; do
    case "$arg" in
        --config=*) source "${arg#*=}" ;;
        --force) FORCE=1 ;;
    esac
done
source "$SCRIPT_DIR/../configs/capi-vars.sh"

if ! declare -f log_info >/dev/null 2>&1; then
    log_info()  { echo "[$(date '+%H:%M:%S')] [INFO]  $*"; }
    log_error() { echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2; }
    log_warn()  { echo "[$(date '+%H:%M:%S')] [WARN]  $*" >&2; }
fi

mgmt_kubectl() {
    ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL $*"
}

log_warn "=== CLEANUP: Deleting cluster '${CAPI_CLUSTER_NAME}' ==="
echo
log_warn "This will delete:"
log_warn "  - All VMs on Harvester for this cluster"
log_warn "  - All PVCs/volumes for this cluster"
log_warn "  - The Cluster, MachineDeployment, ControlPlane resources"
log_warn "  - ClusterResourceSets in namespace '${CAPI_NAMESPACE}'"
log_warn "  - The namespace '${CAPI_NAMESPACE}'"
echo

if [[ "${FORCE:-0}" != "1" ]]; then
    read -p "Are you sure? Type 'yes' to confirm: " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Aborted."
        exit 0
    fi
fi

# 1. Scale workers to 0 first (graceful)
log_info "1. Scaling workers to 0..."
mgmt_kubectl "scale machinedeployment ${CAPI_WORKER_NAME} -n ${CAPI_NAMESPACE} --replicas=0 2>/dev/null" || true
sleep 5

# 2. Delete MachineDeployment
log_info "2. Deleting MachineDeployment..."
mgmt_kubectl "delete machinedeployment ${CAPI_WORKER_NAME} -n ${CAPI_NAMESPACE} --ignore-not-found 2>/dev/null" || true

# 3. Delete ClusterResourceSets
log_info "3. Deleting ClusterResourceSets..."
mgmt_kubectl "delete clusterresourceset -n ${CAPI_NAMESPACE} --all 2>/dev/null" || true

# 4. Delete the Cluster (this cascades to ControlPlane, Machines, InfraCluster)
log_info "4. Deleting CAPI Cluster (cascading)..."
mgmt_kubectl "delete clusters.cluster.x-k8s.io ${CAPI_CLUSTER_NAME} -n ${CAPI_NAMESPACE} --timeout=300s 2>/dev/null" || true

# 5. Wait for machines to be deleted
log_info "5. Waiting for machines to be cleaned up..."
timeout=300
elapsed=0
while (( elapsed < timeout )); do
    machines=$(mgmt_kubectl "get machines -n ${CAPI_NAMESPACE} --no-headers 2>/dev/null | wc -l" || echo "0")
    if [[ "$machines" == "0" ]]; then
        log_info "   All machines deleted"
        break
    fi
    log_info "   ${machines} machine(s) still deleting... (${elapsed}s)"
    sleep 10
    elapsed=$((elapsed + 10))
done

# 6. Clean up remaining resources
log_info "6. Cleaning up ConfigMaps and remaining resources..."
mgmt_kubectl "delete configmap -n ${CAPI_NAMESPACE} --all 2>/dev/null" || true
mgmt_kubectl "delete secret -n ${CAPI_NAMESPACE} --field-selector type!=kubernetes.io/service-account-token --all 2>/dev/null" || true

# 7. Delete namespace
log_info "7. Deleting namespace '${CAPI_NAMESPACE}'..."
mgmt_kubectl "delete ns ${CAPI_NAMESPACE} --timeout=120s 2>/dev/null" || true

echo
log_info "Cleanup complete"
log_info "Verify on Harvester that VMs and volumes have been deleted"
