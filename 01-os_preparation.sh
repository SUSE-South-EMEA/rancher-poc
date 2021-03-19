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
      break;;
      [Nn]* ) echo "Etape annulee";break;;
      * ) echo "Please answer yes (y) or no (n).";;
    esac
done
}

## SSH KEYS CREATION
DESC_SSH_KEYS="Creation d'une paire de clefs SSH en local?${bold}"
COMMAND_SSH_KEYS() {
ssh-keygen
}

## SSH KEYS DEPLOY
DESC_SSH_DEPLOY="Deploiement de la clef publique vers les noeuds?${bold}"
COMMAND_SSH_DEPLOY() {
read -s -p "Veuillez entrer le mot de passe des clients : " PASSWD
for h in ${HOSTS[*]};
  do expect -c "set timeout 2; spawn ssh-copy-id -o StrictHostKeyChecking=no $h; expect 'assword:'; send "$PASSWD\\r"; interact"
done;
}

## SSH CONNECT TESTING
DESC_SSH_CONNECT_TEST="Test de connexion en masse?${bold}"
COMMAND_SSH_CONNECT_TEST() {
for h in ${HOSTS[*]}; do ssh $h "hostname -f" ; done;
}

## LISTE DES REPOSITORIES
DESC_REPOS="$pkg_mgr_type - Liste des repos sur les noeuds${bold}"
COMMAND_REPOS_ZYPPER() {
for h in ${HOSTS[*]}
  do ssh $h "echo && hostname -f && echo && zypper lr"; 
done
}
COMMAND_REPOS_YUM() {
for h in ${HOSTS[*]}
  do ssh $h "echo && hostname -f && echo && yum repolist all"; 
done
}

## ADDING REPOSITORIES
DESC_ADDREPOS="$pkg_mgr_type - Ajout des repos containers-modules sur les noeuds et en local?${bold}"
COMMAND_ADDREPOS_ZYPPER() {
for h in ${HOSTS[*]}
  do ssh $h "echo ; hostname -f ; echo ; zypper ref ; 
zypper ar -G http://suma01/ks/dist/child/sle-module-containers15-sp2-pool-x86_64/sles15sp2 containers_product ; 
zypper ar -G http://suma01/ks/dist/child/sle-module-containers15-sp2-updates-x86_64/sles15sp2 containers_updates" 
done
zypper ar -G http://suma01/ks/dist/child/sle-module-containers15-sp2-pool-x86_64/sles15sp2 containers_product
zypper ar -G http://suma01/ks/dist/child/sle-module-containers15-sp2-updates-x86_64/sles15sp2 containers_updates
}

COMMAND_ADDREPOS_YUM() {

for h in ${HOSTS[*]}
  do ssh $h "echo ; hostname -f ; echo
cat  > /etc/yum.repos.d/res7.repo <<EOF
[res7]
name=res7
baseurl=http://suma01/ks/dist/child/res7-x86_64/rhel76
enabled=1
gpgcheck=0
EOF
cat  > /etc/yum.repos.d/res7-iso.repo <<EOF
[res7-iso]
name=res7.6-ISO
baseurl=http://suma01/ks/dist/child/rhel76-iso/rhel76
enabled=1
gpgcheck=0
EOF
cat  > /etc/yum.repos.d/res7-suma.repo <<EOF
[res7-SUMA]
name=res7-SUMA_BOOTSTRAP
baseurl=http://suma01/ks/dist/child/res7-suse-manager-tools-x86_64/rhel76
enabled=1
gpgcheck=0
EOF"
done
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
}

## ALL NODES UPDATE 
DESC_NODES_UPDATE="$pkg_mgr_type - Mise à jour de tous les noeuds?${bold}"
COMMAND_NODES_UPDATE_ZYPPER() {
for h in ${HOSTS[*]}
  do ssh $h "echo ; hostname -f ; echo ; zypper ref ; zypper --non-interactive up"
done;
for h in ${HOSTS[*]}
  do ssh $h "echo ; zypper ps" 
done
}

COMMAND_NODES_UPDATE_YUM() {
for h in ${HOSTS[*]}
  do ssh $h "echo ; hostname -f ; echo ; yum clean all ; yum -y update"
done;
}

## CHECK TIME
DESC_CHECK_TIME="Verification de la date & heure sur les noeuds?${bold}"
COMMAND_CHECK_TIME() {
for h in ${HOSTS[*]}; do ssh $h "echo && hostname -f && chronyc sources"; done;
}

## CHECK ACCESS - INTERNET/PROXY/REGISTRY
DESC_CHECK_ACCESS="Verification de l'acces depuis les noeuds au reseau public et de stockage?${bold}"
COMMAND_CHECK_ACCESS() {
echo -e "Reseau Public (registry.suse.com):"
for h in ${HOSTS[*]}; do ssh $h "echo && hostname -f && ping -c1 registry.suse.com > /dev/null  && echo 'registry.suse.com: OK' || echo 'registry.suse.com: FAIL'"; done;
echo
echo -e "Reseau de Stockage:"
echo -e "Sauf pour la machine admin (isolation réseau)"
for h in ${HOSTS[*]}; do ssh $h "echo && hostname -f && ping -c1 $STORAGE_TARGET > /dev/null  && echo 'Acces Stockage: OK' || echo 'Acces Stockage: FAIL'"; done;
}

## DOCKER INSTALL
DESC_DOCKER_INSTALL="$pkg_mgr_type - Installation, activation et demarrage de Docker sur les noeuds?${bold}"
COMMAND_DOCKER_INSTALL_ZYPPER() {
for h in ${HOSTS[*]}; do ssh $h "echo ; hostname -f ; zypper ref ; zypper --non-interactive in docker"; done;
for h in ${HOSTS[*]}; do ssh $h "echo ; hostname -f ; systemctl enable docker ; systemctl start docker ; echo "Docker is activated""; done;
}
COMMAND_DOCKER_INSTALL_YUM() {
for h in ${HOSTS[*]}; do ssh $h "echo ; hostname -f ; yum clean all ; yum install -y docker"; done;
for h in ${HOSTS[*]}; do ssh $h "echo ; hostname -f ; systemctl enable docker ; systemctl start docker ; echo "Docker is activated""; done;
}

## ACTIVATION IP FORWARDING
DESC_IPFORWARD_ACTIVATE="Activation de l'IP forwarding?${bold}"
COMMAND_IPFORWARD_ACTIVATE() {
  for h in ${HOSTS[*]}; do ssh $h "echo; hostname -f; sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/g' /etc/sysctl.conf; sed '/^#/d' /etc/sysctl.conf" ; done
}

## DESACTIVATION DU SWAP
DESC_NO_SWAP="Desactivation du swap?${bold}"
COMMAND_NO_SWAP() {
for h in ${HOSTS[*]};do ssh $h 'sed -i "/swap/ s/defaults/&,noauto/" /etc/fstab';done
for h in ${HOSTS[*]};do ssh $h "echo; hostname -f; grep swap /etc/fstab; swapoff -a; free -g";done
}

## OUTILS K8S
DESC_K8S_TOOLS="$pkg_mgr_type - Installation des outils Kubernetes en local?${bold}"
COMMAND_K8S_TOOLS_ZYPPER() {
zypper -n in kubernetes1.18-client
}
COMMAND_K8S_TOOLS_YUM() {
yum install -y kubectl
}

question_yn "$DESC_SSH_KEYS" COMMAND_SSH_KEYS
question_yn "$DESC_SSH_DEPLOY" COMMAND_SSH_DEPLOY
question_yn "$DESC_SSH_CONNECT_TEST" COMMAND_SSH_CONNECT_TEST

if [[ $pkg_mgr_type == 'zypper' ]]
then 
question_yn "$DESC_REPOS" COMMAND_REPOS_ZYPPER
question_yn "$DESC_ADDREPOS" COMMAND_ADDREPOS_ZYPPER
question_yn "$DESC_NODES_UPDATE" COMMAND_NODES_UPDATE_ZYPPER
question_yn "$DESC_DOCKER_INSTALL" COMMAND_DOCKER_INSTALL_ZYPPER
question_yn "$DESC_K8S_TOOLS" COMMAND_K8S_TOOLS_ZYPPER

elif [[ $pkg_mgr_type == 'yum' ]]
then
question_yn "$DESC_REPOS" COMMAND_REPOS_YUM
question_yn "$DESC_ADDREPOS" COMMAND_ADDREPOS_YUM
question_yn "$DESC_NODES_UPDATE" COMMAND_NODES_UPDATE_YUM
question_yn "$DESC_DOCKER_INSTALL" COMMAND_DOCKER_INSTALL_YUM
question_yn "$DESC_K8S_TOOLS" COMMAND_K8S_TOOLS_YUM
fi

question_yn "$DESC_CHECK_TIME" COMMAND_CHECK_TIME
question_yn "$DESC_CHECK_ACCESS" COMMAND_CHECK_ACCESS
question_yn "$DESC_IPFORWARD_ACTIVATE" COMMAND_IPFORWARD_ACTIVATE
question_yn "$DESC_NO_SWAP" COMMAND_NO_SWAP

echo
echo "-- FIN --"
echo "Prochaine étape 02-rke_deploy.sh"
