######################## LANGUAGE ################################
LANGUAGE="fr"

######################## HOSTS LIST ##############################
## Hosts to remote control in $HOST_LIST_FILE (one target per line)
HOST_LIST_FILE=./hosts.list

######################## IF AIRGAP SETUP #########################
## Airgap deployment
AIRGAP_DEPLOY="1"	# 1=airgap enabled / 0=airgap disabled
AIRGAP_REGISTRY_URL="registry.domain:5000"
AIRGAP_REGISTRY_CACERT=""
# Use insecure registry
AIRGAP_REGISTRY_INSECURE="1" # 1=insecure / 0=secured
# Optional user/password
AIRGAP_REGISTRY_USER=""
AIRGAP_REGISTRY_PASSWD=""

######################## IF PROXY SETUP ##########################
## Proxy settings (leave empty aka "" if you don't want proxy setting to trigger)
PROXY_ADDR="squid.zypp.lo"
PROXY_DEPLOY="0"	# 1=proxy enabled / 0=proxy disabled
_HTTP_PROXY="squid:3128"
_HTTPS_PROXY="squid:3128"
_NO_PROXY=127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,cattle-system.svc,.svc,.cluster.local,.zypp.lo
PROXY_CA_LOCATION="/etc/squid/ssl_cert/proxyCA.pem"

######################## DOCKER SETUP ############################
## Docker version to use (RHEL/CentOS)
DOCKER_VERSION="20.10"  # options [19.03|20.10]
## Docker user to be created on target hosts
DOCKER_USER="rkedeploy"
## Docker group to be joined by Docker user
DOCKER_GROUP="docker"	# 'dockerroot' for docker provided by RHEL

######################## REPOSITORIES ############################
## NOT-IMPLEMENTED - Repositories (REPO_MODE: 1=SUSE Manager / 2=RMT Server / 3="Do nothing, I'm good")
#REPO_MODE=1
REPO_SERVER="suma01"

######################## CHECK STORAGE NETWORK ###################
## Existing storage network host for basic check
STORAGE_TARGET="192.168.1.11"

######################## SELECT VERSIONS #########################
## K8S cluster, RKE and Helm versions to deploy
KUBERNETES_VERSION="v1.19.15-rancher1-2"
RKE_VERSION="v1.3.1"
HELM_VERSION="3.5.3"
CERTMGR_VERSION="v1.0.4"
RANCHER_VERSION="2.6.0"

######################## FQDNs & DOMAINs #########################
## Rancher Management Load balancer FQDN (redirect to RKE nodes hosting Rancher)
LB_RANCHER_FQDN="rancher.g2.office.zypp.fr"
