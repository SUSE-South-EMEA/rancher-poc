#!/bin/bash

### Source variables
source ./00-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh

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
# Mass Reboot
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
question_yn "$DESC_DISABLE_IPV6" COMMAND_DISABLE_IPV6
question_yn "$DESC_REBOOT_ALL" COMMAND_REBOOT_ALL

echo
echo "-- ${TXT_END:=END} --"
