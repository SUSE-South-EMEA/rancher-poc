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

###
# Remove default GATEWAY
###
DESC_REMOVE_DEF_GW="Suppression de la gateway par défaut (tous les noeuds)?${bold}"
COMMAND_REMOVE_DEF_GW() {
# remote hosts
for h in ${HOSTS[*]};do
ssh $h "hostname
sed -i -e '/GATEWAY/ s/^#*/#/' /etc/sysconfig/network
systemctl restart network"
done
# local host
sed -i -e '/GATEWAY/ s/^#*/#/' /etc/sysconfig/network
systemctl restart network
}

###
# Copy Squid proxyCA cert
###
DESC_COPY_SQUID_CA="Copie du CA SQUID vers les noeuds?${bold}"
COMMAND_COPY_SQUID_CA() {
# on local host from squid Proxy
scp squid:/etc/squid/ssl_cert/proxyCA.pem /etc/pki/ca-trust/source/anchors/
update-ca-trust
# on remote hosts from local host
for h in ${HOSTS[*]};do
scp /etc/pki/ca-trust/source/anchors/proxyCA.pem $h:/etc/pki/ca-trust/source/anchors/
ssh $h "hostname ; update-ca-trust"
done
}

###
# Disable IPv6
###
DESC_DISABLE_IPV6="Desactiver IPV6? (redemarrage necessaire!)${bold}"
COMMAND_DISABLE_IPV6() {
# remote hosts
for h in ${HOSTS[*]};do 
ssh $h "hostname
if grep ipv6.disable=1 /etc/default/grub ; then echo 'ipv6 already disabled'
else
sed -i 's/GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"ipv6.disable=1 /' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
fi"
done
# local host
if grep ipv6.disable=1 /etc/default/grub ; then
  echo 'ipv6 already disabled'
else
  sed -i 's/GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"ipv6.disable=1 /' /etc/default/grub
  grub2-mkconfig -o /boot/grub2/grub.cfg
fi

echo
echo "-- FIN --"
}
question_yn "$DESC_REMOVE_DEF_GW" COMMAND_REMOVE_DEF_GW
question_yn "$DESC_COPY_SQUID_CA" COMMAND_COPY_SQUID_CA
question_yn "$DESC_DISABLE_IPV6" COMMAND_DISABLE_IPV6
echo
echo "-- FIN --"
