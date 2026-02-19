#!/bin/bash
## ============================================================================
## 02-create-prerequisites.sh — Create namespace, SSH keypair, identity secret
## ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/00-common.sh" 2>/dev/null || true

# Load config (--config <file> or default)
set -a
for arg in "$@"; do
    case "$arg" in
        --config=*) source "${arg#*=}" ;;
        --config) shift_next=1 ;;
        *) [[ "${shift_next:-0}" == "1" ]] && { source "$arg"; shift_next=0; } ;;
    esac
done
source "$SCRIPT_DIR/../configs/capi-vars.sh"
set +a

if ! declare -f log_info >/dev/null 2>&1; then
    log_info()  { echo "[$(date '+%H:%M:%S')] [INFO]  $*"; }
    log_error() { echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2; }
    log_warn()  { echo "[$(date '+%H:%M:%S')] [WARN]  $*" >&2; }
fi

mgmt_kubectl() {
    ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL $*"
}

log_info "=== Creating CAPI prerequisites on ${RANCHER_HOST} ==="
echo

# 1. Create namespace
log_info "1. Creating namespace '${CAPI_NAMESPACE}'..."
envsubst < "$SCRIPT_DIR/../manifests/00-namespace.yaml" \
    | ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL apply -f -"

# 2. Check/Create SSH keypair on Harvester
log_info "2. Checking SSH keypair '${CAPI_HV_SSH_KEYPAIR}'..."
ssh_ns=$(echo "$CAPI_HV_SSH_KEYPAIR" | cut -d/ -f1)
ssh_name=$(echo "$CAPI_HV_SSH_KEYPAIR" | cut -d/ -f2)

key_exists=$(mgmt_kubectl "get secret ${ssh_name} -n ${ssh_ns} --no-headers -o name 2>/dev/null" || true)
if [[ -n "$key_exists" ]]; then
    log_info "   SSH keypair '${ssh_name}' already exists in namespace '${ssh_ns}'"
else
    log_info "   Creating SSH keypair '${ssh_name}'..."
    # Generate a new SSH key pair
    tmpdir=$(mktemp -d)
    ssh-keygen -t ed25519 -f "${tmpdir}/capi-ssh" -N "" -q
    pub_key=$(cat "${tmpdir}/capi-ssh.pub")
    priv_key=$(cat "${tmpdir}/capi-ssh" | base64 -w0)
    pub_b64=$(echo -n "$pub_key" | base64 -w0)

    cat <<EOF | ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL apply -f -"
apiVersion: harvesterhci.io/v1beta1
kind: KeyPair
metadata:
  name: ${ssh_name}
  namespace: ${ssh_ns}
spec:
  publicKey: "${pub_key}"
EOF
    log_info "   SSH keypair created. Private key saved to: ${tmpdir}/capi-ssh"
    log_warn "   Save the private key — it won't be retrievable later!"
    rm -rf "$tmpdir"
fi

# 3. Create/update identity secret
log_info "3. Checking identity secret '${CAPI_IDENTITY_SECRET}'..."
secret_exists=$(mgmt_kubectl "get secret ${CAPI_IDENTITY_SECRET} -n ${CAPI_NAMESPACE} --no-headers -o name 2>/dev/null" || true)
if [[ -n "$secret_exists" ]]; then
    log_info "   Identity secret already exists"
else
    log_info "   Identity secret not found."
    log_info "   You need a Harvester kubeconfig. Get it from:"
    log_info "     https://172.16.3.100 > Advanced > Download Kubeconfig"
    log_info "   Then create the secret with:"
    log_info "     export HV_KUBECONFIG_B64=\$(base64 -w0 < harvester-kubeconfig.yaml)"
    log_info "     envsubst < manifests/01-identity-secret.yaml.tmpl | ssh ${RANCHER_SSH_USER}@${RANCHER_HOST} \"$KUBECTL apply -f -\""
    log_warn "   Cannot proceed without identity secret!"

    # Check if HV_KUBECONFIG_B64 is already set
    if [[ -n "${HV_KUBECONFIG_B64:-}" ]]; then
        log_info "   HV_KUBECONFIG_B64 is set, creating secret..."
        envsubst < "$SCRIPT_DIR/../manifests/01-identity-secret.yaml.tmpl" \
            | ssh "${RANCHER_SSH_USER}@${RANCHER_HOST}" "$KUBECTL apply -f -"
        log_info "   Identity secret created"
    fi
fi

echo
log_info "Prerequisites creation complete"
mgmt_kubectl "get ns ${CAPI_NAMESPACE}"
mgmt_kubectl "get secret -n ${CAPI_NAMESPACE} --no-headers"
