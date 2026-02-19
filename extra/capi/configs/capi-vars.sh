#!/bin/bash
## ============================================================================
## capi-vars.sh — Default variables for CAPI downstream cluster deployment
## Override values in a separate file (e.g. capi-homelab.sh) and pass via --config
## ============================================================================

# --- Cluster identity ---
CAPI_CLUSTER_NAME="${CAPI_CLUSTER_NAME:-downstream-rke2}"
CAPI_NAMESPACE="${CAPI_NAMESPACE:-capi-downstream}"
CAPI_K8S_VERSION="${CAPI_K8S_VERSION:-v1.31.6+rke2r1}"

# --- Control Plane ---
CAPI_CP_REPLICAS="${CAPI_CP_REPLICAS:-1}"
CAPI_CP_CPU="${CAPI_CP_CPU:-2}"
CAPI_CP_MEMORY="${CAPI_CP_MEMORY:-4Gi}"
CAPI_CP_DISK="${CAPI_CP_DISK:-40Gi}"

# --- Workers ---
CAPI_WORKER_REPLICAS="${CAPI_WORKER_REPLICAS:-1}"
CAPI_WORKER_CPU="${CAPI_WORKER_CPU:-1}"
CAPI_WORKER_MEMORY="${CAPI_WORKER_MEMORY:-4Gi}"
CAPI_WORKER_DISK="${CAPI_WORKER_DISK:-40Gi}"

# --- Network ---
CAPI_NETWORK="${CAPI_NETWORK:-default/production}"
CAPI_VM_ADDRESS="${CAPI_VM_ADDRESS:-172.16.3.40/16}"
CAPI_GATEWAY="${CAPI_GATEWAY:-172.16.0.1}"
CAPI_DNS_SERVERS="${CAPI_DNS_SERVERS:-172.16.3.6}"
CAPI_DNS_SEARCH="${CAPI_DNS_SEARCH:-home.lo}"

# --- Harvester ---
CAPI_HV_IMAGE="${CAPI_HV_IMAGE:-default/sles15-sp7-minimal-vm.x86_64-cloud-qu2.qcow2}"
CAPI_HV_SSH_KEYPAIR="${CAPI_HV_SSH_KEYPAIR:-default/capi-ssh-key}"
CAPI_HV_SSH_USER="${CAPI_HV_SSH_USER:-sles}"
CAPI_LB_IPAM="${CAPI_LB_IPAM:-dhcp}"

# --- CNI ---
CAPI_CNI="${CAPI_CNI:-calico}"

# --- Rancher Manager (management cluster) ---
RANCHER_HOST="${RANCHER_HOST:-172.16.3.20}"
RANCHER_SSH_USER="${RANCHER_SSH_USER:-rancher}"
KUBECTL="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"

# --- CAPHV Provider ---
CAPHV_IMAGE="${CAPHV_IMAGE:-gitea.home.zypp.fr/jniedergang/cluster-api-provider-harvester:v0.2.0-rc6}"
CAPHV_NAMESPACE="${CAPHV_NAMESPACE:-caphv-system}"

# --- CCM/CSI versions ---
HARVESTER_CCM_IMAGE="${HARVESTER_CCM_IMAGE:-rancher/harvester-cloud-provider:v0.2.5}"
HARVESTER_CSI_IMAGE="${HARVESTER_CSI_IMAGE:-rancher/harvester-csi-driver:v0.2.5}"
CSI_NODE_REGISTRAR_IMAGE="${CSI_NODE_REGISTRAR_IMAGE:-longhornio/csi-node-driver-registrar:v2.12.0}"
CSI_RESIZER_IMAGE="${CSI_RESIZER_IMAGE:-longhornio/csi-resizer:v1.12.0}"
CSI_PROVISIONER_IMAGE="${CSI_PROVISIONER_IMAGE:-longhornio/csi-provisioner:v5.1.0}"
CSI_ATTACHER_IMAGE="${CSI_ATTACHER_IMAGE:-longhornio/csi-attacher:v4.7.0}"

# --- Derived names (computed from CAPI_CLUSTER_NAME) ---
CAPI_HV_CLUSTER="${CAPI_CLUSTER_NAME}-hv"
CAPI_CP_NAME="${CAPI_CLUSTER_NAME}-cp"
CAPI_CP_MACHINE="${CAPI_CLUSTER_NAME}-cp-machine"
CAPI_WORKER_NAME="${CAPI_CLUSTER_NAME}-workers"
CAPI_WORKER_MACHINE="${CAPI_CLUSTER_NAME}-worker-machine"
CAPI_WORKER_CONFIG="${CAPI_CLUSTER_NAME}-worker-config"
CAPI_IDENTITY_SECRET="hv-identity-secret"
