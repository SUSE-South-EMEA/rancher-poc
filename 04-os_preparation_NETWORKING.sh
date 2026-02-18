#!/bin/bash

### Source variables
source ./01-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh
init_common

# Detect package manager (replaces manual while/read loop)
detect_pkg_manager

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
hostname
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
echo "$(hostname) : Proxy parameters added to /etc/profile.d/proxy.sh"
}


## CHECK TIME
COMMAND_CHECK_TIME() {
for h in "${HOSTS[@]}"; do
  echo -e "\n${bold}$h${normal}"
  ssh_host "$h" "if which chronyc >/dev/null 2>&1 ; then echo \"${TXT_CHECK_TIME_CHRONY_INFO:=Chrony time synchronization status:}\" ; REF_ID=\$(sudo chronyc -a tracking | grep 'Reference ID' | awk '{print \$4, \$5, \$6, \$7}') ; LEAP_STATUS=\$(sudo chronyc -a tracking | grep 'Leap status' | awk '{print \$3, \$4, \$5, \$6}') ; echo \"  Reference ID: \$REF_ID\" ; echo \"  Leap Status: \$LEAP_STATUS\" ; sudo chronyc -a tracking | grep -E 'Reference time|System time|Last offset|RMS offset|Frequency|Stratum' ; elif which ntpq >/dev/null 2>&1 ; then echo \"${TXT_CHECK_TIME_NTPQ_INFO:=NTP time synchronization status:}\" ; sudo ntpq -p ; elif which timedatectl >/dev/null 2>&1 ; then echo \"${TXT_CHECK_TIME_TIMEDATECTL_INFO:=System time status:}\" ; sudo timedatectl | grep -E 'System clock synchronized|NTP service|RTC in local TZ' ; else echo \"${TXT_CHECK_TIME:=Chronyc or ntpq binaries are not present. Cannot check if time is synchronized.}\" ; fi"
done
}

## CHECK ACCESS - INTERNET/PROXY/REGISTRY
COMMAND_CHECK_ACCESS_REGISTRY() {
if [ "${AIRGAP_REGISTRY_INSECURE}" == "1" ] ; then
  for h in "${HOSTS[@]}"; do
    ssh_host "$h" "echo && hostname && curl -k -s -o /dev/null -I https://${AIRGAP_REGISTRY_URL}  && echo '${AIRGAP_REGISTRY_URL}: OK' || echo '${AIRGAP_REGISTRY_URL}: FAIL'"
  done
  echo
elif [[ ! -z ${AIRGAP_REGISTRY_CACERT} ]] ; then
  for h in "${HOSTS[@]}"; do
    ssh_host "$h" "echo && hostname && curl -s -o /dev/null -I --cacert /etc/docker/certs.d/${AIRGAP_REGISTRY_URL}/ca.crt  https://${AIRGAP_REGISTRY_URL}  && echo '${AIRGAP_REGISTRY_URL}: OK' || echo '${AIRGAP_REGISTRY_URL}: FAIL'"
  done
  echo
else
  for h in "${HOSTS[@]}"; do
    ssh_host "$h" "echo && hostname && curl -s -o /dev/null -I https://${AIRGAP_REGISTRY_URL}  && echo '${AIRGAP_REGISTRY_URL}: OK' || echo '${AIRGAP_REGISTRY_URL}: FAIL'"
  done
  echo
fi
}

## ACTIVATION IP FORWARDING
COMMAND_IPFORWARD_ACTIVATE() {
for h in "${HOSTS[@]}";do
  echo -e "\n${bold}$h${normal}"
  ssh_host "$h" "if [ -f /etc/sysctl.conf ] ; then sudo sed -i '/net.ipv4.ip_forward.*/d' /etc/sysctl.conf ; fi ; if [ -d /etc/sysctl.d ] && [ -n \"\$(ls -A /etc/sysctl.d/*.conf 2>/dev/null)\" ] ; then sudo sed -i '/net.ipv4.ip_forward.*/d' /etc/sysctl.d/*.conf ; fi ; if [ -f /etc/sysctl.conf ] ; then echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf >/dev/null ; else echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.conf >/dev/null ; fi ; sudo sysctl -p 2>/dev/null | grep -v '^$' || echo 'IP forwarding enabled'"
done
}

## DESACTIVATION DU SWAP
COMMAND_NO_SWAP() {
for h in "${HOSTS[@]}";do ssh_host "$h" 'sudo sed -i "/swap/ s/defaults/&,noauto/" /etc/fstab';done
for h in "${HOSTS[@]}";do ssh_host "$h" "echo; hostname; grep swap /etc/fstab; sudo swapoff -a; free -g";done
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
  ssh_host "$h" "if sudo $CHECK_CMD $FIREWALL_SVC >/dev/null 2>&1 ; then echo \"${TXT_FIREWALLD_FOUND:=Firewall service} $FIREWALL_SVC ${TXT_IS_PRESENT:=is present}.\" ; if sudo systemctl is-active --quiet $FIREWALL_SVC ; then echo \"${TXT_FIREWALLD_ACTIVE:=Firewall is active. Stopping and disabling...}\" ; sudo systemctl stop $FIREWALL_SVC && sudo systemctl disable $FIREWALL_SVC && echo \"${TXT_FIREWALLD_DISABLED:=Firewall has been stopped and disabled.}\" ; else echo \"${TXT_FIREWALLD_INACTIVE:=Firewall is already stopped. Disabling...}\" ; sudo systemctl disable $FIREWALL_SVC && echo \"${TXT_FIREWALLD_DISABLED:=Firewall has been disabled.}\" ; fi ; else echo \"${TXT_FIREWALLD_NOT_INSTALLED:=Firewall service} $FIREWALL_SVC ${TXT_NOT_PRESENT:=is absent}. ${TXT_FIREWALLD_NOT_INSTALLED_MSG:=Nothing to do.}\" ; fi"
done
echo -e "\n${bold}$(hostname)${normal} (local node)"
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
echo "Note: a Default Gateway should be set on all nodes (even if non-existent/non-working)"
}


##################### BEGIN SSH KEYS EXCHANGE ###################################
question_yn "${DESC_SSH_CONNECT_TEST:=Test SSH connection to nodes?}" COMMAND_SSH_CONNECT_TEST
##################################################################################


###################### BEGIN PROXY ###############################################
if [[ $PROXY_DEPLOY == 1 ]]
then
question_yn "${DESC_SET_PROXY:=PROXY variables are set in ./01-vars.sh. Apply parameters ? \n _HTTP_PROXY=${_HTTP_PROXY} \n _HTTPS_PROXY=${_HTTPS_PROXY} \n _NO_PROXY=${_NO_PROXY}}" COMMAND_SET_PROXY
fi


###################### BEGIN FIREWALL############################################
question_yn "${DESC_FIREWALL:=Check firewall status (must be disabled)?}" COMMAND_FIREWALL


###################### CHECK DEFAULT GATEWAY #####################################
question_yn "${DESC_DEFAULT_GW:=Check for a defined default gateway?}" COMMAND_DEFAULT_GW


###################### CHECK IP FORWARDING ENABLED ###############################
question_yn "${DESC_IPFORWARD_ACTIVATE:=Enable IP forwarding?}" COMMAND_IPFORWARD_ACTIVATE


###################### CHECK TIME SYNC ###########################################
question_yn "${DESC_CHECK_TIME:=Verify date and time on all nodes?}" COMMAND_CHECK_TIME


###################### DISABLE SWAP ##############################################
#question_yn "${DESC_NO_SWAP:=Disable swap on target nodes?}" COMMAND_NO_SWAP
##################################################################################


###################### BEGIN AIRGAP ##############################################
if [[ $AIRGAP_DEPLOY == 1 ]] ; then
  question_yn "Airgap - ${DESC_CHECK_ACCESS_REGISTRY:=Check ${AIRGAP_REGISTRY_URL} is accessible from all nodes?}" COMMAND_CHECK_ACCESS_REGISTRY
fi
##################################################################################

propose_next_script "05-rke2_deploy.sh" "RKE2 cluster deployment"
