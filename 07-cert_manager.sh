#!/bin/bash

### Source des variables
. ./00-vars.sh

bold=$(tput bold)
normal=$(tput sgr0)
clear

#cp cluster.yml cluster-noingress.yml
#sed -i "s/none/nginx/" cluster.yml
#
#while true; do
#	echo -e "${bold}---\nInstallation du reverse proxy nginx-ingress en DaemonSet ${normal}"
#   echo " ${bold}Commande :${normal} "
##   echo " - ajout des labels 'ingress' aux noeuds worker"
#   echo " - ajout de la declaration de nginx dans le cluster.yml"
#echo "Contenu du cluster.yml"
#cat cluster.yml
#echo "----"
#   read -p " ${bold}Executer ? (y/n) ${normal}" yn
#   echo
#   case $yn in
#      [Yy]* )
#rke up
#            break;;
#      [Nn]* ) echo "Annulation de l'etape";break;;
#          * ) echo "Please answer yes (y) or no (n). ";;
#    esac
#done

##
##  Cert Manager est utile si ranche est installé sur RKE
##



while true; do
   echo -e "${bold}---\nInstallation de cert-manager pour generer des certificats TLS ${normal}"
   echo " ${bold}Commande :${normal} "
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo """
A METTRE A JOUR
"""
#kubectl create namespace cert-manager
#helm install cert-manager suse/cert-manager --namespace cert-manager --version v0.15.1
   case $yn in
      [Yy]* )
## Create the namespace for cert-manager
#kubectl create namespace cert-manager
## Install the cert-manager Helm chart
#helm install \
#  cert-manager suse/cert-manager \
#  --namespace cert-manager \
#  --version v0.15.1
#
# Install the CustomResourceDefinition resources separately
#kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.0.4/cert-manager.crds.yaml
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.2.0/cert-manager.crds.yaml

# **Important:**
# If you are running Kubernetes v1.15 or below, you
# will need to add the `--validate=false` flag to your
# kubectl apply command, or else you will receive a
# validation error relating to the
# x-kubernetes-preserve-unknown-fields field in
# cert-manager’s CustomResourceDefinition resources.
# This is a benign error and occurs due to the way kubectl
# performs resource validation.

# Create the namespace for cert-manager
kubectl create namespace cert-manager

# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io

# Update your local Helm chart repository cache
helm repo update

# Install the cert-manager Helm chart
	    #--version v1.0.4 \
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
            break;;
      [Nn]* ) echo "Annulation de l'etape";break;;
          * ) echo "Please answer yes (y) or no (n). ";;
    esac
done
echo
#echo "Verification de l'installation de Ingress NGINX"
#read -p "#> kubectl get pods --namespace ingress-nginx"
#watch -d -c "kubectl get pods,services -n ingress-nginx"
echo "Verification de l'installation de Cert Manager"
read -p "#> kubectl get pods --namespace cert-manager"
watch -d -c "kubectl get pods,services -n cert-manager"
echo

echo
echo "-- FIN --"
echo "Prochaine étape 08-rancher.sh"
