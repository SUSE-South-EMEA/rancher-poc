## ============================================================================
## example-auto.sh — Example configuration for automated deployment
##
## Usage: ./install.sh --auto --config configs/example-auto.sh
##
## Copy this file and adjust the values to match your environment.
## ============================================================================

## ---- Auto-mode settings ----
AUTO_MODE=1
AUTO_FAIL_FAST=1          # 0=continue on error, 1=stop on first error
PREFLIGHT_SSH=1           # 1=test SSH connectivity before starting
LOG_LEVEL="INFO"          # DEBUG, INFO, WARN, ERROR

## ---- Language ----
LANGUAGE="en"             # fr, en, it

## ---- Target hosts ----
HOST_LIST="node1.example.com,node2.example.com,node3.example.com"

## ---- SSH ----
SSH_USER="admin"          # Leave empty to use current user

## ---- Deployment mode ----
AIRGAP_DEPLOY="0"         # 0=internet, 1=airgap
PROXY_DEPLOY="0"          # 0=direct, 1=proxy
# Proxy settings (only if PROXY_DEPLOY=1)
_HTTP_PROXY="proxy:3128"
_HTTPS_PROXY="proxy:3128"
_NO_PROXY="127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,cattle-system.svc,.svc,.cluster.local"

## ---- Airgap settings (only if AIRGAP_DEPLOY=1) ----
AIRGAP_REGISTRY_URL="registry.example.com:5000"
AIRGAP_REGISTRY_CACERT=""
AIRGAP_REGISTRY_INSECURE="1"
AIRGAP_REGISTRY_USER=""
AIRGAP_REGISTRY_PASSWD=""
DOCKER_VERSION="20.10"

## ---- Software versions ----
HELM_VERSION="4.0.1"
RKE2_VERSION="v1.33.7+rke2r1"
CERTMGR_VERSION="v1.19.1"
RANCHER_VERSION="2.13.1"

## ---- Repositories ----
RKE2_REPO="https://prime.ribs.rancher.io/rke2"
HELM_ARCHIVE="https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz"
HELM_REPO_RANCHER="https://charts.rancher.com/server-charts/prime"
HELM_REPO_CERTMANAGER="https://charts.jetstack.io"

## ---- TLS ----
TLS_SOURCE="rancher"      # rancher, secret, external
PRIVATE_CA="0"

## ---- Kube-VIP (leave empty to disable) ----
RKE2_VIP_IP=""
RKE2_VIP_FQDN=""
RKE2_VIP_INTERFACE="eth0"

## ---- Rancher FQDN ----
LB_RANCHER_FQDN="rancher.example.com"
LB2_RANCHER_FQDN=""
