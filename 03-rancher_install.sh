#!/bin/bash

### Source variables
source ./00-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh

# Detect and source Proxy configuration
if [[ $PROXY_DEPLOY == 1 ]] ; then
  source /etc/profile.d/proxy.sh
fi

## CERT MANAGER INSTALL
COMMAND_CERTMGR_INSTALL() {
if [[ $AIRGAP_DEPLOY == 1 ]]
then
  echo
  echo "${bold}Cert Manager airgap deployment${normal}"
  echo
  # Create the namespace for cert-manager
  kubectl create namespace cert-manager
  # Create the cert-manager CustomResourceDefinitions (CRDs)
  kubectl apply -f cert-manager/cert-manager-crd.yaml
  # Launch cert-manager
  kubectl apply -R -f ./cert-manager
elif [[ $PROXY_DEPLOY == 1 ]] && [[ $AIRGAP_DEPLOY != 1 ]]
then
  RANCHER_NO_PROXY=$(echo ${_NO_PROXY} |sed 's/,/\\,/g')
  echo
  echo "${bold}Cert Manager deployment with Proxy settings:"
  echo "- http_proxy=${_HTTP_PROXY}"
  echo "- https_proxy=${_HTTPS_PROXY}"
  echo "- no_proxy=${RANCHER_NO_PROXY}${normal}"
  echo
  # Add the Jetstack Helm repository
  helm repo add jetstack https://charts.jetstack.io
  # Update your local Helm chart repository cache
  helm repo update
  # Install Cert-Manager
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version ${CERTMGR_VERSION} \
    --set installCRDs=true \
    --set http_proxy=http://${_HTTP_PROXY} \
    --set https_proxy=http://${_HTTPS_PROXY} \
    --set no_proxy=${RANCHER_NO_PROXY}
else
  echo
  echo "Cert Manager deployment"
  echo
  # Add the Jetstack Helm repository
  helm repo add jetstack https://charts.jetstack.io
  # Update your local Helm chart repository cache
  helm repo update
  # Install Cert-Manager
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version ${CERTMGR_VERSION} \
    --set installCRDs=true
fi

echo "${TXT_MONITOR_CERTMGR_INSTALL:=Monitor Cert Manager installation}"
read -p "#> kubectl get all --namespace cert-manager"
watch -d -c "kubectl get all -n cert-manager"
}

## TEST FQDN FOR RANCHER MGMT
COMMAND_TEST_FQDN() {
ping -c 1 ${LB_RANCHER_FQDN}
}

## INSTALL RANCHER MANAGEMENT
COMMAND_RANCHER_INSTALL() {
### Install Rancher
kubectl create namespace cattle-system
# Private CA
if [[ $PRIVATE_CA == 1 ]] ; then
  if [[ $TLS_SOURCE == "rancher" ]] ; then echo "Cannot use PRIVATE_CA=1 with TLS_SOURCE=rancher. Exiting..." && exit 1 ; fi
  if [[ ! -f cacerts.pem ]] ; then echo "cacerts.pem not found. Exiting..." && exit 1 ; fi
  EXTRA_OPTS="--set privateCA=true"
  kubectl -n cattle-system create secret generic tls-ca --from-file=cacerts.pem=./cacerts.pem
fi
# User provided certificate
if [[ $TLS_SOURCE == "secret" ]] ; then
  if [[ ! -f tls.crt ]] || [[ ! -f tls.key ]] ; then echo "tls.crt or tls.key not found. Exiting..." && exit 1 ; fi
  EXTRA_OPTS="${EXTRA_OPTS} --set ingress.tls.source=secret"
  kubectl -n cattle-system create secret tls tls-rancher-ingress --cert=tls.crt --key=tls.key
elif [[ $TLS_SOURCE == "external" ]] ; then
  EXTRA_OPTS="${EXTRA_OPTS} --set tls=external"
else
  echo "Self-signed certificate will be generated using Cert-manager"
fi
# Airgap
if [[ $AIRGAP_DEPLOY == 1 ]]
then
  echo
  echo "${bold}Rancher Management Server airgap deployment${normal}"
  echo
  kubectl -n cattle-system apply -R -f ./rancher
# Proxy
elif [[ $PROXY_DEPLOY == 1 ]] && [[ $AIRGAP_DEPLOY != 1 ]]
then
  RANCHER_NO_PROXY=$(echo ${_NO_PROXY} |sed 's/,/\\,/g')
  echo
  echo "${bold}Rancher Management Server deployment with Proxy settings:"
  echo "- proxy=${_HTTP_PROXY}"
  echo "- noProxy=${RANCHER_NO_PROXY}${normal}"
  echo
  helm upgrade --install rancher rancher-prime/rancher \
    --namespace cattle-system \
    --set hostname=${LB_RANCHER_FQDN} \
    --version ${RANCHER_VERSION} \
    --set proxy=http://${_HTTP_PROXY} \
    --set noProxy=${RANCHER_NO_PROXY} ${EXTRA_OPTS}
# With Internet access
else
  echo "${bold}Rancher Management Server deployment${normal}"
  helm upgrade --install rancher rancher-prime/rancher \
    --namespace cattle-system \
    --set hostname=${LB_RANCHER_FQDN} \
    --version ${RANCHER_VERSION} ${EXTRA_OPTS}
fi
echo "${TXT_MONITOR_RANCHER_INSTALL:=Monitor Rancher resources deployment}"
read -p "#> kubectl -n cattle-system get all"
watch -d -c "kubectl -n cattle-system get all"
}

## INIT ADMIN USER
COMMAND_INIT_ADMIN() {
kubectl -n cattle-system exec $(kubectl -n cattle-system get pods -l app=rancher | grep '1/1' | head -1 | awk '{ print $1 }') -- reset-password
}

question_yn "${DESC_CERTMGR_INSTALL:=Install Cert Manager?}" COMMAND_CERTMGR_INSTALL
question_yn "${DESC_TEST_FQDN:=Test DNS name ${LB_RANCHER_FQDN}?}" COMMAND_TEST_FQDN
question_yn "${DESC_RANCHER_INSTALL:=Install Rancher Management Server (${LB_RANCHER_FQDN})?}" COMMAND_RANCHER_INSTALL
question_yn "${DESC_INIT_ADMIN:=Init admin user password?}" COMMAND_INIT_ADMIN

echo
echo "Rancher Management server is available."
echo "${bold}Url :${normal} https://${LB_RANCHER_FQDN}"
echo
echo "-- ${TXT_END:=END} --"
