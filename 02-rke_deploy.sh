#!/bin/bash

### Source des variables
. ./00-vars.sh

bold=$(tput bold)
normal=$(tput sgr0)
clear

#Creation de la table HOSTS a partir du fichier HOST_LIST_FILE

echo "Lecture de la liste des hotes dans $HOST_LIST_FILE"
mapfile -t HOSTS < $HOST_LIST_FILE
echo "Liste des hotes:"
echo
printf '%s\n' "${HOSTS[@]}"
echo

# Fonction generique de question (yes / no)

question_yn() {
while true; do
   echo -e "${bold}---\n $1 ${normal}"
   echo -e "${bold}---\n Commande:\n ${normal}"
   declare -f $2
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
        $2
      break;;
      [Nn]* ) echo "Etape annulee";break;;
      * ) echo "Please answer yes (y) or no (n).";;
    esac
done
}

## RKE INSTALL
DESC_RKE_INSTALL="Installation de RKE en local?${bold}"
COMMAND_RKE_INSTALL() {
curl -LO https://github.com/rancher/rke/releases/download/v1.2.1/rke_linux-amd64
chmod +x rke_linux-amd64
mv rke_linux-amd64 /usr/local/bin/rke
}

## RKE CONFIG
DESC_RKE_CONFIG="Creation du fichier de configuration "cluster.yml"? \n Version K8S: $KUBERNETES_VERSION${bold}"
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
}

## RKE DEPLOY
DESC_RKE_DEPLOY="Installation de RKE en local?${bold}"
COMMAND_RKE_DEPLOY() {
rke up
}

## KUBECONFIG SETUP
DESC_KUBECONFIG="Mise en place du fichier de controle Kubeconfig?${bold}"
COMMAND_KUBECONFIG() {
export KUBECONFIG=$PWD/kube_config_cluster.yml
mkdir -p ~/.kube/
cp $PWD/kube_config_cluster.yml ~/.kube/config
chmod 600 ~/.kube/config
}

## INSTALL HELM
DESC_HELM_INSTALL="Installation de HELM? \n Helm Version: ${HELM_VERSION}${bold}"
COMMAND_HELM_INSTALL() {
curl -O https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz
tar zxvf helm-v${HELM_VERSION}-linux-amd64.tar.gz
mv linux-amd64/helm /usr/local/bin/helm
rm -rf linux-amd64/
rm helm-v${HELM_VERSION}-linux-amd64.tar.gz
}

## REPOS HELM
DESC_HELM_REPOS="Ajout des repos HELM SUSE + Rancher (internet!)?${bold}"
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
echo "-- FIN --"
echo "Prochaine étape 03-rancher_install.sh"
