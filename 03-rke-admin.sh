#!/bin/bash

### Source des variables
. ./00-vars.sh

bold=$(tput bold)
normal=$(tput sgr0)
clear
echo 
mapfile -t HOSTS < $HOST_LIST_FILE
mapfile -t WORKERS < $HOST_WORKERS
mapfile -t MASTERS < $HOST_MASTERS

echo "Lecture du fichier $HOST_LIST_FILE..."
echo "##########################################"
echo "# Liste des noeuds pour le cluster RKE #"
echo "##########################################"
printf '%s\n' "${HOSTS[@]}"
echo
#read -p "Les fichiers $HOST_MASTERS et $HOST_WORKERS doivent être renseignés. Appuyez sur une touche pour continuer, ctrl+c pour quitter."
echo
echo "Lecture du fichier $HOST_MASTERS..."
echo "###########################################"
echo "# Liste des MASTERS pour le cluster RKE #"
echo "###########################################"
printf '%s\n' "${MASTERS[@]}"
echo

echo "Lecture du fichier $HOST_WORKERS..."
echo "###########################################"
echo "# Liste des WORKERS pour le cluster RKE #"
echo "###########################################"
printf '%s\n' "${WORKERS[@]}"
echo
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "Si les informations precedentes sont erronées, quitter ce script (ctrl-c) et corriger les fichiers"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo
#while true; do
#   read -p "Patch GMC / Adresse publique à commenter. Appliquer? (y/n) " yn
#   case $yn in
#      [Yy]* )
#         echo "Execution en cours..."
#         cp /etc/sysconfig/crio .
#         sed -e '/CRIO/ s/^#*/#/' -i crio
#         for h in ${HOSTS[*]};do scp crio root@$h:/etc/sysconfig/;done
#         for h in ${HOSTS[*]};do ssh $h "echo; hostname -f; systemctl restart crio";done
#         break;;
#      [Nn]* ) echo "Etape annulee";break;;
#        * ) echo "Please answer yes (y) or no (n).";;
#    esac
#done
#echo


while true; do
   echo -e "${bold}---\nInstallation de RKE en local ${normal}"
   echo " ${bold}Commande :${normal} curl -LO https://github.com/rancher/rke/releases/download/v1.2.1/rke_linux-amd64"
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
         echo "Execution en cours..."
curl -LO https://github.com/rancher/rke/releases/download/v1.2.1/rke_linux-amd64
chmod +x rke_linux-amd64
mv rke_linux-amd64 ~/bin/rke
         break;;
      [Nn]* ) echo "Etape annulee";break;;
        * ) echo "Please answer yes (y) or no (n).";;
    esac
done
echo
while true; do
   echo -e "${bold}---\nInstallation des outils kubernetes en local ${normal}"
   echo " ${bold}Commande :${normal} zypper -n in kubernetes1.18-client"
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
         echo "Execution en cours..."
   zypper -n in kubernetes1.18-client
         break;;
      [Nn]* ) echo "Etape annulee";break;;
        * ) echo "Please answer yes (y) or no (n).";;
    esac
done
echo

while true; do
   echo -e "${bold}---\nInstallation de docker sur tous les noeuds${normal}"
   echo " ${bold}Commande :${normal} ssh <host> \"zypper --non-interactive in docker\""
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
         for h in ${HOSTS[*]}; do ssh $h "echo && hostname -f && echo && zypper ref && zypper --non-interactive in docker"; done;
         for h in ${HOSTS[*]}; do ssh $h "systemctl enable docker && systemctl start docker"; done;
         break;;
      [Nn]* ) echo "Etape annulee";break;;
        * ) echo "Please answer yes (y) or no (n).";;
    esac
done
echo

while true; do
   echo -e "${bold}---\nForcer l'option 'net.ipv4.ip_forward = 1' dans /etc/sysctl.conf ${normal}"
   echo " ${bold}Commande :${normal} ssh <host> sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/g' /etc/sysctl.conf"
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
         for h in ${HOSTS[*]}; do ssh $h "echo; hostname -f; sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/g' /etc/sysctl.conf; sed '/^#/d' /etc/sysctl.conf" ; done
         break;;
      [Nn]* ) echo "Etape annulee";break;;
        * ) echo "Please answer yes (y) or no (n).";;
    esac
done

echo
echo

while true; do
   echo -e "${bold}---\nDesactivation du swap ${normal}"
   echo " ${bold}Commande :${normal} ssh <host> \"swapoff -a; free -g\""
   echo " Ajout du flag ${bold}noauto dans /etc/fstab${normal} pour le reboot"
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
         for h in ${HOSTS[*]};do ssh $h 'sed -i "/swap/ s/defaults/&,noauto/" /etc/fstab';done
         for h in ${HOSTS[*]};do ssh $h "echo; hostname -f; grep swap /etc/fstab; swapoff -a; free -g";done
         break;;
      [Nn]* ) echo "Etape annulee";break;;
        * ) echo "Please answer yes (y) or no (n).";;
    esac
done

echo -e "${bold}---\nssh-agent en place et ssh-add sur CAASP Admin: ${normal}"
         echo "Execution en cours..."
         eval $(ssh-agent)
         ssh-add
         echo "Done."
echo

echo -e "${bold}---\nInitialisation du cluster RKE Admin ${normal}"

while true; do
   echo -e "${bold}---\nReset de la configuration des noeuds CAASP ${normal}"
   echo " ${bold}Commande :${normal}"
   echo " - Suppression des images docker"
   echo " - suppression des dossiers k8s, ceph, rke et cni"
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
         echo "Execution en cours..."
         for h in ${HOSTS[*]}; do 
            echo  
            echo "Host = $h" 
            ssh $h "docker ps -qa | xargs docker rm -f ; \
		docker images -q | xargs docker rmi -f  ; \
		docker volume ls -q | xargs docker volume rm ; "

	    ssh $h "mount | grep tmpfs | grep '/var/lib/kubelet' | awk '{ print $3 }' | xargs umount ; \
                    umount /var/lib/kubelet; umount /var/lib/rancher"

	ssh $h "rm -rf /etc/ceph \
       /etc/cni \
       /etc/kubernetes \
       /opt/cni \
       /opt/rke \
       /run/secrets/kubernetes.io \
       /run/calico \
       /run/flannel \
       /var/lib/calico \
       /var/lib/etcd \
       /var/lib/cni \
       /var/lib/kubelet \
       /var/lib/rancher/rke/log \
       /var/log/containers \
       /var/log/kube-audit \
       /var/log/pods \
       /var/run/calico" 
         done
         echo "Done."
         break;;
      [Nn]* ) echo "Etape annulee";break;;
        * ) echo "Please answer yes (y) or no (n).";;
    esac
done
echo

## Generation du cluster.yml
echo "nodes:" > ./cluster.yml
for m in ${MASTERS[*]}; do
  echo """- address: ${m}
  role:
  - controlplane
  - etcd
  user: root""" >> ./cluster.yml
done

for w in ${WORKERS[*]}; do
echo """- address: ${w}
  role:
  - worker
  user: root""" >> ./cluster.yml
done

echo """ingress:
  provider: none""" >> ./cluster.yml

## Offline?
while true; do
   echo -e "${bold}---\nInstaller depuis un registre privé ? ${normal}"
   echo " ${bold}Commande :${normal} private_registries: admin.$dom"
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
echo """private_registries:
- url: `hostname -f`:5000
  is_default: true
""" >> ./cluster.yml
         break;;
      [Nn]* ) echo "Etape annulee";break;;
        * ) echo "Please answer yes (y) or no (n).";;
    esac
done

while true; do
   echo -e "${bold}---\nDeploiement de RKE ${normal}"
   echo
   echo " ${bold}Commandes :${normal}"
   echo "Contenu du cluster.yml"
cat cluster.yml
echo "-------"
echo "rke up --config cluster.yml"
echo
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
         echo "Execution en cours..."
rke up
         echo "Done."
         break;;
      [Nn]* ) echo "Etape annulee";break;;
        * ) echo "Please answer yes (y) or no (n).";;
    esac
done
echo
#while true; do
#   echo -e "${bold}---\nDesactivation de la mise à jour automatique du cluster par skuba ${normal}"
#   echo " ${bold}Commande :${normal}"
#   echo """
#   ssh <host> "sed -i '/SKUBA_UPDATE_OPTIONS/ s/=\"\"/=\"--annotate-only\"/' /etc/sysconfig/skuba-update"
#   """
#   read -p " ${bold}Executer ? (y/n) ${normal}" yn
#   echo
#   case $yn in
#      [Yy]* )
#         echo "Execution en cours..."
#         for h in ${HOSTS[*]}; do 
#            echo ; 
#            echo "Host = $h" ; 
#            ssh $h "sed -i '/SKUBA_UPDATE_OPTIONS/ s/=\"\"/=\"--annotate-only\"/' /etc/sysconfig/skuba-update; \
#                    grep SKUBA_UPDATE_OPTIONS /etc/sysconfig/skuba-update"
#         done
#         break
#         ;;
#      [Nn]* ) echo "Etape annulee";break;;
#        * ) echo "Please answer yes (y) or no (n).";;
#    esac
#done
#echo

echo -e "${bold}---\nChargement de la config pour administration via kubectl ${normal}"
echo " ${bold}Commandes :${normal}"
echo """
 export KUBECONFIG=$PWD/kube_config_cluster.yml
 cp $PWD/kube_config_cluster.yml ~/.kube/config
"""
export KUBECONFIG=$PWD/kube_config_cluster.yml
mkdir -p ~/.kube/
cp $PWD/kube_config_cluster.yml ~/.kube/config

echo -e "${bold}---\nEtat du cluster Kubernetes / CaaSP 4 ${normal}"
echo " ${bold}Commande :${normal} kubectl get nodes ; kubectl get pods -n kube-system"
read -p "Appuyez sur une touche."
MASTER1=$(head -1 hosts.list)
watch -n 1 -d -c "echo MASTER1; ssh $MASTER1 \"docker ps --format '{{.Image}} -- {{.Names}}' | egrep 'etcd|hyperkube'\";echo;  kubectl get nodes ; echo; kubectl get pods -n kube-system"

echo
echo "CAASP Admin actif"
echo

echo "-- FIN --"
echo "Prochaine étape 04-services_apache.sh"
