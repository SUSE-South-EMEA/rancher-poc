#!/bin/bash

### Source variables
source ./01-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh
init_common

# Detect and source Proxy configuration
if [[ $PROXY_DEPLOY == 1 ]] ; then
  source /etc/profile.d/proxy.sh
fi


## INSTALL HELM
COMMAND_HELM_INSTALL() {
if [[ $AIRGAP_DEPLOY == 1 ]]; then
  tar zxvf helm-v${HELM_VERSION}-linux-amd64.tar.gz
  sudo mv linux-amd64/helm /usr/local/bin/helm
  rm -rf linux-amd64/
else
  curl -O ${HELM_ARCHIVE}
  tar zxvf helm-v${HELM_VERSION}-linux-amd64.tar.gz
  sudo mv linux-amd64/helm /usr/local/bin/helm
  rm -rf linux-amd64/
  rm helm-v${HELM_VERSION}-linux-amd64.tar.gz
fi
echo -e "\nHelm installed.\n $(helm version)"
}


## REPOS HELM
COMMAND_HELM_REPOS() {
if [[ $AIRGAP_DEPLOY == 1 ]]; then
  echo "${TXT_HELM_REPOS:=Helm charts must be previously synced with 00-prepare-airgap.sh and placed in current directory.}"
else
  helm repo add rancher ${HELM_REPO_RANCHER}
  helm repo list
fi
}


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
  helm repo add jetstack ${HELM_REPO_CERTMANAGER}
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
  helm repo add jetstack ${HELM_REPO_CERTMANAGER}
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
if [[ "${AUTO_MODE:-0}" == "1" ]]; then
    wait_for_pods "cert-manager" 300
else
    read -p "#> kubectl get all --namespace cert-manager"
    watch -d -c "kubectl get all -n cert-manager"
fi
}

## TEST FQDN FOR RANCHER MGMT
COMMAND_TEST_FQDN() {
ping -c 1 ${LB_RANCHER_FQDN}
}

## INSTALL RANCHER MANAGEMENT
COMMAND_RANCHER_INSTALL() {
### Wait for ingress controller webhook to be ready (avoids "no endpoints available" error)
log_info "Waiting for ingress controller admission webhook to be ready..."
local webhook_timeout=120
local webhook_elapsed=0
while (( webhook_elapsed < webhook_timeout )); do
    if kubectl get endpoints -n kube-system rke2-ingress-nginx-controller-admission -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -q .; then
        log_info "Ingress controller webhook is ready"
        break
    fi
    log_debug "Ingress webhook not ready yet (elapsed: ${webhook_elapsed}s)..."
    sleep 5
    webhook_elapsed=$((webhook_elapsed + 5))
done
if (( webhook_elapsed >= webhook_timeout )); then
    log_warn "Ingress webhook not ready after ${webhook_timeout}s, proceeding anyway..."
fi

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
  helm repo update
  helm upgrade --install rancher rancher/rancher \
    --namespace cattle-system \
    --set hostname=${LB_RANCHER_FQDN} \
    --set global.cattle.psp.enabled=false \
    --version ${RANCHER_VERSION} \
    --set proxy=http://${_HTTP_PROXY} \
    --set noProxy=${RANCHER_NO_PROXY} ${EXTRA_OPTS}
# With Internet access
else
  echo "${bold}Rancher Management Server deployment${normal}"
  helm repo update
  helm upgrade --install rancher rancher/rancher \
    --namespace cattle-system \
    --set hostname=${LB_RANCHER_FQDN} \
    --set global.cattle.psp.enabled=false \
    --version ${RANCHER_VERSION} ${EXTRA_OPTS}
fi
echo "${TXT_MONITOR_RANCHER_INSTALL:=Monitor Rancher resources deployment}"
if [[ "${AUTO_MODE:-0}" == "1" ]]; then
    wait_for_pods "cattle-system" 600
else
    read -p "#> kubectl -n cattle-system get all"
    watch -d -c "kubectl -n cattle-system get all"
fi
}

## INIT ADMIN USER
COMMAND_INIT_ADMIN() {
local timeout=300
local interval=5
local elapsed=0
local pod_name=""

log_info "Waiting for a Rancher pod to be Ready (1/1) before resetting admin password (timeout: ${timeout}s)..."

while (( elapsed < timeout )); do
    pod_name=$(kubectl -n cattle-system get pods -l app=rancher --no-headers 2>/dev/null \
        | grep '1/1' | grep 'Running' | head -1 | awk '{ print $1 }')

    if [[ -n "$pod_name" ]]; then
        log_info "Rancher pod '$pod_name' is Ready. Running reset-password..."
        kubectl -n cattle-system exec "$pod_name" -- reset-password
        return $?
    fi

    log_debug "No Rancher pod Ready yet (elapsed: ${elapsed}s)..."
    sleep "$interval"
    elapsed=$((elapsed + interval))
done

log_error "Timeout: no Rancher pod became Ready after ${timeout}s"
kubectl -n cattle-system get pods -l app=rancher 2>/dev/null || true
return 1
}

question_yn "${DESC_HELM_INSTALL:=Install Helm binary? \n Helm Version: ${HELM_VERSION}}" COMMAND_HELM_INSTALL
question_yn "${DESC_HELM_REPOS:=Add SUSE + Rancher Helm repositories (Internet!)?}" COMMAND_HELM_REPOS
question_yn "${DESC_CERTMGR_INSTALL:=Install Cert Manager?}" COMMAND_CERTMGR_INSTALL
question_yn "${DESC_TEST_FQDN:=Test DNS name ${LB_RANCHER_FQDN}?}" COMMAND_TEST_FQDN
question_yn "${DESC_RANCHER_INSTALL:=Install Rancher Management Server (${LB_RANCHER_FQDN})?}" COMMAND_RANCHER_INSTALL
question_yn "${DESC_INIT_ADMIN:=Init admin user password?}" COMMAND_INIT_ADMIN

echo
echo "Rancher Management server is available."
echo "${bold}Url :${normal} https://${LB_RANCHER_FQDN}"
echo
echo "-- ${TXT_END:=END} --"
echo
echo "${bold}Deployment completed successfully!${normal}"
echo "Rancher is now available at: https://${LB_RANCHER_FQDN}"
echo
