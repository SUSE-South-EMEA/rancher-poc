#!/bin/bash
## ============================================================================
## 06-verify-cluster.sh — Verify the full CAPI cluster stack
## Checks cluster status, nodes, CCM, CSI, ingress, and Rancher import.
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
    log_warn()  { echo "[$(date '+%H:%M:%S')] [WARN]  $*" >&2; }
fi

mgmt_kubectl() {
    ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL $*"
}

errors=0
warnings=0

log_info "=== Verifying CAPI cluster '${CAPI_CLUSTER_NAME}' ==="
echo

# 1. Cluster status
log_info "1. CAPI Cluster status"
phase=$(mgmt_kubectl "get clusters.cluster.x-k8s.io ${CAPI_CLUSTER_NAME} -n ${CAPI_NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null" || echo "NotFound")
cp_ready=$(mgmt_kubectl "get clusters.cluster.x-k8s.io ${CAPI_CLUSTER_NAME} -n ${CAPI_NAMESPACE} -o jsonpath='{.status.controlPlaneReady}' 2>/dev/null" || echo "false")
infra_ready=$(mgmt_kubectl "get clusters.cluster.x-k8s.io ${CAPI_CLUSTER_NAME} -n ${CAPI_NAMESPACE} -o jsonpath='{.status.infrastructureReady}' 2>/dev/null" || echo "false")

if [[ "$phase" == "Provisioned" ]]; then
    log_info "   Phase: Provisioned | CP Ready: ${cp_ready} | Infra Ready: ${infra_ready}"
else
    log_error "   Phase: ${phase} (expected: Provisioned)"
    errors=$((errors + 1))
fi

# 2. Machines
log_info "2. Machines"
mgmt_kubectl "get machines -n ${CAPI_NAMESPACE} -o wide 2>/dev/null" || log_warn "   No machines found"

# 3. MachineDeployment (workers)
log_info "3. MachineDeployment (workers)"
md_exists=$(mgmt_kubectl "get machinedeployment ${CAPI_WORKER_NAME} -n ${CAPI_NAMESPACE} --no-headers -o name 2>/dev/null" || true)
if [[ -n "$md_exists" ]]; then
    mgmt_kubectl "get machinedeployment -n ${CAPI_NAMESPACE} -o wide"
else
    log_warn "   No MachineDeployment found (workers not yet added)"
    warnings=$((warnings + 1))
fi

# 4. ClusterResourceSets
log_info "4. ClusterResourceSets"
crs_count=$(mgmt_kubectl "get clusterresourceset -n ${CAPI_NAMESPACE} --no-headers 2>/dev/null | wc -l" || echo "0")
if [[ "$crs_count" -gt 0 ]]; then
    mgmt_kubectl "get clusterresourceset -n ${CAPI_NAMESPACE}"
else
    log_warn "   No ClusterResourceSets found (addons not yet deployed)"
    warnings=$((warnings + 1))
fi

# 5. Downstream cluster verification
log_info "5. Downstream cluster connectivity"
kubeconfig_b64=$(mgmt_kubectl "get secret ${CAPI_CLUSTER_NAME}-kubeconfig -n ${CAPI_NAMESPACE} -o jsonpath='{.data.value}' 2>/dev/null" || true)

if [[ -z "$kubeconfig_b64" ]]; then
    log_error "   Cannot retrieve downstream kubeconfig"
    errors=$((errors + 1))
else
    tmpkubeconfig=$(mktemp)
    echo "$kubeconfig_b64" | base64 -d > "$tmpkubeconfig"

    # Test connectivity
    if kubectl --kubeconfig "$tmpkubeconfig" get nodes --no-headers >/dev/null 2>&1; then
        echo
        log_info "   Nodes:"
        kubectl --kubeconfig "$tmpkubeconfig" get nodes -o wide

        echo
        log_info "   CCM pods:"
        kubectl --kubeconfig "$tmpkubeconfig" get pods -n kube-system -l app.kubernetes.io/name=harvester-cloud-provider --no-headers 2>/dev/null \
            || log_warn "   No CCM pods found"

        echo
        log_info "   CSI pods:"
        kubectl --kubeconfig "$tmpkubeconfig" get pods -n kube-system -l app=harvester-csi-plugin --no-headers 2>/dev/null \
            || log_warn "   No CSI plugin pods found"
        kubectl --kubeconfig "$tmpkubeconfig" get pods -n kube-system -l app=csi-controller --no-headers 2>/dev/null \
            || log_warn "   No CSI controller pods found"

        echo
        log_info "   Ingress pods:"
        kubectl --kubeconfig "$tmpkubeconfig" get pods -n kube-system -l app.kubernetes.io/name=rke2-ingress-nginx --no-headers 2>/dev/null \
            || log_warn "   No ingress pods found"

        echo
        log_info "   StorageClass:"
        kubectl --kubeconfig "$tmpkubeconfig" get storageclass 2>/dev/null || true
    else
        log_warn "   Cannot reach downstream cluster API (VM may not be reachable from this host)"
        warnings=$((warnings + 1))
    fi

    rm -f "$tmpkubeconfig"
fi

# 6. Rancher auto-import
log_info "6. Rancher cluster import"
rancher_clusters=$(mgmt_kubectl "get clusters.management.cattle.io -o jsonpath='{range .items[*]}{.metadata.name} {.spec.displayName}{\"\\n\"}{end}' 2>/dev/null" || true)
if echo "$rancher_clusters" | grep -q "${CAPI_CLUSTER_NAME}"; then
    log_info "   Cluster '${CAPI_CLUSTER_NAME}' visible in Rancher"
else
    log_warn "   Cluster '${CAPI_CLUSTER_NAME}' not yet visible in Rancher (auto-import may take a few minutes)"
    warnings=$((warnings + 1))
fi

# Summary
echo
echo "========================================"
if [[ $errors -gt 0 ]]; then
    log_error "Verification completed: ${errors} error(s), ${warnings} warning(s)"
    exit 1
elif [[ $warnings -gt 0 ]]; then
    log_warn "Verification completed: ${warnings} warning(s)"
else
    log_info "Verification completed: all checks passed"
fi
