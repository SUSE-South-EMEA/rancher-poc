######################## LANGUAGE ################################
LANGUAGE="fr"

######################## HOSTS LIST ##############################
## Hosts to remote control in $HOST_LIST_FILE (one target per line)
HOST_LIST_FILE=./hosts.list

######################## IF AIRGAP SETUP #########################
## Deploiement airgap: tapez 1 sinon 0
AIRGAP_DEPLOY="0" # 1=deploiement airgap / 0=deploiement non-airgap
AIRGAP_REGISTRY_URL="http://mon_registry:5000"
# Optional user/password
AIRGAP_REGISTRY_USER="toto"
AIRGAP_REGISTRY_PASSWD=""

######################## IF PROXY SETUP ##########################
## Proxy settings (leave empty aka "" if you don't want proxy setting to trigger)
PROXY_ADDR="squid.zypp.lo"
PROXY_DEPLOY="1" # 1=deploiement avec proxy / 0=deploiement sans proxy
_HTTP_PROXY="squid:3128"
_HTTPS_PROXY="squid:3128"
#_NO_PROXY="127.0.0.1,172.16.2.27,172.16.2.28,172.16.2.29,172.16.2.30,cattle-system.svc"
_NO_PROXY=127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,cattle-system.svc,.svc,.cluster.local,.zypp.lo
PROXY_CA_LOCATION="/etc/squid/ssl_cert/proxyCA.pem"

######################## DOCKER SETUP ############################
## Docker version to use (to be deprecated) 
DOCKER_VERSION="19.03"  # options [19.03|20.10]
## Docker user to be created on target hosts
DOCKER_USER="rkedeploy"
## Docker group to be joined by Docker user
DOCKER_GROUP="docker"	# 'dockerroot' for docker provided by RHEL

######################## REPOSITORIES ############################
## NON-FONCTIONNEL - Repositories (REPO_MODE: 1=SUSE Manager / 2=RMT Server / 3="Do nothing, I'm good")
#REPO_MODE=1
REPO_SERVER="suma01.zypp.lo"

######################## CHECK STORAGE NETWORK ###################
## Existing storage network host for basic check
STORAGE_TARGET="192.168.1.11"

######################## SELECT VERSIONS #########################
## K8S cluster, RKE and Helm versions to deploy
KUBERNETES_VERSION="v1.19.3-rancher1-1"
RKE_VERSION="v1.2.6"
HELM_VERSION="3.5.3"

######################## FQDNs & DOMAINs #########################
## Rancher Management Load balancer FQDN (redirect to RKE nodes hosting Rancher)
LB_RANCHER_FQDN="rancher.office.zypp.fr"
## Apps DNS domain (wildcard redirecting to RKE workers nodes hosting applications)
LB_APPS_DOMAIN="apps.office.zypp.fr"
