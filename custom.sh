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

###
# Remove default GATEWAY
###
DESC_REMOVE_DEF_GW="Suppression de la gateway par défaut (tous les noeuds)?${bold}"
COMMAND_REMOVE_DEF_GW() {
if [[ $pkg_mgr_type == 'zypper' ]]
then
        # remote hosts - SLES
	for h in ${HOSTS[*]};do
	ssh $h "hostname
	sed -i -e '/default/ s/^#*/#/' /etc/sysconfig/network/routes
	systemctl restart network"
	done
	# local host - SLES
	sed -i -e '/default/ s/^#*/#/' /etc/sysconfig/network/routes
	systemctl restart network
elif [[ $pkg_mgr_type == 'yum' ]]
then
        # remote hosts - RHEL
	for h in ${HOSTS[*]};do
	ssh $h "hostname
	sed -i -e '/GATEWAY/ s/^#*/#/' /etc/sysconfig/network
	systemctl restart network"
	done
	# local host - RHEL
	sed -i -e '/GATEWAY/ s/^#*/#/' /etc/sysconfig/network
	systemctl restart network
fi
}
###
# Add default GATEWAY
###
NEW_DEF_GW="172.16.253.44"
DESC_ADD_DEF_GW="Ajout d'une default gateway (tous les noeuds) - Default GW=$NEW_DEF_GW?${bold}"
COMMAND_ADD_DEF_GW() {
if [[ $pkg_mgr_type == 'zypper' ]]
then
        # remote hosts - SLES
	for h in ${HOSTS[*]};do
	ssh $h "hostname
        echo "default $NEW_DEF_GW - -" >> /etc/sysconfig/network/routes
	systemctl restart network"
	done
	# local host - SLES
	echo "default $NEW_DEF_GW - -" >> /etc/sysconfig/network/routes
	systemctl restart network
elif [[ $pkg_mgr_type == 'yum' ]]
then
        # remote hosts - RHEL
	for h in ${HOSTS[*]};do
	ssh $h "hostname
	echo "GATEWAY=$NEW_DEF_GW" /etc/sysconfig/network
	systemctl restart network"
	done
	# local host - RHEL
	echo "GATEWAY=$NEW_DEF_GW" /etc/sysconfig/network
	systemctl restart network
fi
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
}
###
# Disable IPv6
###
DESC_REBOOT_ALL="Reboot des machines?${bold}"
COMMAND_REBOOT_ALL() {
# Reboot Machines ${HOSTS[*]}
for h in ${HOSTS[*]};do
ssh $h "hostname
reboot"
done
# Reboot machine locale
reboot
}

question_yn "$DESC_REMOVE_DEF_GW" COMMAND_REMOVE_DEF_GW
question_yn "$DESC_ADD_DEF_GW" COMMAND_ADD_DEF_GW
question_yn "$DESC_COPY_SQUID_CA" COMMAND_COPY_SQUID_CA
question_yn "$DESC_DISABLE_IPV6" COMMAND_DISABLE_IPV6
question_yn "$DESC_REBOOT_ALL" COMMAND_REBOOT_ALL

echo
echo "-- FIN --"
