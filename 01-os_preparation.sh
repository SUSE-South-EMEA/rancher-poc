#!/bin/bash

### Source variables
source ./00-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh

# Select package manager to use for next steps
while true; do
   read -p "${bold}Package manager type? (zypper/yum/apt) ${normal}" pkg_mgr_type
   case $pkg_mgr_type in
      zypper )
            echo "$pkg_mgr_type selected."
            echo
            break;;
      yum ) 
            echo "$pkg_mgr_type selected."
            echo
	    break;;
      apt ) 
            echo "$pkg_mgr_type selected."
            echo
	    break;;
      * ) echo "Please answer: zypper or yum or apt.";;
    esac
done

## SSH KEYS CREATION
COMMAND_SSH_KEYS() {
ssh-keygen
}

## SSH KEYS DEPLOY
COMMAND_SSH_DEPLOY() {
read -s -p "${TXT_ENTER_CLIENT_PWD:=Please enter target hosts SSH password}: " PASSWD
for h in "${HOSTS[@]}";
  do
    if [[ -n "${SSH_USER:-}" ]]; then
      expect -c "set timeout 2; spawn ssh-copy-id -o StrictHostKeyChecking=no ${SSH_USER}@$h; expect 'assword:'; send "$PASSWD\\r"; interact"
    else
      expect -c "set timeout 2; spawn ssh-copy-id -o StrictHostKeyChecking=no $h; expect 'assword:'; send "$PASSWD\\r"; interact"
    fi
done;
unset PASSWD
}

## SSH CONNECT TESTING
COMMAND_SSH_CONNECT_TEST() {
for h in "${HOSTS[@]}"; do ssh_host "$h" "hostname -f" ; done;
echo "Domain in use must not be using *.local !!!"
}

## SET PROXY
COMMAND_SET_PROXY() {
# Configure proxy on hosts
for h in "${HOSTS[@]}"
  do
ssh_host "$h" "sudo tee /etc/profile.d/proxy.sh <<EOF
export http_proxy=http://${_HTTP_PROXY}
export https_proxy=http://${_HTTPS_PROXY}
export no_proxy=${_NO_PROXY}
EOF
hostname -f
echo 'Proxy parameters added to /etc/profile.d/proxy.sh'
echo"
done
# Configure proxy on deploy node
sudo tee /etc/profile.d/proxy.sh <<EOF
export http_proxy=http://${_HTTP_PROXY}
export https_proxy=http://${_HTTPS_PROXY}
export no_proxy=${_NO_PROXY}
EOF
sudo chmod 0755 /etc/profile.d/proxy.sh
source /etc/profile.d/proxy.sh
echo "$(hostname -f) : Proxy parameters added to /etc/profile.d/proxy.sh"
}

## LIST REPOSITORIES
COMMAND_REPOS_ZYPPER() {
for h in "${HOSTS[@]}"
  do ssh_host "$h" "echo && hostname -f && echo && sudo zypper lr"; 
done
}
COMMAND_REPOS_YUM() {
for h in "${HOSTS[@]}"
  do ssh_host "$h" "echo && hostname -f && echo && sudo yum repolist all"; 
done
}
COMMAND_REPOS_APT() {
for h in "${HOSTS[@]}"
  do ssh_host "$h" "echo && hostname -f && echo && sudo apt-cache policy"; 
done
}

## ADDING REPOSITORIES
COMMAND_ADDREPOS_ZYPPER() {
for h in "${HOSTS[@]}"
  do ssh_host "$h" "echo ; hostname -f ; echo ; sudo zypper ref ; 
sudo zypper ar -G http://${REPO_SERVER}/ks/dist/child/sle-module-containers15-sp4-pool-x86_64/sles15sp4 containers_product ; 
sudo zypper ar -G http://${REPO_SERVER}/ks/dist/child/sle-module-containers15-sp4-updates-x86_64/sles15sp4 containers_updates" 
done
sudo zypper ar -G http://${REPO_SERVER}/ks/dist/child/sle-module-containers15-sp4-pool-x86_64/sles15sp4 containers_product
sudo zypper ar -G http://${REPO_SERVER}/ks/dist/child/sle-module-containers15-sp4-updates-x86_64/sles15sp4 containers_updates
}

## ALL NODES UPDATE 
COMMAND_NODES_UPDATE_ZYPPER() {
for h in "${HOSTS[@]}"
  do ssh_host "$h" "echo ; hostname -f ; echo ; sudo zypper ref ; sudo zypper --non-interactive up"
done;
for h in "${HOSTS[@]}"
  do ssh_host "$h" "echo ; sudo zypper ps" 
done
}

COMMAND_NODES_UPDATE_YUM() {
for h in "${HOSTS[@]}"
  do ssh_host "$h" "echo ; hostname -f ; echo ; sudo yum -y update"
done;
}

COMMAND_NODES_UPDATE_APT() {
for h in "${HOSTS[@]}"
  do ssh_host "$h" "echo ; hostname -f ; echo ; sudo apt-get -y upgrade"
done;
}

## CHECK TIME
COMMAND_CHECK_TIME() {
for h in "${HOSTS[@]}"; do
  echo -e "\n${bold}$h${normal}"
  ssh_host "$h" "hostname -f &&
	  if which chronyc >/dev/null 2>&1 ; then 
	    echo '${TXT_CHECK_TIME_CHRONY_INFO:=Chrony time synchronization status:}' ; 
	    REF_ID=\$(sudo chronyc -a tracking | grep 'Reference ID' | awk '{print \$4, \$5, \$6, \$7}') ; 
	    LEAP_STATUS=\$(sudo chronyc -a tracking | grep 'Leap status' | awk '{print \$3, \$4, \$5, \$6}') ; 
	    echo \"  Reference ID: \$REF_ID\" ; 
	    echo \"  Leap Status: \$LEAP_STATUS\" ; 
	    sudo chronyc -a tracking | grep -E '(Reference time|System time|Last offset|RMS offset|Frequency|Stratum)'
 	  elif which ntpq >/dev/null 2>&1 ; then 
	    echo '${TXT_CHECK_TIME_NTPQ_INFO:=NTP time synchronization status:}' ; 
	    sudo ntpq -p
    elif which timedatectl >/dev/null 2>&1 ; then 
	    echo '${TXT_CHECK_TIME_TIMEDATECTL_INFO:=System time status:}' ; 
	    sudo timedatectl | grep -E '(System clock synchronized|NTP service|RTC in local TZ)'
	  else 
	    echo '${TXT_CHECK_TIME:=Chronyc or ntpq binaries are not present. Cannot check if time is synchronized.}'
	  fi"
done
echo -e "\n${bold}$(hostname -f)${normal} (local node)"
if which chronyc >/dev/null 2>&1 ; then
  echo "${TXT_CHECK_TIME_CHRONY_INFO:=Chrony time synchronization status:}"
  REF_ID=$(sudo chronyc -a tracking | grep 'Reference ID' | awk '{print $4, $5, $6, $7}')
  LEAP_STATUS=$(sudo chronyc -a tracking | grep 'Leap status' | awk '{print $3, $4, $5, $6}')
  echo "  Reference ID: $REF_ID"
  echo "  Leap Status: $LEAP_STATUS"
  sudo chronyc -a tracking | grep -E '(Reference time|System time|Last offset|RMS offset|Frequency|Stratum)'
elif which ntpq >/dev/null 2>&1 ; then
  echo "${TXT_CHECK_TIME_NTPQ_INFO:=NTP time synchronization status:}"
  sudo ntpq -p
elif which timedatectl >/dev/null 2>&1 ; then
  echo "${TXT_CHECK_TIME_TIMEDATECTL_INFO:=System time status:}"
  sudo timedatectl | grep -E '(System clock synchronized|NTP service|RTC in local TZ)'
else
  echo "${TXT_CHECK_TIME:=Chronyc or ntpq binaries are not present. Cannot check if time is synchronized.}"
fi
}

## CHECK ACCESS - INTERNET/PROXY/REGISTRY
COMMAND_CHECK_ACCESS_REGISTRY() {
if [ "${AIRGAP_REGISTRY_INSECURE}" == "1" ] ; then
  for h in "${HOSTS[@]}"; do
    ssh_host "$h" "echo && hostname -f && curl -k -s -o /dev/null -I https://${AIRGAP_REGISTRY_URL}  && echo '${AIRGAP_REGISTRY_URL}: OK' || echo '${AIRGAP_REGISTRY_URL}: FAIL'"
  done
  echo
elif [[ ! -z ${AIRGAP_REGISTRY_CACERT} ]] ; then
  for h in "${HOSTS[@]}"; do
    ssh_host "$h" "echo && hostname -f && curl -s -o /dev/null -I --cacert /etc/docker/certs.d/${AIRGAP_REGISTRY_URL}/ca.crt  https://${AIRGAP_REGISTRY_URL}  && echo '${AIRGAP_REGISTRY_URL}: OK' || echo '${AIRGAP_REGISTRY_URL}: FAIL'"
  done
  echo
else
  for h in "${HOSTS[@]}"; do
    ssh_host "$h" "echo && hostname -f && curl -s -o /dev/null -I https://${AIRGAP_REGISTRY_URL}  && echo '${AIRGAP_REGISTRY_URL}: OK' || echo '${AIRGAP_REGISTRY_URL}: FAIL'"
  done
  echo
fi
}

## ACTIVATION IP FORWARDING
COMMAND_IPFORWARD_ACTIVATE() {
for h in "${HOSTS[@]}";do 
  echo -e "\n${bold}$h${normal}"
  ssh_host "$h" "echo; hostname -f ; sudo sed -i '/net.ipv4.ip_forward.*/d' /etc/sysctl.conf ; if [ -d /etc/sysctl.d ] && [ -n \"\$(ls -A /etc/sysctl.d/*.conf 2>/dev/null)\" ] ; then sudo sed -i '/net.ipv4.ip_forward.*/d' /etc/sysctl.d/*.conf ; fi ; echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf ; sudo sysctl -p"
done
echo -e "\n${bold}$(hostname -f)${normal} (local node)"
sudo sed -i '/net.ipv4.ip_forward.*/d' /etc/sysctl.conf
if [ -d /etc/sysctl.d ] && [ -n "$(ls -A /etc/sysctl.d/*.conf 2>/dev/null)" ]; then
  sudo sed -i '/net.ipv4.ip_forward.*/d' /etc/sysctl.d/*.conf
fi
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
}

## DESACTIVATION DU SWAP
COMMAND_NO_SWAP() {
for h in "${HOSTS[@]}";do ssh_host "$h" 'sudo sed -i "/swap/ s/defaults/&,noauto/" /etc/fstab';done
for h in "${HOSTS[@]}";do ssh_host "$h" "echo; hostname -f; grep swap /etc/fstab; sudo swapoff -a; free -g";done
}

## OUTILS K8S
COMMAND_INSTALL_KUBECTL() {
if [[ $AIRGAP_DEPLOY != 1 ]] ; then
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
fi
sudo install -v -o root -g root -m 0755 kubectl /usr/bin/kubectl
}

## CHECK FIREWALLD
COMMAND_FIREWALL() {
if [[ $pkg_mgr_type == 'zypper' ]]
then
	FIREWALL_SVC="firewalld"
	CHECK_CMD="rpm -q"
elif [[ $pkg_mgr_type == 'yum' ]]
then
	FIREWALL_SVC="firewalld"
	CHECK_CMD="rpm -q"
elif [[ $pkg_mgr_type == 'apt' ]]
then
	FIREWALL_SVC="ufw"
	CHECK_CMD="dpkg-query -W"
fi
for h in "${HOSTS[@]}";do
  echo -e "\n${bold}$h${normal}"
  ssh_host "$h" "hostname -f && if sudo $CHECK_CMD $FIREWALL_SVC >/dev/null 2>&1 ; then echo \"${TXT_FIREWALLD_FOUND:=Firewall service} $FIREWALL_SVC ${TXT_IS_PRESENT:=is present}.\" ; if sudo systemctl is-active --quiet $FIREWALL_SVC ; then echo \"${TXT_FIREWALLD_ACTIVE:=Firewall is active. Stopping and disabling...}\" ; sudo systemctl stop $FIREWALL_SVC && sudo systemctl disable $FIREWALL_SVC && echo \"${TXT_FIREWALLD_DISABLED:=Firewall has been stopped and disabled.}\" ; else echo \"${TXT_FIREWALLD_INACTIVE:=Firewall is already stopped. Disabling...}\" ; sudo systemctl disable $FIREWALL_SVC && echo \"${TXT_FIREWALLD_DISABLED:=Firewall has been disabled.}\" ; fi ; else echo \"${TXT_FIREWALLD_NOT_INSTALLED:=Firewall service} $FIREWALL_SVC ${TXT_NOT_PRESENT:=is absent}. ${TXT_FIREWALLD_NOT_INSTALLED_MSG:=Nothing to do.}\" ; fi"
done
echo -e "\n${bold}$(hostname -f)${normal} (local node)"
if sudo $CHECK_CMD $FIREWALL_SVC >/dev/null 2>&1 ; then
  echo "${TXT_FIREWALLD_FOUND:=Firewall service} $FIREWALL_SVC ${TXT_IS_PRESENT:=is present}."
  if sudo systemctl is-active --quiet $FIREWALL_SVC ; then
    echo "${TXT_FIREWALLD_ACTIVE:=Firewall is active. Stopping and disabling...}"
    sudo systemctl stop $FIREWALL_SVC && sudo systemctl disable $FIREWALL_SVC && echo "${TXT_FIREWALLD_DISABLED:=Firewall has been stopped and disabled.}"
  else
    echo "${TXT_FIREWALLD_INACTIVE:=Firewall is already stopped. Disabling...}"
    sudo systemctl disable $FIREWALL_SVC && echo "${TXT_FIREWALLD_DISABLED:=Firewall has been disabled.}"
  fi
else
  echo "${TXT_FIREWALLD_NOT_INSTALLED:=Firewall service} $FIREWALL_SVC ${TXT_NOT_PRESENT:=is absent}. ${TXT_FIREWALLD_NOT_INSTALLED_MSG:=Nothing to do.}"
fi
}

## CHECK DEFAULT GW EXISTS
COMMAND_DEFAULT_GW() {
echo
for h in "${HOSTS[@]}";do 
  ROUTE_TABLE=$(ssh_host "$h" "cat /proc/net/route" | awk '$2==00000000')
  CURRENT_GATEWAY=$(for i in `echo $ROUTE_TABLE | awk '{print $3}'| sed -E 's/(..)(..)(..)(..)/\4 \3 \2 \1/'`;do printf "%d." $((16#$i));done |sed 's/.$//';echo)
  #echo $CURRENT_GATEWAY
  echo ${bold};ssh_host "$h" "hostname"|tr -d "\n";echo -n ${normal};echo -n ": default gateway is${bold} $CURRENT_GATEWAY"${normal};
done
echo
echo "A Default Gateway should be set on all nodes (even if non-existent/non-working)"
}

## LONGHORN
COMMAND_INSTALL_LONGHORN_PREREQ() {
if [[ $pkg_mgr_type == 'zypper' ]] ; then
  for h in "${HOSTS[@]}"; do
    echo ; echo "${bold}${h}${normal}"
    ssh_host "$h" "sudo zypper in -y open-iscsi nfs-client ; sudo systemctl enable --now iscsid.service"
  done
elif [[ $pkg_mgr_type == 'yum' ]] ; then
  for h in "${HOSTS[@]}"; do
    echo ; echo "${bold}${h}${normal}"
    ssh_host "$h" "sudo yum install -y iscsi-initiator-utils nfs-utils"
  done
elif [[ $pkg_mgr_type == 'apt' ]] ; then
  for h in "${HOSTS[@]}"; do
    echo ; echo "${bold}${h}${normal}"
    ssh_host "$h" "sudo apt-get install -y open-iscsi nfs-common ; sudo systemctl enable --now iscsid.service"
  done
else
  echo "Unknow package manager type. Exiting..." && exit 1
fi
}

##################### BEGIN PRE-CHECK LOCAL PACKAGES ##################################
if [[ $pkg_mgr_type == 'apt' ]]
then
  question_yn "${DESC_CHECK_PACKAGE:=Local deployment system : check if required packages are installed?}" "COMMAND_CHECK_PACKAGE_DPKG_LOCAL curl expect sudo"
else
  question_yn "${DESC_CHECK_PACKAGE_RPM_LOCAL:=Local deployment system : check if required packages are installed?}" "COMMAND_CHECK_PACKAGE_RPM_LOCAL curl expect sudo"
fi
##################### END PRE-CHECK LOCAL PACKAGES ####################################
#
#
##################### BEGIN SSH KEYS EXCHANGE ###################################
question_yn "${DESC_SSH_KEYS:=Create a local SSH key pair?}" COMMAND_SSH_KEYS
question_yn "${DESC_SSH_DEPLOY:=Push public key to nodes?}" COMMAND_SSH_DEPLOY
question_yn "${DESC_SSH_CONNECT_TEST:=Test SSH connection to nodes?}" COMMAND_SSH_CONNECT_TEST
##################### END SSH KEYS EXCHANGE #####################################
#
#
##################### BEGIN PRE-CHECK PACKAGES ##################################
if [[ $pkg_mgr_type == 'apt' ]]
then
  question_yn "${DESC_CHECK_PACKAGE:=Check if required packages are installed?}" "COMMAND_CHECK_PACKAGE_DPKG iptables apparmor sudo"
else
  question_yn "${DESC_CHECK_PACKAGE_RPM:=Check if required packages are installed?}" "COMMAND_CHECK_PACKAGE_RPM iptables apparmor-parser sudo lsof"
fi
##################### END PRE-CHECK PACKAGES ####################################
#
#
##################### BEGIN PROXY ###############################################
if [[ $PROXY_DEPLOY == 1 ]]
then
question_yn "${DESC_SET_PROXY:=PROXY variables are set in ./00-vars.sh. Apply parameters ? \n _HTTP_PROXY=${_HTTP_PROXY} \n _HTTPS_PROXY=${_HTTPS_PROXY} \n _NO_PROXY=${_NO_PROXY}}" COMMAND_SET_PROXY
fi
##################### END PROXY #################################################
#
##################### BEGIN OS REQUIREMENTS #####################################
question_yn "$pkg_mgr_type - ${DESC_FIREWALL:=Check firewalld status (must be disabled)?}" COMMAND_FIREWALL
question_yn "${DESC_DEFAULT_GW:=Check for a defined default gateway?}" COMMAND_DEFAULT_GW
question_yn "${DESC_CHECK_TIME:=Verify date and time on all nodes?}" COMMAND_CHECK_TIME
question_yn "${DESC_IPFORWARD_ACTIVATE:=Enable IP forwarding?}" COMMAND_IPFORWARD_ACTIVATE
#question_yn "${DESC_NO_SWAP:=Disable swap on target nodes?}" COMMAND_NO_SWAP
##################### END OS REQUIREMENTS #######################################
#
#
##################### BEGIN REPOS & BINARIES ####################################
if [[ $pkg_mgr_type == 'zypper' ]]
then 
question_yn "$pkg_mgr_type - ${DESC_REPOS:=List repositories on nodes}" COMMAND_REPOS_ZYPPER
#question_yn "$pkg_mgr_type - ${DESC_ADDREPOS:=Add sle-module-containers repositories on target and local nodes?}" COMMAND_ADDREPOS_ZYPPER
question_yn "${DESC_NODES_UPDATE:=Update all nodes?}" COMMAND_NODES_UPDATE_ZYPPER

elif [[ $pkg_mgr_type == 'yum' ]]
then
question_yn "$DESC_REPOS" COMMAND_REPOS_YUM
question_yn "$pkg_mgr_type - ${DESC_NODES_UPDATE:=Update all nodes?}" COMMAND_NODES_UPDATE_YUM

elif [[ $pkg_mgr_type == 'apt' ]]
then
question_yn "$DESC_REPOS" COMMAND_REPOS_APT
question_yn "$pkg_mgr_type - ${DESC_NODES_UPDATE:=Update all nodes?}" COMMAND_NODES_UPDATE_APT
fi

question_yn "${DESC_INSTALL_KUBECTL:=Install kubectl on local node?}" COMMAND_INSTALL_KUBECTL
##################### END REPOS & BINARIES ######################################
#
#
##################### BEGIN AIRGAP ##############################################
if [[ $AIRGAP_DEPLOY == 1 ]] ; then
  question_yn "Airgap - ${DESC_CHECK_ACCESS_REGISTRY:=Check ${AIRGAP_REGISTRY_URL} is accessible from all nodes?}" COMMAND_CHECK_ACCESS_REGISTRY
fi
##################### END AIRGAP ################################################
#
#
##################### BEGIN LONGHORN REQUIREMENTS ################################
question_yn "${DESC_INSTALL_LONGHORN_PREREQ:=Install Longhorn pre-requisites (open-iscsi) on all nodes?}" COMMAND_INSTALL_LONGHORN_PREREQ
##################### END LONGHORN REQUIREMENTS ##################################

echo
echo "-- ${TXT_END:=END} --"
echo "${TXT_NEXT_STEP:=Next step} 02-rke2_deploy.sh"
