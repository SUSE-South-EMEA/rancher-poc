bold=$(tput bold)
normal=$(tput sgr0)
#!/bin/bash
clear
echo
HOST_LIST_FILE=../hosts.list
#MASTER_LIST_FILE=../masters.list
#WORKER_LIST_FILE=../workers.list
echo "${bold}Lecture de la liste des hotes dans $HOST_LIST_FILE ${normal}"
mapfile -t HOSTS < $HOST_LIST_FILE
#mapfile -t MASTERS < $MASTER_LIST_FILE
#mapfile -t WORKERS < $WORKER_LIST_FILE

echo ${HOSTS[*]}
#printf '%s\n' "${MASTERS[@]}"
#printf '%s\n' "${WORKERS[@]}"
echo

HOST_NAME=`hostname -f`

#while true; do
#   read -p "${bold}Generer registries.conf ? (y/n) ${normal}" yn
#   case $yn in
#      [Yy]* )
#cat <<EOF > registries.conf
#unqualified-search-registries = ["docker.io"]
#
#[[registry]]
#prefix = "registry.suse.com"
#location = "${HOST_NAME}:5000/registry.suse.com"
#insecure = true
#[[registry]]
#prefix = "docker.io"
#location = "${HOST_NAME}:5000/docker.io"
#insecure = true
#[[registry]]
#prefix = "docker.io/library"
#location = "${HOST_NAME}:5000/docker.io"
#insecure = true
#[[registry]]
#prefix = "quay.io"
#location = "${HOST_NAME}:5000/quay.io"
#insecure = true
#[[registry]]
#prefix = "k8s.gcr.io"
#location = "${HOST_NAME}:5000/k8s.gcr.io"
#insecure = true
#[[registry]]
#prefix = "gcr.io"
#location = "${HOST_NAME}:5000/gcr.io"
#insecure = true
#EOF
#            break;;
#      [Nn]* ) 
#	        echo;
#			echo "Annulation de l'etape";
#			echo;
#			break;;
#      * ) echo "Please answer yes (y) or no (n).";;
#    esac
#done
#echo
#echo "#################################################"
#while true; do
#   read -p "${bold}Copie du fichier registries.conf? (y/n) ${normal}" yn
#   case $yn in
#      [Yy]* ) 
#         for h in ${MASTERS[*]};
#         do 
#		 scp registries.conf $h:/etc/containers/registries.conf
#         done;
#         for h in ${WORKERS[*]};
#         do 
#		 scp registries.conf $h:/etc/containers/registries.conf
#         done;
#      break;;
#      [Nn]* ) echo "Etape annulee";break;;
#      * ) echo "Please answer yes (y) or no (n).";;
#    esac
#done

echo "#################################################"
while true; do
   read -p "${bold}Modification de la configuration docker pour ajouter notre private registry? (y/n) ${normal}" yn
   case $yn in
      [Yy]* ) 
      sed "s/^{/&\n  \"registry-mirrors\": \[\"https\:\/\/$HOST_NAME:5000\"\],/" /etc/docker/daemon.json | tee daemon.json
      break;;
      [Nn]* ) echo "Etape annulee";break;;
      * ) echo "Please answer yes (y) or no (n).";;
    esac
done

echo "#################################################"
while true; do
   read -p "${bold}Copie du fichier configuration docker sur tous les noeuds? (y/n) ${normal}" yn
   case $yn in
      [Yy]* ) 
         for h in ${HOSTS[*]};
         do 
            scp daemon.json ${h}:/etc/docker/
         done;
      break;;
      [Nn]* ) echo "Etape annulee";break;;
      * ) echo "Please answer yes (y) or no (n).";;
    esac
done


echo "#################################################"
while true; do
   read -p "${bold}Copie du fichier certificat du registre sur tous les noeuds? (y/n) ${normal}" yn
   case $yn in
      [Yy]* ) 
         for h in ${HOSTS[*]};
         do 
            ssh $h "mkdir -p /etc/docker/certs.d/${HOST_NAME}\:5000/"
            scp /etc/registry/host.cert ${h}:/etc/docker/certs.d/${HOST_NAME}\:5000/ca.crt
         done;
      break;;
      [Nn]* ) echo "Etape annulee";break;;
      * ) echo "Please answer yes (y) or no (n).";;
    esac
done

echo "#################################################"
while true; do
   read -p "${bold}Relance du daemon docker sur tous les noeuds? (y/n) ${normal}" yn
   case $yn in
      [Yy]* ) 
         for h in ${HOSTS[*]};
         do 
            ssh $h systemctl restart docker
         done;
      break;;
      [Nn]* ) echo "Etape annulee";break;;
      * ) echo "Please answer yes (y) or no (n).";;
    esac
done
