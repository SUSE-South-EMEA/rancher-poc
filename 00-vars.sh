# 01-os_preparation.sh
## Hosts to remote control in $HOST_LIST_FILE (one target per line)
HOST_LIST_FILE=./hosts.list
## NON-FONCTIONNEL - Repositories (REPO_MODE: 1=SUSE Manager / 2=RMT Server / 3="Do nothing, I'm good")
#REPO_MODE=1
#REPO_SERVER='suma01'
## Existing storage network host for basic check
STORAGE_TARGET="192.168.1.11"
## Docker version to use (to be deprecated) 
DOCKER_VERSION="19.03"  # options [19.03|20.10]
## Proxy settings (leave empty aka "" if you don't want proxy setting to trigger)
_HTTP_PROXY="squid:3128"
_HTTPS_PROXY="squid:3128"
_NO_PROXY="127.0.0.1,172.16.2.27,172.16.2.28,172.16.2.29,172.16.2.30,cattle-system.svc"

# 02-rke_deploy.sh
## Docker user to be created on target hosts
DOCKER_USER="rkedeploy"
## K8S cluster, RKE and Helm versions to deploy
KUBERNETES_VERSION="v1.19.3-rancher1-1"
RKE_VERSION="v1.2.6"
HELM_VERSION="3.5.3"
## Registry address in case of airgap scenario
REGISTRY_AIRGAP="https://registry.zypp.lo/library" # To be set in case of airgap

# 03-rancher_install.sh
## K8S Masters load balanced DNS name
LB_MASTERS="api.apps.zypp.lo"
## Apps private DNS domain
dom="apps.zypp.lo"
## Apps public DNS domain
ext_dom="apps.office.zypp.fr"
