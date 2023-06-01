#!/bin/bash

### Source variables
source ./00-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh

COMMAND_RKE2_UNINSTALL() {
for h in ${HOSTS[*]}; do
echo  
echo "${bold}${TXT_NODE_UNINSTALL:=Uninstall rke2 on node} $h${normal}" 
echo
ssh $h "sudo /usr/local/bin/rke2-killall.sh ;
sudo /usr/local/bin/rke2-uninstall.sh ;
sudo systemctl stop rancher-system-agent.service ; 
sudo systemctl disable rancher-system-agent.service ;
sudo rm -f /etc/systemd/system/rancher-system-agent.service ;
sudo rm -f /etc/systemd/system/rancher-system-agent.env ;
sudo systemctl daemon-reload ;
sudo rm -f /usr/local/bin/rancher-system-agent ;
sudo rm -rf /etc/rancher/ ;
sudo rm -rf /var/lib/rancher/ ;
sudo rm -rf /usr/local/bin/rke2*"
done
}

COMMAND_RKE2_NODES_REBOOT() {
for h in ${HOSTS[*]}; do
echo  
echo "${bold}${TXT_REBOOT_NODE:=Reboot node} $h${normal}" 
echo
ssh $h "sudo reboot"
done
}

COMMAND_LOCAL_DOCKER_CLEANUP() {
echo "${bold}${TXT_CLEANUP_LOCAL_NODE:=Cleanup local node} $HOSTNAME ${normal}"
echo
echo "- ${TXT_LOCAL_DOCKER_IMAGES_VOLUMES_CLEAN:=Removing local docker images and volumes}"
sudo docker ps -qa | xargs sudo docker rm -f
sudo docker images -q | xargs sudo docker rmi -f
sudo docker volume ls -q | xargs sudo docker volume rm
echo
echo "- ${TXT_LOCAL_DOCKER_MOUNT_CLEAN:=Unmounting local docker and kubernetes specific directories}"
sudo mount | grep tmpfs | grep '/var/lib/kubelet' | awk '{ print $3 }' | xargs sudo umount
sudo umount /var/lib/kubelet; sudo umount /var/lib/rancher
echo
echo "- ${TXT_LOCAL_DOCKER_CLEAN_DIR:=Removing local docker and kubernetes specific directories}"
sudo rm -rf /etc/ceph \
       /etc/cni \
       /etc/kubernetes \
       /opt/cni \
       /opt/rke \
       /run/secrets/kubernetes.io \
       /run/calico \
       /run/flannel \
       /var/lib/calico \
       /var/lib/etcd \
       /var/lib/cni \
       /var/lib/kubelet \
       /var/lib/rancher/rke/log \
       /var/log/containers \
       /var/log/kube-audit \
       /var/log/pods \
       /var/run/calico
}

COMMAND_LOCAL_AIRGAP_RESOURCES_CLEANUP() {
# Rancher images and scripts
sudo rm -f rancher-images.tar.gz rancher-images.txt rancher-load-images.sh rancher-save-images.sh
# RKE2 images, scripts and configuration files
sudo rm -f rke2-*.tar.gz rke2-*.txt registries.yaml rke2-server kube-vip-rbac.yaml kube-vip.yaml
# Prereqs binaries
sudo rm -f helm-v*-linux-amd64.tar.gz kubectl rke2.linux-amd64.tar.gz
# Docker RPMs
sudo rm -f *.rpm
# Fetched Helm charts
sudo rm -rf cert-manager rancher cert-manager-*.tgz
}


##################### BEGIN CLEANUP ##################################
question_yn "${DESC_RKE2_UNINSTALL:=Uninstall RKE2 from all nodes?}" COMMAND_RKE2_UNINSTALL
question_yn "${DESC_RKE2_NODES_REBOOT:=Reboot RKE2 nodes?}" COMMAND_RKE2_NODES_REBOOT
question_yn "${DESC_LOCAL_DOCKER_CLEANUP:=Cleanup local node - remove docker images, volumes, mountpoints and directories?}" COMMAND_LOCAL_DOCKER_CLEANUP
question_yn "${DESC_LOCAL_AIRGAP_RESOURCES_CLEANUP:=Cleanup local Airgap resources created by 00-prepare-airgap script?}" COMMAND_LOCAL_AIRGAP_RESOURCES_CLEANUP
##################### END CLEANUP ####################################

echo "-- ${TXT_END:=END} --"
