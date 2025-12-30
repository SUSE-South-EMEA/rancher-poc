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

## RKE2 INSTALL
COMMAND_RKE2_INSTALL() {
if [[ $AIRGAP_DEPLOY != 1 ]]; then
  echo "${TXT_DL_RKE2:=Download rke2 tarball} - version: ${RKE2_VERSION}"
  # Use GitHub releases as default, fallback to RKE2_REPO if defined
  # URL encode the version to handle special characters like +
  RKE2_VERSION_ENCODED=$(echo "${RKE2_VERSION}" | sed 's/+/%2B/g')
  RKE2_DOWNLOAD_URL="${RKE2_REPO:-https://github.com/rancher/rke2/releases/download}/${RKE2_VERSION_ENCODED}/rke2.linux-amd64.tar.gz"
  echo "Downloading from: ${RKE2_DOWNLOAD_URL}"
  
  # Build curl command with appropriate options
  CURL_OPTS="-LO --fail --location --max-redirs 5"
  
  # Add User-Agent to mimic browser
  CURL_OPTS="${CURL_OPTS} --user-agent 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'"
  
  # Add proxy if configured
  if [[ $PROXY_DEPLOY == 1 ]] && [[ -n "${_HTTP_PROXY:-}" ]]; then
    CURL_OPTS="${CURL_OPTS} --proxy http://${_HTTP_PROXY}"
  fi
  
  # Try with SSL verification first, then without if it fails
  if ! eval "curl ${CURL_OPTS} --show-error '${RKE2_DOWNLOAD_URL}'" 2>&1; then
    echo "First attempt failed, trying without SSL verification..." >&2
    if ! eval "curl ${CURL_OPTS} --insecure --show-error '${RKE2_DOWNLOAD_URL}'" 2>&1; then
      echo "" >&2
      echo "Error: Failed to download RKE2 from ${RKE2_DOWNLOAD_URL}" >&2
      echo "Please check:" >&2
      echo "  - Internet connectivity" >&2
      echo "  - Proxy settings if PROXY_DEPLOY=1" >&2
      echo "  - RKE2_VERSION=${RKE2_VERSION} is correct" >&2
      echo "  - RKE2_REPO=${RKE2_REPO:-not set} if using custom repository" >&2
      echo "  - Try downloading manually: curl -LO '${RKE2_DOWNLOAD_URL}'" >&2
      exit 1
    fi
  fi
  
  if [[ ! -f rke2.linux-amd64.tar.gz ]]; then
    echo "Error: Downloaded file rke2.linux-amd64.tar.gz not found" >&2
    exit 1
  fi
  
  echo "Download completed successfully"
  ls -lh rke2.linux-amd64.tar.gz
fi
for h in "${HOSTS[@]}";do
  echo -e "\n${bold}$h${normal}"
  scp_host rke2.linux-amd64.tar.gz "$h:"
  ssh_host "$h" "sudo tar xvzf rke2.linux-amd64.tar.gz -C /usr/local/"
  ssh_host "$h" "echo ; rke2 --version && sudo mkdir -p /etc/rancher/rke2/"
done
}

## RKE2 CONFIG REGISTRY
COMMAND_RKE2_CONFIG_REGISTRY() {
echo "${TXT_RKE2_CONFIG_REGISTRY:=Generate registry configuration files}"
echo
cat << EOF > registries.yaml
mirrors:
  docker.io:
    endpoint:
      - "https://${AIRGAP_REGISTRY_URL}"
EOF

if [ "${AIRGAP_REGISTRY_INSECURE}" == "1" ]; then
cat << EOF >> registries.yaml
configs:
  "${AIRGAP_REGISTRY_URL}":
    tls:
      insecure_skip_verify: true
EOF
fi

if [ "${AIRGAP_REGISTRY_INSECURE}" == "1" ] && [[ ! ${AIRGAP_REGISTRY_URL} =~ ":" ]]; then
cat << EOF >> registries.yaml
  "${AIRGAP_REGISTRY_URL}:443":
    tls:
      insecure_skip_verify: true
EOF
fi

cat registries.yaml
}

## RKE2 CONFIG PROXY
COMMAND_RKE2_CONFIG_PROXY() {
echo "${TXT_RKE2_CONFIG_PROXY:=Generate rke2 proxy configuration file}"
echo
cat << EOF > rke2-server
HTTP_PROXY="http://$_HTTP_PROXY"
HTTPS_PROXY="http://$_HTTPS_PROXY"
NO_PROXY="$_NO_PROXY"
EOF
}

## RKE2 CONFIG CREATE
COMMAND_RKE2_CONFIG_CREATE() {
echo "${bold}${TXT_RKE2_BOOTSTRAP_CONFIG:=Generating RKE2 configuration (./config.yaml)...}${normal}"
echo "tls-san:" |tee config.yaml
for h in ${HOSTS[*]};do
  echo "  - $h" |tee -a config.yaml
done
if [[ ! -z ${RKE2_VIP_FQDN} ]] && [[ ! -z ${RKE2_VIP_IP} ]]; then
  echo "  - ${RKE2_VIP_FQDN}" |tee -a config.yaml
  echo "  - ${RKE2_VIP_IP}" |tee -a config.yaml
  echo "  - ${LB_RANCHER_FQDN}" |tee -a config.yaml
  echo "  - ${LB2_RANCHER_FQDN}" |tee -a config.yaml
fi
}

## RKE2 DEPLOY
COMMAND_RKE2_BOOTSTRAP_DEPLOY() {
echo "${bold}${TXT_RKE2_BOOTSTRAP_DEPLOY:=Bootstrap rke2 server on first node}: ${HOSTS[0]}${normal}"
echo "${TXT_COPY_FILES:=Copying files...}"
scp_host config.yaml "${HOSTS[0]}:" && ssh_host "${HOSTS[0]}" "sudo mv config.yaml /etc/rancher/rke2/config.yaml"
if [[ $AIRGAP_DEPLOY == 1 ]]; then scp_host registries.yaml "${HOSTS[0]}:" && ssh_host "${HOSTS[0]}" "sudo mv registries.yaml /etc/rancher/rke2/registries.yaml" ; fi
if [[ $PROXY_DEPLOY == 1 ]]; then scp_host rke2-server "${HOSTS[0]}:" && ssh_host "${HOSTS[0]}" "sudo mv rke2-server /etc/default/rke2-server" ; fi
echo; echo "${TXT_RKE_DEPLOY_WAIT:=Please wait while resources are being deployed (could take a few minutes...)}"
ssh_host "${HOSTS[0]}" "sudo systemctl enable --now rke2-server"
}

## KUBECONFIG SETUP
COMMAND_KUBECONFIG() {
echo "${TXT_KUBECONFIG:=Get rke2 cluster kubeconfig from first node}: ${HOSTS[0]}"
mkdir -p ~/.kube/
ssh_host "${HOSTS[0]}" "sudo cat /etc/rancher/rke2/rke2.yaml" > ~/.kube/config
chmod 600 ~/.kube/config
sed -i "s/127.0.0.1/${HOSTS[0]}/" ~/.kube/config
echo "${TXT_KUBECONFIG_PATH:=KUBECONFIG copied to ~/.kube/config}"
echo
read -rsp "${TXT_RKE_DEPLOY_PRESS_KEY:=Press a key to monitor deployment...}" -n1 key
watch -n1 -d "kubectl get nodes,pods -A ; echo -e '\nPlease wait. Ctrl+C to quit when all pods are Ready...'"
}

## KUBE-VIP DEPLOYMENT
COMMAND_KUBEVIP_DEPLOY() {
if [[ $AIRGAP_DEPLOY != 1 ]]; then
  # Download and configure the kube-vip rbac and deployment manifests
  curl -sL kube-vip.io/manifests/rbac.yaml | sudo tee kube-vip-rbac.yaml
  # Ensure VIP IP is properly formatted (kube-vip expects CIDR format or plain IP)
  # Use export to ensure variables are properly passed to the script
  export vipAddress="${RKE2_VIP_IP}"
  export vipInterface="${RKE2_VIP_INTERFACE}"
  curl -sL kube-vip.io/k3s | sh | sudo tee kube-vip.yaml
  # Find/Replace all k3s entries to represent rke2
  sed -i 's/k3s/rke2/g' kube-vip.yaml
  # Verify the VIP address in the generated manifest
  if grep -q "${RKE2_VIP_IP}" kube-vip.yaml; then
    echo "VIP address ${RKE2_VIP_IP} found in kube-vip.yaml"
  else
    echo "Warning: VIP address ${RKE2_VIP_IP} not found in kube-vip.yaml, checking content..." >&2
    grep -i "vip\|address" kube-vip.yaml | head -5
  fi
fi
# Push kube-vip rbac and deployment manifests on bootstrap node
echo
echo "${TXT_COPY_FILES:=Copying files...}"
scp_host kube-vip-rbac.yaml "${HOSTS[0]}:" && ssh_host "${HOSTS[0]}" "sudo mkdir -p /var/lib/rancher/rke2/server/manifests/ && sudo mv kube-vip-rbac.yaml /var/lib/rancher/rke2/server/manifests/kube-vip-rbac.yaml"
scp_host kube-vip.yaml "${HOSTS[0]}:" && ssh_host "${HOSTS[0]}" "sudo mv kube-vip.yaml /var/lib/rancher/rke2/server/manifests/kube-vip.yaml"
# Restart rke2-server to deploy kube-vip
echo ; echo "${TXT_RKE2_DEPLOY_RESTART:=Restart rke2 server}"
ssh_host "${HOSTS[0]}" "sudo systemctl restart rke2-server"
echo
read -rsp "${TXT_RKE_DEPLOY_PRESS_KEY:=Press a key to monitor deployment...}" -n1 key
watch -d "kubectl get pods -n kube-system -l name=kube-vip-ds ; echo ; ssh_host \"${HOSTS[0]}\" \"if ip a show dev ${RKE2_VIP_INTERFACE} |grep ${RKE2_VIP_IP} ; then echo 'VIP is up.' ; else echo 'VIP is not up yet...' ; fi\" ; echo -e '\nPlease wait. Ctrl+C to quit when all pods are Ready...'"
echo
sed -i "s/${HOSTS[0]}/${RKE2_VIP_FQDN}/" ~/.kube/config
echo "${TXT_KUBECONFIG_KUBEVIP:=KUBECONFIG (~/.kube/config) modified to use VIP hostname: ${RKE2_VIP_FQDN}}"
}

## RKE2 DEPLOY (ADDITIONNAL NODES)
COMMAND_RKE2_DEPLOY() {
echo "${TXT_RKE2_DEPLOY:=Bootstrap rke2 server on other nodes}: ${HOSTS[@]:1}"
TOKEN=$(ssh_host "${HOSTS[0]}" "sudo cat /var/lib/rancher/rke2/server/token")
for h in "${HOSTS[@]:1}";do
  echo -e "\n${bold}$h${normal}"
  echo "${TXT_COPY_FILES:=Copying files...}"
  scp_host config.yaml "$h:" && ssh_host "$h" "sudo mv config.yaml /etc/rancher/rke2/config.yaml"
  if [[ $AIRGAP_DEPLOY == 1 ]]; then scp_host registries.yaml "$h:" && ssh_host "$h" "sudo mv registries.yaml /etc/rancher/rke2/registries.yaml" ; fi
  if [[ $PROXY_DEPLOY == 1 ]]; then scp_host rke2-server "$h:" && ssh_host "$h" "sudo mv rke2-server /etc/default/rke2-server" ; fi
  echo
  if [[ ! -z ${RKE2_VIP_FQDN} ]] ; then
    ssh_host "$h" "echo \"token: $TOKEN\" |sudo tee -a /etc/rancher/rke2/config.yaml ; echo \"server: https://${RKE2_VIP_FQDN}:9345\" |sudo tee -a /etc/rancher/rke2/config.yaml"
  else
    ssh_host "$h" "echo \"token: $TOKEN\" |sudo tee -a /etc/rancher/rke2/config.yaml ; echo \"server: https://${HOSTS[0]}:9345\" |sudo tee -a /etc/rancher/rke2/config.yaml"
  fi
  echo ; echo "${TXT_RKE2_DEPLOY_START:=Start rke2 server}"
  ssh_host "$h" "sudo systemctl enable --now rke2-server"
done
echo; echo "${TXT_RKE_DEPLOY_WAIT:=Please wait while resources are being deployed (could take a few minutes...)}"
read -rsp "${TXT_RKE_DEPLOY_PRESS_KEY:=Press a key to monitor deployment...}" -n1 key
watch -n1 -d "kubectl get nodes,pods -A ; echo -e '\nPlease wait. Ctrl+C to quit when all pods are Ready...'"
}

## INSTALL HELM
COMMAND_HELM_INSTALL() {
if [[ $AIRGAP_DEPLOY == 1 ]]; then
  tar zxvf helm-v${HELM_VERSION}-linux-amd64.tar.gz
  sudo mv linux-amd64/helm /usr/local/bin/helm
  rm -rf linux-amd64/
else
  curl -O https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz
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
  helm repo add rancher-prime https://charts.rancher.com/server-charts/prime
  helm repo list
fi
}


##################### BEGIN RKE2 DEPLOYMENT ##################################
question_yn "${DESC_RKE2_INSTALL:=Install RKE2 on cluster nodes? \n RKE2 version}: ${RKE2_VERSION}" COMMAND_RKE2_INSTALL
question_yn "${DESC_RKE2_CONFIG_CREATE:=Create RKE2 configuration file?}" COMMAND_RKE2_CONFIG_CREATE
if [[ $AIRGAP_DEPLOY == 1 ]]; then
  question_yn "${DESC_RKE2_CONFIG_REGISTRY:=Create RKE2 registry configuration files?}" COMMAND_RKE2_CONFIG_REGISTRY
fi
if [[ $PROXY_DEPLOY == 1 ]]; then
  question_yn "${DESC_RKE2_CONFIG_PROXY:=Create RKE2 proxy configuration file?}" COMMAND_RKE2_CONFIG_PROXY
fi
question_yn "${DESC_RKE2_BOOTSTRAP_DEPLOY:=Bootstrap first rke2 server node?}" COMMAND_RKE2_BOOTSTRAP_DEPLOY
question_yn "${DESC_KUBECONFIG:=Copy Kubeconfig file to ~/.kube/config?}" COMMAND_KUBECONFIG
if [[ ! -z ${RKE2_VIP_FQDN} ]] && [[ ! -z ${RKE2_VIP_IP} ]]; then
  question_yn "${DESC_KUBEVIP_DEPLOY:=Deploy kube-vip in the rke2 cluster?}" COMMAND_KUBEVIP_DEPLOY
fi
question_yn "${DESC_RKE2_DEPLOY:=Deploy remaining rke2 server node?}" COMMAND_RKE2_DEPLOY
question_yn "${DESC_HELM_INSTALL:=Install Helm binary? \n Helm Version: ${HELM_VERSION}}" COMMAND_HELM_INSTALL
question_yn "${DESC_HELM_REPOS:=Add SUSE + Rancher Helm repositories (Internet!)?}" COMMAND_HELM_REPOS
##################### END RKE2 DEPLOYMENT ####################################

echo
echo "-- ${TXT_END:=END} --"
echo "${TXT_NEXT_STEP:=Next step} 03-rancher_install.sh"
