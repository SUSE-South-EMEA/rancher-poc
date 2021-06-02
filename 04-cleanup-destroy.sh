#!/bin/bash

### Source variables
source ./00-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh

while true; do
   echo -e "${bold}---\nReset de la configuration des noeuds?  ${normal}"
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

while true; do
   echo -e "${bold}---\nReset de la configuration locale?  ${normal}"
   echo " ${bold}Commande en local:${normal}"
   echo " - Suppression des images docker"
   echo " - suppression des dossiers k8s, ceph, rke et cni"
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
         echo "Execution en cours..."
docker ps -qa | xargs docker rm -f 
docker images -q | xargs docker rmi -f 
docker volume ls -q | xargs docker volume rm

mount | grep tmpfs | grep '/var/lib/kubelet' | awk '{ print $3 }' | xargs umount ; umount /var/lib/kubelet; umount /var/lib/rancher

rm -rf /etc/ceph \
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
       /var/run/calico
       break;;
      [Nn]* ) echo "Etape annulee";break;;
        * ) echo "Please answer yes (y) or no (n).";;
    esac
done

echo "-- ${TXT_END:=END} --"
