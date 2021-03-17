#!/bin/bash

### Source des variables
. ./00-vars.sh

bold=$(tput bold)
normal=$(tput sgr0)
clear
echo

echo "######################################"
echo "# Déploiement du client/serveur Helm #"
echo "######################################"
echo
while true; do
   echo -e "${bold}---\nInstallation de helm version 3 dans ~/bin/${normal}"
   echo -e " ${bold}Commande :${normal} curl -O https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz"
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
         echo "Execution en cours..."
  curl -O https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz
  tar zxvf helm-v${HELM_VERSION}-linux-amd64.tar.gz
  mv linux-amd64/helm ~/bin/helm
  rm -rf linux-amd64/
  rm helm-v${HELM_VERSION}-linux-amd64.tar.gz
         break;;
      [Nn]* ) echo "Etape annulee";break;;
        * ) echo "Please answer yes (y) or no (n).";;
    esac
done

echo
while true; do
   echo -e "${bold}---\nAjouter les charts Helm de SUSE + Rancher (connexion Internet) ${normal}"
   echo " ${bold}Commande :${normal} helm repo add suse https://kubernetes-charts.suse.com/"
   echo " helm repo add rancher-stable https://releases.rancher.com/server-charts/stable"
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Nn]* ) echo "Etape annulee";break;;
      [Yy]* )
         echo "Execution..."
	 	helm repo add suse https://kubernetes-charts.suse.com/
		helm repo add rancher-stable https://releases.rancher.com/server-charts/stable

         echo "Done."
         echo
         break;;
          * ) echo "Please answer yes (y) or no (n). ";;
    esac
done
echo 
#
# FIX : mettre Harbor
#HOST_NAME=$(hostname -f)
#while true; do
#   echo -e "${bold}---\nAjouter les charts Helm du Airgap (si deployé) ${normal}"
#   echo " ${bold}Commande :${normal} helm repo add suse http://${HOST_NAME}/charts"
#   read -p " ${bold}Executer ? (y/n) ${normal}" yn
#   echo
#   case $yn in
#      [Nn]* ) echo "Etape annulee";break;;
#      [Yy]* )
#         echo "Execution..."
#	 	helm repo add suse http://${HOST_NAME}/charts
#         echo "Done."
#         echo
#         break;;
#          * ) echo "Please answer yes (y) or no (n). ";;
#    esac
#done
#echo
echo -e "Liste des repos Helm:"
helm repo list

echo
echo "-- FIN --"
echo "Prochaine étape 07-ingress.sh"
