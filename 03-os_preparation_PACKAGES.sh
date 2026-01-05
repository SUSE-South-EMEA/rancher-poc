#!/bin/bash

### Source variables
source ./01-vars.sh
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

## SSH CONNECT TESTING
## Tests SSH connection to all hosts without password
COMMAND_SSH_CONNECT_TEST() {
    local success_count=0
    local fail_count=0
    local failed_hosts=()
    
    echo "${bold}Testing SSH connections...${normal}"
    echo
    
    for h in "${HOSTS[@]}"; do
        echo -n "Testing $h... "
        
        if ssh_host "$h" "hostname -f" >/dev/null 2>&1; then
            local hostname
            hostname=$(ssh_host "$h" "hostname -f" 2>/dev/null)
            echo "✓ Connected (hostname: $hostname)"
            ((success_count++))
        else
            echo "✗ Failed"
            ((fail_count++))
            failed_hosts+=("$h")
        fi
    done
    
    echo
    echo "${bold}=== Connection Test Summary ===${normal}"
    echo "  Successful: $success_count"
    echo "  Failed: $fail_count"
    
    if [[ $fail_count -gt 0 ]]; then
        echo
        echo "${bold}Failed hosts:${normal}"
        printf '  - %s\n' "${failed_hosts[@]}"
        return 1
    fi
    
    echo
    echo "Note: Domain in use must not be using *.local"
    return 0
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

## OUTILS K8S
COMMAND_INSTALL_KUBECTL() {
if [[ $AIRGAP_DEPLOY != 1 ]] ; then
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
fi
sudo install -v -o root -g root -m 0755 kubectl /usr/bin/kubectl
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


##################### BEGIN SSH KEYS EXCHANGE ###################################
question_yn "${DESC_SSH_CONNECT_TEST:=Test SSH connection to nodes?}" COMMAND_SSH_CONNECT_TEST
##################################################################################


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
##################################################################################


##################### BEGIN PRE-CHECK REMOTE PACKAGES ############################
if [[ $pkg_mgr_type == 'apt' ]]
then
	question_yn "${DESC_CHECK_PACKAGE:=Remote system(s): check if required packages are installed?}" "COMMAND_CHECK_PACKAGE_DPKG iptables apparmor sudo"
else
	question_yn "${DESC_CHECK_PACKAGE_RPM:=Remote system(s): check if required packages are installed?}" "COMMAND_CHECK_PACKAGE_RPM iptables apparmor-parser sudo lsof"
fi
##################################################################################


##################### K8S TOOLS & LONGHORN PREREQ ################################
question_yn "${DESC_INSTALL_KUBECTL:=Install kubectl on local node?}" COMMAND_INSTALL_KUBECTL
question_yn "${DESC_INSTALL_LONGHORN_PREREQ:=Install Longhorn pre-requisites (open-iscsi) on all nodes?}" COMMAND_INSTALL_LONGHORN_PREREQ
##################################################################################

propose_next_script "04-os_preparation_NETWORKING.sh" "Network configuration and OS checks"
