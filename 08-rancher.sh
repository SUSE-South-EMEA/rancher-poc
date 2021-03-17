#!/bin/bash

### Source des variables
. ./00-vars.sh

bold=$(tput bold)
normal=$(tput sgr0)
clear
echo

## Rancher sur RKE
## FIX: le proxy externe ne renvoie pas vert la bonne url
## il faut deployer avec le $ext_dom
## https://rancher.com/docs/rancher/v2.x/en/installation/resources/advanced/helm2/rke-add-on/layer-7-lb/

## FIX: Best Practice Rancher est deployé sur sont propre RKE
## il faut faire un rke up sur 1 node sur admin
#
#
while true; do
   echo -e "${bold}---\nTester le nom dns rancher.$dom ${normal}"
   echo " ${bold}Commande :${normal} ping -c 1 rancher.$dom"
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
            ping -c 1 rancher.$dom
            break;;
      [Nn]* )
            echo;
            echo "Annulation de l'etape.";
            echo;
            break;;
      * ) echo "Please answer yes (y) or no (n). ";;
    esac
done
echo
while true; do
   echo -e "${bold}---\nInstallation de Rancher Management (rancher.$dom) ${normal}"
   echo " ${bold}Commande :${normal}"
   echo """
kubectl create namespace cattle-system
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=rancher.$dom
   """
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
kubectl create namespace cattle-system
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=rancher.$dom
            break;;
      [Nn]* )
                echo;
                        echo "Annulation de l'etape.";
                        echo;
                        break;;
          * ) echo "Please answer yes (y) or no (n). ";;
    esac
done
echo
echo
echo "Verification de l'installation de rancher.app"
read -p "#> kubectl -n cattle-system get pods,deploy"
watch -d -c "kubectl -n cattle-system get pods,deploy"
echo
echo "###################################"
echo "# Rancher Management est déployé  #"
echo "###################################"
# 
while true; do
   echo -e "${bold}---\nInstallation de Rancher Management (rancher.$dom) ${normal}"
   echo " ${bold}Commande :${normal}"
   echo """
kubectl create namespace cattle-system
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=rancher.$dom
   """
   read -p " ${bold}Initialiser le mot de passe admin de l'interface ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
kubectl -n cattle-system exec $(kubectl -n cattle-system get pods -l app=rancher | grep '1/1' | head -1 | awk '{ print $1 }') -- reset-password
            break;;
      [Nn]* )
                echo;
                        echo "Annulation de l'etape.";
                        echo;
                        break;;
          * ) echo "Please answer yes (y) or no (n). ";;
    esac
done


echo
echo "${bold}Url :${normal} https://rancher.${ext_dom}"
echo

############################
## Workaround
## Install de Rancher en standalone sur l'admin node
#docker run -d --restart=unless-stopped   -p 80:80 -p 443:443   --privileged   rancher/rancher:v2.5-head

echo "${bold}Url :${normal} https://admin.${ext_dom}"

echo "-- FIN --"
