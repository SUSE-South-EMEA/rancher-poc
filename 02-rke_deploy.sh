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

## RKE INSTALL
COMMAND_RKE_INSTALL() {
if [[ $AIRGAP_DEPLOY == 1 ]]; then
  chmod +x rke_linux-amd64
  sudo cp rke_linux-amd64 /usr/local/bin/rke
else
  curl -LO https://github.com/rancher/rke/releases/download/${RKE_VERSION}/rke_linux-amd64
  chmod +x rke_linux-amd64
  sudo mv rke_linux-amd64 /usr/local/bin/rke
fi
rke --version
}

## RKE CONFIG
COMMAND_RKE_CONFIG() {
echo "nodes:" > ./cluster.yml
for m in ${HOSTS[*]}; do
  echo """- address: ${m}
  role:
  - controlplane
  - etcd
  - worker
  user: ${DOCKER_USER}""" >> ./cluster.yml
done
echo "kubernetes_version: \"$KUBERNETES_VERSION\"" >> ./cluster.yml
echo "ingress:" >> ./cluster.yml
echo "  provider: nginx" >> ./cluster.yml
#rke config
if [[ $AIRGAP_DEPLOY == 1 ]]; then
echo """private_registries:
  - url: $AIRGAP_REGISTRY_URL
    is_default: true """ >> ./cluster.yml
  if [[ ! -z ${AIRGAP_REGISTRY_USER} ]] ; then
    echo """    user: $AIRGAP_REGISTRY_USER
    password: $AIRGAP_REGISTRY_PASSWD """ >> ./cluster.yml
  fi
fi
echo -e "${TXT_RKE_CONFIG_GENERATED:=Configuration file cluster.yml is created with content:\n}"
cat ./cluster.yml
}

## RKE DEPLOY
COMMAND_RKE_DEPLOY() {
rke up
echo; echo "${TXT_RKE_DEPLOY_WAIT:=Please wait while resources are being created.}"
read -rsp "${TXT_RKE_DEPLOY_PRESS_KEY:=Press a key to monitor deployment...}" -n1 key
export KUBECONFIG=$PWD/kube_config_cluster.yml
watch -n1 -d kubectl get nodes,pods -A
}

## KUBECONFIG SETUP
COMMAND_KUBECONFIG() {
export KUBECONFIG=$PWD/kube_config_cluster.yml
mkdir -p ~/.kube/
chmod 600 $PWD/kube_config_cluster.yml
cp $PWD/kube_config_cluster.yml ~/.kube/config
chmod 600 ~/.kube/config
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
  helm repo add suse https://kubernetes-charts.suse.com/
  helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
  helm repo list
fi
}


question_yn "${DESC_RKE_INSTALL:=Install RKE binary on local node? \n RKE version: ${RKE_VERSION}}" COMMAND_RKE_INSTALL
question_yn "${DESC_RKE_CONFIG:=Create cluster.yml configuration file? \n Kubernetes version: $KUBERNETES_VERSION}" COMMAND_RKE_CONFIG
question_yn "${DESC_RKE_DEPLOY:=Deploy RKE cluster?}" COMMAND_RKE_DEPLOY
question_yn "${DESC_KUBECONFIG:=Copy Kubeconfig file to ~/.kube/config?}" COMMAND_KUBECONFIG
question_yn "${DESC_HELM_INSTALL:=Install Helm binary? \n Helm Version: ${HELM_VERSION}}" COMMAND_HELM_INSTALL
question_yn "${DESC_HELM_REPOS:=Add SUSE + Rancher Helm repositories (Internet!)?}" COMMAND_HELM_REPOS

echo
echo "-- ${TXT_END:=END} --"
echo "${TXT_NEXT_STEP:=Next step} 03-rancher_install.sh"
