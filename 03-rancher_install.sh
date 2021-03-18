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

## CERT MANAGER INSTALL
DESC_CERTMGR_INSTALL="Installation de Cert Manager?${bold}"
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
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.2.0 \
  --set global.podSecurityPolicy.enabled=True \
  --set global.podSecurityPolicy.useAppArmor=False
  # Correction pour K8S 1.19 - sélection du profil PSP (apparmor forcé bien que désactivé)
kubectl annotate --overwrite psp cert-manager \
  seccomp.security.alpha.kubernetes.io/allowedProfileNames=docker/default,runtime/default
kubectl annotate --overwrite psp cert-manager-cainjector \
  seccomp.security.alpha.kubernetes.io/allowedProfileNames=docker/default,runtime/default
kubectl annotate --overwrite psp cert-manager-webhook \
  seccomp.security.alpha.kubernetes.io/allowedProfileNames=docker/default,runtime/default
echo "Verification de l'installation de Cert Manager"
read -p "#> kubectl get pods --namespace cert-manager"
watch -d -c "kubectl get pods,services -n cert-manager"
}

## TEST FQDN FOR RANCHER MGMT
DESC_TEST_FQDN="Test du nom dns rancher.$dom?${bold}"
COMMAND_TEST_FQDN() {
ping -c 1 rancher.$dom
}

## INSTALL RANCHER MANAGEMEBT
DESC_RANCHER_INSTALL="Installation de Rancher Management (rancher.$dom)?${bold}"
COMMAND_RANCHER_INSTALL() {
kubectl create namespace cattle-system
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=rancher.$dom
echo "Verification de l'installation de rancher.app"
read -p "#> kubectl -n cattle-system get pods,deploy"
watch -d -c "kubectl -n cattle-system get pods,deploy"
}

## INIT ADMIN USER
DESC_INIT_ADMIN="Initialisation d'un utilisateur admin?${bold}"
COMMAND_INIT_ADMIN() {
kubectl -n cattle-system exec $(kubectl -n cattle-system get pods -l app=rancher | grep '1/1' | head -1 | awk '{ print $1 }') -- reset-password
}

question_yn "$DESC_CERTMGR_INSTALL" COMMAND_CERTMGR_INSTALL
question_yn "$DESC_TEST_FQDN" COMMAND_TEST_FQDN
question_yn "$DESC_RANCHER_INSTALL" COMMAND_RANCHER_INSTALL
question_yn "$DESC_INIT_ADMIN" COMMAND_INIT_ADMIN

echo
echo "Rancher Management server is available:"
echo "${bold}Url :${normal} https://rancher.${ext_dom}"
echo
echo "-- FIN --"
