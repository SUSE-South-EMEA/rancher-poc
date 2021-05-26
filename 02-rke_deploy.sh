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
curl -LO https://github.com/rancher/rke/releases/download/${RKE_VERSION}/rke_linux-amd64
chmod +x rke_linux-amd64
sudo mv rke_linux-amd64 /usr/local/bin/rke
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
echo "Fichier cluster.yml généré:"
cat ./cluster.yml
}

## RKE DEPLOY
COMMAND_RKE_DEPLOY() {
rke up
echo; echo "Veuillez patienter lors de la création des ressources du clusters."
read -rsp $'Pressez une touche pour suivre la construction...\n' -n1 key
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
curl -O https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz
tar zxvf helm-v${HELM_VERSION}-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm
rm -rf linux-amd64/
rm helm-v${HELM_VERSION}-linux-amd64.tar.gz
}

## REPOS HELM
COMMAND_HELM_REPOS() {
helm repo add suse https://kubernetes-charts.suse.com/
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo list
}


question_yn "$DESC_RKE_INSTALL" COMMAND_RKE_INSTALL
question_yn "$DESC_RKE_CONFIG" COMMAND_RKE_CONFIG
question_yn "$DESC_RKE_DEPLOY" COMMAND_RKE_DEPLOY
question_yn "$DESC_KUBECONFIG" COMMAND_KUBECONFIG
question_yn "$DESC_HELM_INSTALL" COMMAND_HELM_INSTALL
question_yn "$DESC_HELM_REPOS" COMMAND_HELM_REPOS

echo
echo "-- $TXT_END --"
echo "$TXT_NEXT_STEP 03-rancher_install.sh"
