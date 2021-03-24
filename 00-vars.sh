# 01-os_preparation.sh
HOST_LIST_FILE=./hosts.list
STORAGE_TARGET="192.168.1.11"
DOCKER_VERSION="19.03"  # options [19.03|20.10]
_HTTP_PROXY="squid:3128"
_HTTPS_PROXY="squid:3128"
_NO_PROXY="127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,cattle-system.svc"

# 02-rke_deploy.sh
DOCKER_USER="rkedeploy"
RKE_VERSION="v1.2.6"
KUBERNETES_VERSION="v1.19.3-rancher1-1"
HELM_VERSION="3.5.3"
REGISTRY_AIRGAP="https://registry.zypp.lo/library" # To be set in case of airgap

# 03-rancher_install.sh
LB_MASTERS="api.apps.zypp.lo"
dom="apps.zypp.lo"
ext_dom="apps.office.zypp.fr"
