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
DESC_SSH_CONNECT_TEST="Deploiement de la clef publique vers les noeuds?${bold}"
COMMAND_SSH_CONNECT_TEST() {
for h in ${HOSTS[*]}; do ssh $h "hostname -f" ; done;
}

## LISTE DES REPOSITORIES
DESC_REPOS="Liste des repos sur les noeuds${bold}"
COMMAND_REPOS() {
for h in ${HOSTS[*]}
  do ssh $h "echo && hostname -f && echo && zypper lr"; 
done
}

## ADDING REPOSITORIES
DESC_ADDREPOS="Ajout des repos containers-modules sur les noeuds${bold}"
COMMAND_ADDREPOS() {
for h in ${HOSTS[*]}
  do ssh $h "echo ; hostname -f ; echo ; zypper ref ; 
#zypper ar -G http://suma01/ks/dist/child/sle-module-containers15-sp2-pool-x86_64/sles15sp2 containers_product ; 
#zypper ar -G http://suma01/ks/dist/child/sle-module-containers15-sp2-updates-x86_64/sles15sp2 containers_updates" 
done
}

## ALL NODES UPDATE 
DESC_NODES_UPDATE="Mise à jour de tous les noeuds?${bold}"
COMMAND_NODES_UPDATE() {
for h in ${HOSTS[*]}
  do ssh $h "echo ; hostname -f ; echo ; zypper ref ; zypper --non-interactive up"
done;
for h in ${HOSTS[*]}
  do ssh $h "echo ; zypper ps" 
done
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
for h in ${HOSTS[*]}; do ssh $h "echo && hostname -f && ping -c1 $CEPH_MON1 > /dev/null  && echo 'Ceph Monitor 1: OK' || echo 'Ceph Monitor 1: FAIL'"; done;
}

## DOCKER INSTALL
DESC_DOCKER_INSTALL="Installation, activation et demarrage de Docker sur les noeuds?${bold}"
COMMAND_DOCKER_INSTALL() {
for h in ${HOSTS[*]}; do ssh $h "echo ; hostname -f ; zypper ref ; zypper --non-interactive in docker"; done;
for h in ${HOSTS[*]}; do ssh $h "echo ; hostname -f ; systemctl enable docker ; systemctl start docker ; echo "Docker is activated""; done;
}

question_yn "$DESC_SSH_KEYS" COMMAND_SSH_KEYS
question_yn "$DESC_SSH_DEPLOY" COMMAND_SSH_DEPLOY
question_yn "$DESC_SSH_CONNECT_TEST" COMMAND_SSH_CONNECT_TEST
question_yn "$DESC_REPOS" COMMAND_REPOS
question_yn "$DESC_ADDREPOS" COMMAND_ADDREPOS
question_yn "$DESC_NODES_UPDATE" COMMAND_NODES_UPDATE
question_yn "$DESC_CHECK_TIME" COMMAND_CHECK_TIME
question_yn "$DESC_CHECK_ACCESS" COMMAND_CHECK_ACCESS
question_yn "$DESC_DOCKER_INSTALL" COMMAND_DOCKER_INSTALL

echo
echo "-- FIN --"
echo "Prochaine étape XXX"
