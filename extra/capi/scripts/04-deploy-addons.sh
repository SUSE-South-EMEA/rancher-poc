#!/bin/bash
## ============================================================================
## 04-deploy-addons.sh — Deploy CCM/CSI/Calico ClusterResourceSets
## Injects the cloud-config from CAPHV into the CCM ConfigMap, then applies
## all ClusterResourceSets.
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

log_info "=== Deploying CCM/CSI/Calico addons for '${CAPI_CLUSTER_NAME}' ==="
echo

# 1. Get cloud-config from CAPHV-generated secret
cloud_config_secret="${CAPI_CLUSTER_NAME}-hv-cloud-config"
log_info "1. Retrieving cloud-config from secret '${cloud_config_secret}'..."

CLOUD_CONFIG_B64=$(mgmt_kubectl "get secret ${cloud_config_secret} -n ${CAPI_NAMESPACE} -o jsonpath='{.data.cloud-config}' 2>/dev/null" || true)

if [[ -z "$CLOUD_CONFIG_B64" ]]; then
    log_error "Cloud config secret '${cloud_config_secret}' not found or empty."
    log_error "Ensure the cluster is provisioned (03-deploy-cluster.sh) and CAPHV has generated the config."
    exit 1
fi
export CLOUD_CONFIG_B64

log_info "   Cloud config retrieved (${#CLOUD_CONFIG_B64} chars base64)"

# 2. Apply CCM ConfigMap (with cloud-config injected)
log_info "2. Applying Harvester CCM addon ConfigMap..."
envsubst < "$SCRIPT_DIR/../manifests/addons/harvester-ccm-configmap.yaml" \
    | ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL apply -f -"

# 3. Apply CSI ConfigMap
log_info "3. Applying Harvester CSI addon ConfigMap..."
envsubst < "$SCRIPT_DIR/../manifests/addons/harvester-csi-configmap.yaml" \
    | ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL apply -f -"

# 4. Apply Calico config ConfigMap
log_info "4. Applying Calico Helm config ConfigMap..."
envsubst < "$SCRIPT_DIR/../manifests/addons/calico-helm-config.yaml" \
    | ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL apply -f -"

# 5. Apply ClusterResourceSets
log_info "5. Applying ClusterResourceSets..."
envsubst < "$SCRIPT_DIR/../manifests/addons/cluster-resource-set.yaml" \
    | ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL apply -f -"

echo
log_info "Addon manifests applied. ClusterResourceSets will push resources to matching clusters."
echo
log_info "ClusterResourceSet status:"
mgmt_kubectl "get clusterresourceset -n ${CAPI_NAMESPACE}"

# 6. Verify on downstream (if reachable)
echo
log_info "Attempting to verify addons on downstream cluster..."

# Get downstream kubeconfig
kubeconfig_b64=$(mgmt_kubectl "get secret ${CAPI_CLUSTER_NAME}-kubeconfig -n ${CAPI_NAMESPACE} -o jsonpath='{.data.value}' 2>/dev/null" || true)

if [[ -n "$kubeconfig_b64" ]]; then
    tmpkubeconfig=$(mktemp)
    echo "$kubeconfig_b64" | base64 -d > "$tmpkubeconfig"

    log_info "Downstream pods (kube-system):"
    kubectl --kubeconfig "$tmpkubeconfig" get pods -n kube-system --no-headers 2>/dev/null \
        | grep -E '(harvester|csi|ccm|cloud-provider|ingress)' || log_warn "   No CCM/CSI pods found yet (may take a few minutes)"

    rm -f "$tmpkubeconfig"
else
    log_warn "   Could not retrieve downstream kubeconfig"
fi
