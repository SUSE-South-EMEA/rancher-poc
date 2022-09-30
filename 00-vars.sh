######################## LANGUAGE ################################
LANGUAGE="fr"

######################## HOSTS LIST ##############################
## Nodes to be handled by the script / FQDN
## Used by RKE2 when generating TLS certs
HOST_LIST="ranch1.domain,ranch2.domain,ranch3.domain"

######################## IF AIRGAP SETUP #########################
## Airgap deployment
AIRGAP_DEPLOY="0"	# 1=airgap enabled / 0=airgap disabled
AIRGAP_REGISTRY_URL="registry.domain:5000"
AIRGAP_REGISTRY_CACERT=""
# Use insecure registry
AIRGAP_REGISTRY_INSECURE="1" # 1=insecure / 0=secured
# Optional user/password
AIRGAP_REGISTRY_USER=""
AIRGAP_REGISTRY_PASSWD=""

######################## IF PROXY SETUP ##########################
## Proxy settings
PROXY_DEPLOY="0"	# 1=proxy enabled / 0=proxy disabled
_HTTP_PROXY="admin:3128"
_HTTPS_PROXY="admin:3128"
_NO_PROXY=127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,cattle-system.svc,.svc,.cluster.local,.zypp.lo

######################## DOCKER SETUP (for Airgap)################
## Docker version to use (RHEL/CentOS)
DOCKER_VERSION="20.10"  # options [19.03|20.10]
## Docker user to be created on target hosts
DOCKER_USER="rkedeploy"
## Docker group to be joined by Docker user
DOCKER_GROUP="docker"	# 'dockerroot' for docker provided by RHEL

######################## REPOSITORIES ############################
REPO_SERVER="suma01"

######################## CHECK STORAGE NETWORK ###################
## Existing storage network host for basic check
STORAGE_TARGET="192.168.1.11"

######################## SELECT VERSIONS #########################
## RKE2, Rancher and Helm versions to deploy
HELM_VERSION="3.7.1"
RKE2_VERSION="v1.24.4+rke2r1"
CERTMGR_VERSION="v1.7.1"
RANCHER_VERSION="2.6.8"

######### RANCHER MGMT SERVER CERTIFICATE AND PRIVATE CA #########
## Rancher TLS configuration. Available options are [rancher,secret,external]
## - rancher  :  Self-signed certificate are generated by cert-manager (default)
## - secret   :  User provided certificate. Certificate (tls.crt) and key (tls.key) must be placed in working directory
## - external :  External TLS termination
TLS_SOURCE="rancher"
## Private CA (cacerts.pem must be placed in working directory)
PRIVATE_CA="0"

######################## FQDNs & DOMAINs #########################
## Rancher Management Load balancer FQDN (redirect to RKE nodes hosting Rancher)
LB_RANCHER_FQDN="rancher.domain"
