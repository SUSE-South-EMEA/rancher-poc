#!/bin/bash
## ============================================================================
## 03-deploy-cluster.sh — Deploy CAPI downstream cluster (Cluster + CP)
## Applies the Cluster, HarvesterCluster, RKE2ControlPlane, and
## HarvesterMachineTemplate manifests.
## ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/00-common.sh" 2>/dev/null || true

set -a
for arg in "$@"; do
    case "$arg" in
        --config=*) source "${arg#*=}" ;;
    esac
done
source "$SCRIPT_DIR/../configs/capi-vars.sh"
set +a

if ! declare -f log_info >/dev/null 2>&1; then
    log_info()  { echo "[$(date '+%H:%M:%S')] [INFO]  $*"; }
    log_error() { echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2; }
fi

mgmt_kubectl() {
    ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL $*"
}

log_info "=== Deploying CAPI cluster '${CAPI_CLUSTER_NAME}' ==="
echo

# Verify prerequisites
log_info "Verifying identity secret..."
secret_check=$(mgmt_kubectl "get secret ${CAPI_IDENTITY_SECRET} -n ${CAPI_NAMESPACE} --no-headers -o name 2>/dev/null" || true)
if [[ -z "$secret_check" ]]; then
    log_error "Identity secret '${CAPI_IDENTITY_SECRET}' not found in namespace '${CAPI_NAMESPACE}'"
    log_error "Run 02-create-prerequisites.sh first"
    exit 1
fi

# Apply Cluster + HarvesterCluster
log_info "Applying Cluster and HarvesterCluster..."
envsubst < "$SCRIPT_DIR/../manifests/02-cluster.yaml" \
    | ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL apply -f -"

# Apply RKE2ControlPlane + HarvesterMachineTemplate
log_info "Applying RKE2ControlPlane and machine template..."
envsubst < "$SCRIPT_DIR/../manifests/03-control-plane.yaml" \
    | ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL apply -f -"

echo
log_info "Cluster resources applied. Waiting for provisioning..."

# Wait for infrastructure to be ready
timeout=600
interval=15
elapsed=0
while (( elapsed < timeout )); do
    phase=$(mgmt_kubectl "get clusters.cluster.x-k8s.io ${CAPI_CLUSTER_NAME} -n ${CAPI_NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null" || echo "")
    infra_ready=$(mgmt_kubectl "get clusters.cluster.x-k8s.io ${CAPI_CLUSTER_NAME} -n ${CAPI_NAMESPACE} -o jsonpath='{.status.infrastructureReady}' 2>/dev/null" || echo "false")
    cp_ready=$(mgmt_kubectl "get clusters.cluster.x-k8s.io ${CAPI_CLUSTER_NAME} -n ${CAPI_NAMESPACE} -o jsonpath='{.status.controlPlaneReady}' 2>/dev/null" || echo "false")

    log_info "  Phase: ${phase:-Pending} | Infra: ${infra_ready} | CP: ${cp_ready} (${elapsed}s)"

    if [[ "$phase" == "Provisioned" ]] && [[ "$cp_ready" == "true" ]]; then
        echo
        log_info "Cluster '${CAPI_CLUSTER_NAME}' is Provisioned and ControlPlane is ready!"
        break
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
done

if (( elapsed >= timeout )); then
    log_error "Timeout waiting for cluster provisioning after ${timeout}s"
    mgmt_kubectl "get clusters.cluster.x-k8s.io ${CAPI_CLUSTER_NAME} -n ${CAPI_NAMESPACE} -o yaml"
    exit 1
fi

# Show cluster status
echo
log_info "Cluster status:"
mgmt_kubectl "get clusters.cluster.x-k8s.io -n ${CAPI_NAMESPACE}"
mgmt_kubectl "get machines -n ${CAPI_NAMESPACE} -o wide"

# Get control plane endpoint
cp_endpoint=$(mgmt_kubectl "get clusters.cluster.x-k8s.io ${CAPI_CLUSTER_NAME} -n ${CAPI_NAMESPACE} -o jsonpath='{.spec.controlPlaneEndpoint.host}'" || echo "unknown")
log_info "Control plane endpoint: ${cp_endpoint}:6443"
