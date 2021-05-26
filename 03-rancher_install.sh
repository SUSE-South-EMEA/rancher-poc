#!/bin/bash

### Source variables
source ./00-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh

# Detect and source Proxy configuration
if [[ $PROXY_DEPLOY == 1 ]]
  then
  source /etc/profile.d/proxy.sh
fi

## CERT MANAGER INSTALL
COMMAND_CERTMGR_INSTALL() {
# Install the CustomResourceDefinition resources separately
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.2.0/cert-manager.crds.yaml
# Create the namespace for cert-manager
kubectl create namespace cert-manager
# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io
# Update your local Helm chart repository cache
helm repo update
# Install Cert-Manager
if [[ $PROXY_DEPLOY == 1 ]] 
then
  RANCHER_NO_PROXY=$(echo ${_NO_PROXY} |sed 's/,/\\,/g')
  echo
  echo "${bold}Cert Manager deployment with Proxy settings:"
  echo "- http_proxy=${_HTTP_PROXY}"
  echo "- https_proxy=${_HTTPS_PROXY}"
  echo "- no_proxy=${RANCHER_NO_PROXY}${normal}"
  echo
  helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version v1.2.0 \
    --set global.podSecurityPolicy.enabled=True \
    --set global.podSecurityPolicy.useAppArmor=False \
    --set http_proxy=http://${_HTTP_PROXY} \
    --set https_proxy=http://${_HTTPS_PROXY} \
    --set no_proxy=${RANCHER_NO_PROXY}
else
  echo "Cert Manager deployment"
  helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version v1.2.0 \
    --set global.podSecurityPolicy.enabled=True \
    --set global.podSecurityPolicy.useAppArmor=False
fi
  # Fix for K8S 1.19 - Select PSP profile (apparmor forced whereas desactivated)
kubectl annotate --overwrite psp cert-manager \
  seccomp.security.alpha.kubernetes.io/allowedProfileNames=docker/default,runtime/default
kubectl annotate --overwrite psp cert-manager-cainjector \
  seccomp.security.alpha.kubernetes.io/allowedProfileNames=docker/default,runtime/default
kubectl annotate --overwrite psp cert-manager-webhook \
  seccomp.security.alpha.kubernetes.io/allowedProfileNames=docker/default,runtime/default
echo "$TXT_VERIFY_CERTMGR_INSTALL"
read -p "#> kubectl get all --namespace cert-manager"
watch -d -c "kubectl get all -n cert-manager"
}

## TEST FQDN FOR RANCHER MGMT
COMMAND_TEST_FQDN() {
ping -c 1 ${LB_RANCHER_FQDN}
}

## INSTALL RANCHER MANAGEMENT
COMMAND_RANCHER_INSTALL() {
kubectl create namespace cattle-system
if [[ $PROXY_DEPLOY == 1 ]] 
then
  RANCHER_NO_PROXY=$(echo ${_NO_PROXY} |sed 's/,/\\,/g')
  echo
  echo "${bold}Rancher Management Server deployment with Proxy settings:"
  echo "- proxy=${_HTTP_PROXY}"
  echo "- no_proxy=${RANCHER_NO_PROXY}${normal}"
  echo
  helm install rancher rancher-stable/rancher \
    --namespace cattle-system \
    --set hostname=${LB_RANCHER_FQDN} \
    --set proxy=http://${_HTTP_PROXY} \
    --set no_proxy=${RANCHER_NO_PROXY}
else
  echo "Rancher Management Server deployment"
  helm install rancher rancher-stable/rancher \
    --namespace cattle-system \
    --set hostname=${LB_RANCHER_FQDN}
fi
echo "Verification de l'installation de rancher.app"
read -p "#> kubectl -n cattle-system get all"
watch -d -c "kubectl -n cattle-system get all"
}

## INIT ADMIN USER
COMMAND_INIT_ADMIN() {
kubectl -n cattle-system exec $(kubectl -n cattle-system get pods -l app=rancher | grep '1/1' | head -1 | awk '{ print $1 }') -- reset-password
}

question_yn "$DESC_CERTMGR_INSTALL" COMMAND_CERTMGR_INSTALL
question_yn "$DESC_TEST_FQDN" COMMAND_TEST_FQDN
question_yn "$DESC_RANCHER_INSTALL" COMMAND_RANCHER_INSTALL
question_yn "$DESC_INIT_ADMIN" COMMAND_INIT_ADMIN

echo
echo "Rancher Management server is available."
echo "${bold}Url :${normal} https://${LB_RANCHER_FQDN}"
echo
echo "-- $TXT_END --"
