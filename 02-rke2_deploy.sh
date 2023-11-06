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
  curl -LO https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2.linux-amd64.tar.gz
fi
for h in ${HOSTS[*]};do
  echo -e "\n${bold}$h${normal}"
  scp rke2.linux-amd64.tar.gz $h:
  ssh $h "sudo tar xvzf rke2.linux-amd64.tar.gz -C /usr/local/"
  ssh $h "echo ; rke2 --version && sudo mkdir -p /etc/rancher/rke2/"
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
fi
}

## RKE2 DEPLOY
COMMAND_RKE2_BOOTSTRAP_DEPLOY() {
echo "${bold}${TXT_RKE2_BOOTSTRAP_DEPLOY:=Bootstrap rke2 server on first node}: ${HOSTS[0]}${normal}"
echo "${TXT_COPY_FILES:=Copying files...}"
scp config.yaml ${HOSTS[0]}: && ssh ${HOSTS[0]} "sudo mv config.yaml /etc/rancher/rke2/config.yaml"
if [[ $AIRGAP_DEPLOY == 1 ]]; then scp registries.yaml ${HOSTS[0]}: && ssh ${HOSTS[0]} "sudo mv registries.yaml /etc/rancher/rke2/registries.yaml" ; fi
if [[ $PROXY_DEPLOY == 1 ]]; then scp rke2-server ${HOSTS[0]}: && ssh ${HOSTS[0]} "sudo mv rke2-server /etc/default/rke2-server" ; fi
echo; echo "${TXT_RKE_DEPLOY_WAIT:=Please wait while resources are being deployed (could take a few minutes...)}"
ssh ${HOSTS[0]} "sudo systemctl enable --now rke2-server"
}

## KUBECONFIG SETUP
COMMAND_KUBECONFIG() {
echo "${TXT_KUBECONFIG:=Get rke2 cluster kubeconfig from first node}: ${HOSTS[0]}"
mkdir -p ~/.kube/
ssh ${HOSTS[0]} "sudo cat /etc/rancher/rke2/rke2.yaml" > ~/.kube/config
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
  curl -sL kube-vip.io/k3s |  vipAddress=${RKE2_VIP_IP} vipInterface=${RKE2_VIP_INTERFACE} sh | sudo tee kube-vip.yaml
  # Find/Replace all k3s entries to represent rke2
  sed -i 's/k3s/rke2/g' kube-vip.yaml
fi
# Push kube-vip rbac and deployment manifests on bootstrap node
echo
echo "${TXT_COPY_FILES:=Copying files...}"
scp kube-vip-rbac.yaml ${HOSTS[0]}: && ssh ${HOSTS[0]} "sudo mkdir -p /var/lib/rancher/rke2/server/manifests/ && sudo mv kube-vip-rbac.yaml /var/lib/rancher/rke2/server/manifests/kube-vip-rbac.yaml"
scp kube-vip.yaml ${HOSTS[0]}: && ssh ${HOSTS[0]} "sudo mv kube-vip.yaml /var/lib/rancher/rke2/server/manifests/kube-vip.yaml"
# Restart rke2-server to deploy kube-vip
echo ; echo "${TXT_RKE2_DEPLOY_RESTART:=Restart rke2 server}"
ssh ${HOSTS[0]} "sudo systemctl restart rke2-server"
echo
read -rsp "${TXT_RKE_DEPLOY_PRESS_KEY:=Press a key to monitor deployment...}" -n1 key
watch -d "kubectl get pods -n kube-system -l name=kube-vip-ds ; echo ; ssh ranch1 \"if ip a show dev ${RKE2_VIP_INTERFACE} |grep ${RKE2_VIP_IP} ; then echo 'VIP is up.' ; else echo 'VIP is not up yet...' ; fi \" ; echo -e '\nPlease wait. Ctrl+C to quit when all pods are Ready...'"
echo
sed -i "s/${HOSTS[0]}/${RKE2_VIP_FQDN}/" ~/.kube/config
echo "${TXT_KUBECONFIG_KUBEVIP:=KUBECONFIG (~/.kube/config) modified to use VIP hostname: ${RKE2_VIP_FQDN}}"
}

## RKE2 DEPLOY (ADDITIONNAL NODES)
COMMAND_RKE2_DEPLOY() {
echo "${TXT_RKE2_DEPLOY:=Bootstrap rke2 server on other nodes}: ${HOSTS[@]:1}"
TOKEN=$(ssh ${HOSTS[0]} "sudo cat /var/lib/rancher/rke2/server/token")
for h in ${HOSTS[@]:1};do
  echo -e "\n${bold}$h${normal}"
  echo "${TXT_COPY_FILES:=Copying files...}"
  scp config.yaml $h: && ssh $h "sudo mv config.yaml /etc/rancher/rke2/config.yaml"
  if [[ $AIRGAP_DEPLOY == 1 ]]; then scp registries.yaml $h: && ssh $h "sudo mv registries.yaml /etc/rancher/rke2/registries.yaml" ; fi
  if [[ $PROXY_DEPLOY == 1 ]]; then scp rke2-server $h: && ssh $h "sudo mv rke2-server /etc/default/rke2-server" ; fi
  echo
  if [[ ! -z ${RKE2_VIP_FQDN} ]] ; then
    ssh $h "echo \"token: $TOKEN\" |sudo tee -a /etc/rancher/rke2/config.yaml ; echo \"server: https://${RKE2_VIP_FQDN}:9345\" |sudo tee -a /etc/rancher/rke2/config.yaml"
  else
    ssh $h "echo \"token: $TOKEN\" |sudo tee -a /etc/rancher/rke2/config.yaml ; echo \"server: https://${HOSTS[0]}:9345\" |sudo tee -a /etc/rancher/rke2/config.yaml"
  fi
  echo ; echo "${TXT_RKE2_DEPLOY_START:=Start rke2 server}"
  ssh $h "sudo systemctl enable --now rke2-server"
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
