#!/bin/bash

### Source variables
source ./00-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh

# Select package manager to use for next steps
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

## SSH KEYS CREATION
COMMAND_SSH_KEYS() {
ssh-keygen
}

## SSH KEYS DEPLOY
COMMAND_SSH_DEPLOY() {
read -s -p "${TXT_ENTER_CLIENT_PWD:=Please enter target hosts SSH password}: " PASSWD
for h in ${HOSTS[*]};
  do expect -c "set timeout 2; spawn ssh-copy-id -o StrictHostKeyChecking=no $h; expect 'assword:'; send "$PASSWD\\r"; interact"
done;
}

## SSH CONNECT TESTING
COMMAND_SSH_CONNECT_TEST() {
for h in ${HOSTS[*]}; do ssh $h "hostname -s" ; done;
}

## Copy Proxy CA locally (specific to SUSE Lab FR)
COMMAND_COPY_PROXY_CA() {
if [[ $pkg_mgr_type == 'zypper' ]]
then
	PRIV_KEY_PATH="/etc/pki/trust/anchors/"
elif [[ $pkg_mgr_type == 'yum' ]]
then
	PRIV_KEY_PATH="/etc/pki/ca-trust/source/anchors/"
fi
echo "Get private certificate from proxy."
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
hostname -s
if [[ $pkg_mgr_type == 'zypper' ]]
then 
sudo update-ca-certificates
fi
if [[ $pkg_mgr_type == 'yum' ]]
then 
sudo update-ca-trust
fi
echo 'Proxy parameters added to /etc/profile.d/proxy.sh'
echo"
done
# Add locally
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
echo "$(hostname -s) : Proxy parameters added to /etc/profile.d/proxy.sh"
}

## LIST REPOSITORIES
COMMAND_REPOS_ZYPPER() {
for h in ${HOSTS[*]}
  do ssh $h "echo && hostname -s && echo && sudo zypper lr"; 
done
}
COMMAND_REPOS_YUM() {
for h in ${HOSTS[*]}
  do ssh $h "echo && hostname -s && echo && sudo yum repolist all"; 
done
}
COMMAND_REPOS_APT() {
for h in ${HOSTS[*]}
  do ssh $h "echo && hostname -f && echo && sudo apt-cache policy"; 
done
}

## ADDING REPOSITORIES
COMMAND_ADDREPOS_ZYPPER() {
for h in ${HOSTS[*]}
  do ssh $h "echo ; hostname -s ; echo ; sudo zypper ref ; 
sudo zypper ar -G http://${REPO_SERVER}/ks/dist/child/sle-module-containers15-sp3-pool-x86_64/sles15sp3 containers_product ; 
sudo zypper ar -G http://${REPO_SERVER}/ks/dist/child/sle-module-containers15-sp3-updates-x86_64/sles15sp3 containers_updates" 
done
sudo zypper ar -G http://${REPO_SERVER}/ks/dist/child/sle-module-containers15-sp3-pool-x86_64/sles15sp3 containers_product
sudo zypper ar -G http://${REPO_SERVER}/ks/dist/child/sle-module-containers15-sp3-updates-x86_64/sles15sp3 containers_updates
}

## ALL NODES UPDATE 
COMMAND_NODES_UPDATE_ZYPPER() {
for h in ${HOSTS[*]}
  do ssh $h "echo ; hostname -s ; echo ; sudo zypper ref ; sudo zypper --non-interactive up"
done;
for h in ${HOSTS[*]}
  do ssh $h "echo ; sudo zypper ps" 
done
}

COMMAND_NODES_UPDATE_YUM() {
for h in ${HOSTS[*]}
  do ssh $h "echo ; hostname -s ; echo ; sudo yum -y update"
done;
}

COMMAND_NODES_UPDATE_APT() {
for h in ${HOSTS[*]}
  do ssh $h "echo ; hostname -f ; echo ; sudo apt-get -y upgrade"
done;
}

## CHECK TIME
## TODO - support chronyc and ntpq
COMMAND_CHECK_TIME() {
for h in ${HOSTS[*]}; do
  ssh $h "echo && hostname -s &&
	  if which chronyc ; then sudo chronyc -a tracking |grep 'Leap status'
 	  elif which ntpq ; then sudo ntpq -p
    elif which timedatectl; then sudo timedatectl | grep sync
	  else echo ${TXT_CHECK_TIME:=Chronyc or ntpq binaries are not present. Cannot check if time is synchronized.}
	  fi"
done
}

## CHECK ACCESS - INTERNET/PROXY/REGISTRY
COMMAND_CHECK_ACCESS_REGISTRY() {
if [ "${AIRGAP_REGISTRY_INSECURE}" == "1" ] ; then
  for h in ${HOSTS[*]}; do
    ssh $h "echo && hostname -s && curl -k -s -o /dev/null -I https://${AIRGAP_REGISTRY_URL}  && echo '${AIRGAP_REGISTRY_URL}: OK' || echo '${AIRGAP_REGISTRY_URL}: FAIL'"
  done
  echo
elif [[ ! -z ${AIRGAP_REGISTRY_CACERT} ]] ; then
  for h in ${HOSTS[*]}; do
    ssh $h "echo && hostname -s && curl -s -o /dev/null -I --cacert /etc/docker/certs.d/${AIRGAP_REGISTRY_URL}/ca.crt  https://${AIRGAP_REGISTRY_URL}  && echo '${AIRGAP_REGISTRY_URL}: OK' || echo '${AIRGAP_REGISTRY_URL}: FAIL'"
  done
  echo
else
  for h in ${HOSTS[*]}; do
    ssh $h "echo && hostname -s && curl -s -o /dev/null -I https://${AIRGAP_REGISTRY_URL}  && echo '${AIRGAP_REGISTRY_URL}: OK' || echo '${AIRGAP_REGISTRY_URL}: FAIL'"
  done
  echo
fi
}

COMMAND_CHECK_ACCESS_STORAGE_NET() {
for h in ${HOSTS[*]}; do ssh $h "echo && hostname -s && ping -c1 $STORAGE_TARGET > /dev/null  && echo 'ping $STORAGE_TARGET: OK' || echo 'ping $STORAGE_TARGET: FAIL'"; done;
}

## ACTIVATION IP FORWARDING
COMMAND_IPFORWARD_ACTIVATE() {
for h in ${HOSTS[*]};do ssh $h "echo; hostname -s ; sudo sed -i '/net.ipv4.ip_forward.*/d' /etc/sysctl.conf /etc/sysctl.d/*.conf ; echo 'net.ipv4.ip_forward = 1' |sudo tee -a /etc/sysctl.conf; sudo sed '/^#/d' /etc/sysctl.conf;sudo sysctl -p" ; done
}

## DESACTIVATION DU SWAP
COMMAND_NO_SWAP() {
for h in ${HOSTS[*]};do ssh $h 'sudo sed -i "/swap/ s/defaults/&,noauto/" /etc/fstab';done
for h in ${HOSTS[*]};do ssh $h "echo; hostname -s; grep swap /etc/fstab; sudo swapoff -a; free -g";done
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
elif [[ $pkg_mgr_type == 'yum' ]]
then
	FIREWALL_SVC="firewalld"
elif [[ $pkg_mgr_type == 'apt' ]]
then
	FIREWALL_SVC="firewalld"
fi
for h in ${HOSTS[*]};do
ssh $h "
hostname -s
if sudo rpm -q $FIREWALL_SVC ; then
  echo "${TXT_FIREWALLD_STOP_DISABLE:=Stop and disable firewalld}"
  sudo systemctl stop $FIREWALL_SVC
  sudo systemctl disable $FIREWALL_SVC
fi
"
done
hostname -s
if sudo rpm -q $FIREWALL_SVC ; then
  echo "${TXT_FIREWALLD_STOP_DISABLE:=Stop and disable firewalld}"
  sudo systemctl stop $FIREWALL_SVC
  sudo systemctl disable $FIREWALL_SVC
fi
}

## CHECK DEFAULT GW EXISTS
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

## LONGHORN
COMMAND_INSTALL_LONGHORN_PREREQ() {
if [[ $pkg_mgr_type == 'zypper' ]]
then
  for h in ${HOSTS[*]}; do
    ssh $h "hostname -s ; sudo zypper in -y open-iscsi nfs-utils ; sudo systemctl enable --now iscsid.service"
  done
elif [[ $pkg_mgr_type == 'yum' ]]
then
  for h in ${HOSTS[*]}; do
    ssh $h "hostname -s ; sudo yum install -y iscsi-initiator-utils nfs-utils"
  done
elif [[ $pkg_mgr_type == 'apt' ]]
then
  for h in ${HOSTS[*]}; do
    ssh $h "hostname -f ; sudo apt-get install -y open-iscsi; sudo systemctl enable --now iscsid.service"
  done
fi
}

##################### BEGIN PRE-CHECK LOCAL PACKAGES ##################################
if [[ $pkg_mgr_type == 'apt' ]]
then
  question_yn "${DESC_CHECK_PACKAGE:=Check if required packages are installed?}" "COMMAND_CHECK_PACKAGE_DPKG_LOCAL curl expect"
else
  question_yn "${DESC_CHECK_PACKAGE_RPM_LOCAL:=Check if required packages are installed?}" "COMMAND_CHECK_PACKAGE_RPM_LOCAL curl expect"
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
  question_yn "${DESC_CHECK_PACKAGE:=Check if required packages are installed?}" "COMMAND_CHECK_PACKAGE_DPKG iptables apparmor"
else
  question_yn "${DESC_CHECK_PACKAGE_RPM:=Check if required packages are installed?}" "COMMAND_CHECK_PACKAGE_RPM iptables apparmor-parser"
fi
##################### END PRE-CHECK PACKAGES ####################################
#
#
##################### BEGIN PROXY ###############################################
if [[ $PROXY_DEPLOY == 1 ]]
then
question_yn "${DESC_COPY_PROXY_CA:=Copy proxy private key to clients. Apply parameters? (specific to SUSE FR Lab)}" COMMAND_COPY_PROXY_CA
question_yn "${DESC_SET_PROXY:=PROXY variables are set in ./00-vars.sh. Apply parameters ? \n _HTTP_PROXY=${_HTTP_PROXY} \n _HTTPS_PROXY=${_HTTPS_PROXY} \n _NO_PROXY=${_NO_PROXY}}" COMMAND_SET_PROXY
fi
##################### END PROXY #################################################
#
##################### BEGIN OS REQUIREMENTS #####################################
question_yn "$pkg_mgr_type - ${DESC_FIREWALL:=Check firewalld status (must be disabled)?}" COMMAND_FIREWALL
question_yn "${DESC_DEFAULT_GW:=Check for a defined default gateway?}" COMMAND_DEFAULT_GW
question_yn "${DESC_CHECK_TIME:=Verify date and time on all nodes?}" COMMAND_CHECK_TIME
question_yn "${DESC_IPFORWARD_ACTIVATE:=Enable IP forwarding?}" COMMAND_IPFORWARD_ACTIVATE
question_yn "${DESC_NO_SWAP:=Disable swap on target nodes?}" COMMAND_NO_SWAP
##################### END OS REQUIREMENTS #######################################
#
#
##################### BEGIN REPOS & BINARIES ####################################
if [[ $pkg_mgr_type == 'zypper' ]]
then 
question_yn "$pkg_mgr_type - ${DESC_REPOS:=List repositories on nodes}" COMMAND_REPOS_ZYPPER
question_yn "$pkg_mgr_type - ${DESC_ADDREPOS:=Add sle-module-containers repositories on target and local nodes?}" COMMAND_ADDREPOS_ZYPPER
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
##################### BEGIN CHECK STORAGE ACCESS #################################
if [[ ! -z ${STORAGE_TARGET} ]] ; then
  question_yn "${DESC_CHECK_ACCESS_STORAGE_NET:=Check $STORAGE_TARGET is accessible from all nodes?}" COMMAND_CHECK_ACCESS_STORAGE_NET
fi
##################### END CHECK STORAGE ACCESS ###################################
#
#
##################### BEGIN LONGHORN REQUIREMENTS ################################
question_yn "${DESC_INSTALL_LONGHORN_PREREQ:=Install Longhorn pre-requisites (open-iscsi) on all nodes?}" COMMAND_INSTALL_LONGHORN_PREREQ
##################### END LONGHORN REQUIREMENTS ##################################

echo
echo "-- ${TXT_END:=END} --"
echo "${TXT_NEXT_STEP:=Next step} 02-rke2_deploy.sh"
