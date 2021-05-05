#!/bin/bash

### Source variables
source ./00-vars.sh
source ./lang/$LANGUAGE.sh

bold=$(tput bold)
normal=$(tput sgr0)
clear

#Creation de la table HOSTS a partir du fichier HOST_LIST_FILE

echo "Lecture de la liste des hotes dans $HOST_LIST_FILE"
mapfile -t HOSTS < $HOST_LIST_FILE
echo "Liste des hotes cibles:"
echo
printf '%s\n' "${HOSTS[@]}"
echo

# Selection du package manager à utiliser pour les futures commandes

while true; do
   read -p "${bold}Package manager type? (zypper/yum/apt) ${normal}" pkg_mgr_type
   case $pkg_mgr_type in
      [zypper]* )
            echo "$pkg_mgr_type selected."
            echo
            break;;
      [yum]* ) 
            echo "$pkg_mgr_type selected."
            echo
	    break;;
      [apt]* ) 
            echo "$pkg_mgr_type selected."
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
   echo
   read -p " ${bold}Executer ? (y/n) ${normal}" yn
   echo
   case $yn in
      [Yy]* )
        $2
        echo
        read -rsp $'Pressez une touche pour continuer...\n' -n1 key
      break;;
      [Nn]* ) echo "Etape annulee";break;;
      * ) echo "Please answer yes (y) or no (n).";;
    esac
done
}

## PRE-CHECK PACKAGE

COMMAND_CHECK_PACKAGE_RPM() {
for i in $@;do echo "Recherche de la presence du paquet: ${bold}$i${normal}"
if sudo rpm -q $i
then
  echo "${bold}$i${normal} is present. OK!";echo
else
  echo "${bold}$i${normal} is not present. ERROR!"
  echo "sudo rpm -q ${bold}$i${normal}: 'not installed'"
fi
done
}

## SSH KEYS CREATION
COMMAND_SSH_KEYS() {
ssh-keygen
}

## SSH KEYS DEPLOY
COMMAND_SSH_DEPLOY() {
read -s -p "Veuillez entrer le mot de passe des clients : " PASSWD
for h in ${HOSTS[*]};
  do expect -c "set timeout 2; spawn ssh-copy-id -o StrictHostKeyChecking=no $h; expect 'assword:'; send "$PASSWD\\r"; interact"
done;
}

## SSH CONNECT TESTING
COMMAND_SSH_CONNECT_TEST() {
for h in ${HOSTS[*]}; do ssh $h "hostname -f" ; done;
}

## Copy Proxy CA locally
COMMAND_COPY_PROXY_CA() {
if [[ $pkg_mgr_type == 'zypper' ]]
then
	PRIV_KEY_PATH="/etc/pki/trust/anchors/"
elif [[ $pkg_mgr_type == 'yum' ]]
then
	PRIV_KEY_PATH="/etc/pki/ca-trust/source/anchors/"
fi
echo "Recuperation du certificat privé provenant du proxy."
sudo scp -o StrictHostKeyChecking=no $PROXY_ADDR:$PROXY_CA_LOCATION /tmp/proxyCA.pem
for h in ${HOSTS[*]}
  do
ssh $h "hostname"
scp /tmp/proxyCA.pem $h:$PRIV_KEY_PATH
done
}

## SET PROXY
COMMAND_SET_PROXY() {
if [[ $pkg_mgr_type == 'zypper' ]]
then
	PRIV_KEY_PATH="/etc/pki/trust/anchors/"
elif [[ $pkg_mgr_type == 'yum' ]]
then
	PRIV_KEY_PATH="/etc/pki/ca-trust/source/anchors/"
fi
echo "$PROXY_ADDR:$PROXY_CA_LOCATION"
echo
for h in ${HOSTS[*]}
  do
ssh $h "sudo tee /etc/profile.d/proxy.sh <<EOF
export http_proxy=http://${_HTTP_PROXY}
export https_proxy=http://${_HTTPS_PROXY}
export no_proxy=${_NO_PROXY}
EOF
hostname -f
if [[ $pkg_mgr_type == 'zypper' ]]
then 
sudo update-ca-certificates
fi
if [[ $pkg_mgr_type == 'yum' ]]
then 
sudo update-ca-trust
fi
echo 'Parametres Proxy ajoutes dans /etc/profile.d/proxy.sh'
echo"
done
# ajout en local egalement
sudo tee /etc/profile.d/proxy.sh <<EOF
export http_proxy=http://${_HTTP_PROXY}
export https_proxy=http://${_HTTPS_PROXY}
export no_proxy=${_NO_PROXY}
EOF
source /etc/profile.d/proxy.sh
sudo cp /tmp/proxyCA.pem $PRIV_KEY_PATH
if [[ $pkg_mgr_type == 'zypper' ]]
then 
sudo update-ca-certificates
fi
if [[ $pkg_mgr_type == 'yum' ]]
then 
sudo update-ca-trust
fi
echo "$(hostname -f) : Parametres Proxy ajoutes dans /etc/profile.d/proxy.sh"
}

## LISTE DES REPOSITORIES
COMMAND_REPOS_ZYPPER() {
for h in ${HOSTS[*]}
  do ssh $h "echo && hostname -f && echo && sudo zypper lr"; 
done
}
COMMAND_REPOS_YUM() {
for h in ${HOSTS[*]}
  do ssh $h "echo && hostname -f && echo && sudo yum repolist all"; 
done
}

## ADDING REPOSITORIES
COMMAND_ADDREPOS_ZYPPER() {
for h in ${HOSTS[*]}
  do ssh $h "echo ; hostname -f ; echo ; sudo zypper ref ; 
sudo zypper ar -G http://${REPO_SERVER}/ks/dist/child/sle-module-containers15-sp2-pool-x86_64/sles15sp2 containers_product ; 
sudo zypper ar -G http://${REPO_SERVER}/ks/dist/child/sle-module-containers15-sp2-updates-x86_64/sles15sp2 containers_updates" 
done
sudo zypper ar -G http://${REPO_SERVER}/ks/dist/child/sle-module-containers15-sp2-pool-x86_64/sles15sp2 containers_product
sudo zypper ar -G http://${REPO_SERVER}/ks/dist/child/sle-module-containers15-sp2-updates-x86_64/sles15sp2 containers_updates
}

COMMAND_ADDREPOS_YUM() {
for h in ${HOSTS[*]}
  do ssh $h "echo ; hostname -f ; echo
sudo tee /etc/yum.repos.d/res7.repo <<EOF
[res7]
name=res7
baseurl=http://${REPO_SERVER}/ks/dist/child/res7-x86_64/rhel76
enabled=1
gpgcheck=0
EOF
sudo tee /etc/yum.repos.d/res7-iso.repo <<EOF
[res7-iso]
name=res7.6-ISO
baseurl=http://${REPO_SERVER}/ks/dist/child/rhel76-iso/rhel76
enabled=1
gpgcheck=0
EOF
sudo tee  /etc/yum.repos.d/res7-suma.repo <<EOF
[res7-SUMA]
name=res7-SUMA_BOOTSTRAP
baseurl=http://${REPO_SERVER}/ks/dist/child/res7-suse-manager-tools-x86_64/rhel76
enabled=1
gpgcheck=0
EOF"
done
}

## YUM SPECIFIC REPO FOR K8S TOOLS 
COMMAND_ADDREPOS_YUM_K8STOOLS() {
sudo tee /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
echo -e "Repo for K8S Tools has been added."
}

## ALL NODES UPDATE 
COMMAND_NODES_UPDATE_ZYPPER() {
for h in ${HOSTS[*]}
  do ssh $h "echo ; hostname -f ; echo ; sudo zypper ref ; sudo zypper --non-interactive up"
done;
for h in ${HOSTS[*]}
  do ssh $h "echo ; sudo zypper ps" 
done
}

COMMAND_NODES_UPDATE_YUM() {
for h in ${HOSTS[*]}
  do ssh $h "echo ; hostname -f ; echo ; sudo yum -y update"
done;
}

## CHECK TIME
COMMAND_CHECK_TIME() {
for h in ${HOSTS[*]}; do ssh $h "echo && hostname -f && sudo chronyc -a tracking |grep 'Leap status'"; done;
}

## CHECK ACCESS - INTERNET/PROXY/REGISTRY
COMMAND_CHECK_ACCESS() {
echo -e "Reseau Public (registry.suse.com):"
for h in ${HOSTS[*]}; do ssh $h "echo && hostname -f && curl -s -o /dev/null -I https://registry.suse.com  && echo 'registry.suse.com: OK' || echo 'registry.suse.com: FAIL'"; done;
echo
echo -e "Reseau de Stockage:"
echo -e "Sauf pour la machine admin (isolation réseau)"
for h in ${HOSTS[*]}; do ssh $h "echo && hostname -f && ping -c1 $STORAGE_TARGET > /dev/null  && echo 'Acces Stockage: OK' || echo 'Acces Stockage: FAIL'"; done;
}

## DOCKER INSTALL
COMMAND_DOCKER_INSTALL_ZYPPER() {
for h in ${HOSTS[*]}; do ssh $h "echo ; hostname -f ; sudo zypper ref ; sudo zypper --non-interactive in docker"; done;
for h in ${HOSTS[*]}; do ssh $h "echo ; hostname -f ; sudo systemctl enable docker ; sudo systemctl start docker && echo 'Docker is activated' || echo 'Docker could not start'"; done;
}
COMMAND_DOCKER_INSTALL_YUM() {
for h in ${HOSTS[*]}; do ssh $h "echo ; hostname -f ; sudo yum install -y http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.107-3.el7.noarch.rpm"; done;
for h in ${HOSTS[*]}; do ssh $h "echo ; hostname -f ; sudo yum install -y http://mirror.centos.org/centos/7/extras/x86_64/Packages/slirp4netns-0.4.3-4.el7_8.x86_64.rpm"; done;
for h in ${HOSTS[*]}; do ssh $h "echo ; hostname -f ; curl -s http://releases.rancher.com/install-docker/${DOCKER_VERSION}.sh | /bin/bash"; done;
for h in ${HOSTS[*]}; do ssh $h "echo ; hostname -f ; sudo systemctl enable docker ; sudo systemctl start docker && echo 'Docker is activated' || echo 'Docker could not start'"; done;
}

## DOCKER USER/GROUP FOR RKE
COMMAND_CREATE_DOCKER_USER() {
for h in ${HOSTS[*]}; do ssh $h "echo ; hostname -f ;
sudo useradd -m -G ${DOCKER_GROUP} ${DOCKER_USER} > /dev/null 2>&1 && echo \"${DOCKER_USER} user is created\" || echo \"Failed to create ${DOCKER_USER} user\" &&
sudo mkdir /home/${DOCKER_USER}/.ssh &&
sudo chown ${DOCKER_USER}:${DOCKER_GROUP} /home/${DOCKER_USER}/.ssh &&
sudo chmod 700 /home/${DOCKER_USER}/.ssh &&
echo "Ajout des clefs publiques dans /home/${DOCKER_USER}/.ssh/authorized_keys:" &&
cat ${HOME}/.ssh/authorized_keys |sudo tee /home/${DOCKER_USER}/.ssh/authorized_keys &&
sudo chown ${DOCKER_USER}:${DOCKER_GROUP} /home/${DOCKER_USER}/.ssh/authorized_keys &&
sudo chmod 600 /home/${DOCKER_USER}/.ssh/authorized_keys "; done;
}

## DOCKER PROXY
COMMAND_DOCKER_PROXY() {
for h in ${HOSTS[*]}; do ssh $h "echo ; hostname -f ;
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://${_HTTP_PROXY}"
Environment="HTTPS_PROXY=http://${_HTTPS_PROXY}"
Environment="NO_PROXY=${_NO_PROXY}"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker"
done
}

## ACTIVATION IP FORWARDING
COMMAND_IPFORWARD_ACTIVATE() {
for h in ${HOSTS[*]};do ssh $h "echo; hostname -f ; sudo sed -i '/net.ipv4.ip_forward.*/d' /etc/sysctl.conf; echo 'net.ipv4.ip_forward = 1' |sudo tee -a /etc/sysctl.conf; sudo sed '/^#/d' /etc/sysctl.conf;sudo sysctl -p" ; done
}

## DESACTIVATION DU SWAP
COMMAND_NO_SWAP() {
for h in ${HOSTS[*]};do ssh $h 'sudo sed -i "/swap/ s/defaults/&,noauto/" /etc/fstab';done
for h in ${HOSTS[*]};do ssh $h "echo; hostname -f; grep swap /etc/fstab; sudo swapoff -a; free -g";done
}

## OUTILS K8S
COMMAND_K8S_TOOLS_ZYPPER() {
sudo zypper -n in kubernetes1.18-client
}
COMMAND_K8S_TOOLS_YUM() {
sudo yum install -y kubectl
}

## CHECK FIREWALLD
COMMAND_FIREWALL() {
if [[ $pkg_mgr_type == 'zypper' ]]
then
	FIREWALL_SVC="firewalld"
elif [[ $pkg_mgr_type == 'yum' ]]
then
	FIREWALL_SVC="firewalld"
fi
for h in ${HOSTS[*]};do
ssh $h "
hostname -f
if sudo rpm -q $FIREWALL_SVC ; then
  echo "Arret et desactivation de firewalld..."
  sudo systemctl stop $FIREWALL_SVC
  sudo systemctl disable $FIREWALL_SVC
fi
"
done
hostname -f
if sudo rpm -q $FIREWALL_SVC ; then
  echo "Arret et desactivation de firewalld..."
  sudo systemctl stop $FIREWALL_SVC
  sudo systemctl disable $FIREWALL_SVC
fi
}

## CHECK DEFAULT GW EXISTS
DEFAULT_GW='172.16.0.254'
COMMAND_DEFAULT_GW() {
echo
for h in ${HOSTS[*]};do 
  ROUTE_TABLE=$(ssh $h cat /proc/net/route | awk '$2==00000000')
  CURRENT_GATEWAY=$(for i in `echo $ROUTE_TABLE | awk '{print $3}'| sed -E 's/(..)(..)(..)(..)/\4 \3 \2 \1/'`;do printf "%d." $((16#$i));done |sed 's/.$//';echo)
  #echo $CURRENT_GATEWAY
  echo ${bold};ssh $h hostname|tr -d "\n";echo -n ${normal};echo -n ": default gateway is${bold} $CURRENT_GATEWAY"${normal};
done
echo
echo "A Default Gateway should be set on all nodes (even if non-existent/non-working)"
}


##################### BEGIN PRE-CHECK PACKAGES ##################################
question_yn "$DESC_CHECK_PACKAGE" "COMMAND_CHECK_PACKAGE_RPM curl expect"
##################### END PRE-CHECK PACKAGES ####################################
#
#
##################### BEGIN SSH KEYS EXCHANGE ###################################
question_yn "$DESC_SSH_KEYS" COMMAND_SSH_KEYS
question_yn "$DESC_SSH_DEPLOY" COMMAND_SSH_DEPLOY
question_yn "$DESC_SSH_CONNECT_TEST" COMMAND_SSH_CONNECT_TEST
##################### END SSH KEYS EXCHANGE #####################################
#
#
##################### BEGIN PROXY ###############################################
if [[ $PROXY_DEPLOY == 1 ]]
then
question_yn "$DESC_COPY_PROXY_CA" COMMAND_COPY_PROXY_CA
question_yn "$DESC_SET_PROXY" COMMAND_SET_PROXY
fi
##################### END PROXY #################################################
#
##################### BEGIN FIREWALL#############################################
question_yn "$DESC_FIREWALL" COMMAND_FIREWALL
question_yn "$DESC_DEFAULT_GW" COMMAND_DEFAULT_GW
question_yn "$DESC_CHECK_TIME" COMMAND_CHECK_TIME
question_yn "$DESC_IPFORWARD_ACTIVATE" COMMAND_IPFORWARD_ACTIVATE
question_yn "$DESC_NO_SWAP" COMMAND_NO_SWAP
#
#
##################### BEGIN REPOS & BINARIES ####################################
if [[ $pkg_mgr_type == 'zypper' ]]
then 
question_yn "$DESC_REPOS" COMMAND_REPOS_ZYPPER
question_yn "$DESC_ADDREPOS" COMMAND_ADDREPOS_ZYPPER
question_yn "$DESC_NODES_UPDATE" COMMAND_NODES_UPDATE_ZYPPER
question_yn "$DESC_DOCKER_INSTALL" COMMAND_DOCKER_INSTALL_ZYPPER
question_yn "$DESC_CREATE_DOCKER_USER" COMMAND_CREATE_DOCKER_USER
question_yn "$DESC_K8S_TOOLS" COMMAND_K8S_TOOLS_ZYPPER

elif [[ $pkg_mgr_type == 'yum' ]]
then
question_yn "$DESC_REPOS" COMMAND_REPOS_YUM
#question_yn "$DESC_ADDREPOS" COMMAND_ADDREPOS_YUM
question_yn "$DESC_ADDREPOS_YUM_K8STOOLS" COMMAND_ADDREPOS_YUM_K8STOOLS
question_yn "$DESC_NODES_UPDATE" COMMAND_NODES_UPDATE_YUM
question_yn "$DESC_DOCKER_INSTALL_YUM" COMMAND_DOCKER_INSTALL_YUM
question_yn "$DESC_CREATE_DOCKER_USER" COMMAND_CREATE_DOCKER_USER
question_yn "$DESC_K8S_TOOLS" COMMAND_K8S_TOOLS_YUM
fi
##################### END REPOS & BINARIES ######################################
#
#
##################### BEGIN DOCKER PROXY SETTINGS ###############################
if [[ $PROXY_DEPLOY == 1 ]]
then
question_yn "$DESC_DOCKER_PROXY" COMMAND_DOCKER_PROXY
fi
##################### END DOCKER PROXY SETTINGS #################################
#
#
##################### BEGIN CHECK ACCESS ########################################
#question_yn "$DESC_CHECK_ACCESS" COMMAND_CHECK_ACCESS
##################### END CHECK ACCESS ##########################################

echo
echo "-- FIN --"
echo "Prochaine étape 02-rke_deploy.sh"
