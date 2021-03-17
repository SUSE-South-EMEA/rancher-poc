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

#Selection du package manager à utiliser pour les futures commandes

while true; do
   read -p "${bold}Package manager type? (zypper/yum/apt) ${normal}" pkg_mgr_type
   case $pkg_mgr_type in
      [zypper]* )
            echo $pkg_mgr_type
            echo
            break;;
      [yum]* ) 
            echo $pkg_mgr_type
            echo
	    break;;
      [apt]* ) 
            echo $pkg_mgr_type
            echo
	    break;;
      * ) echo "Please answer: zypper or yum or apt.";;
    esac
done

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
mv rke_linux-amd64 ~/bin/rke
}

## RKE CONFIG
DESC_RKE_CONFIG="Configuration de RKE?${bold}"
COMMAND_RKE_CONFIG() {
rke config
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
}

## INSTALL HELM
DESC_HELM_INSTALL="Installation de HELM?${bold}"
COMMAND_HELM_INSTALL() {
curl -O https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz
tar zxvf helm-v${HELM_VERSION}-linux-amd64.tar.gz
mv linux-amd64/helm ~/bin/helm
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
echo "Prochaine étape XXX"
