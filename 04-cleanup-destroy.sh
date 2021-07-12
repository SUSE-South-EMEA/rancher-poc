#!/bin/bash

### Source variables
source ./00-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh

COMMAND_RKE_REMOVE() {
# Remote rke cluster
rke remove
}

COMMAND_NODES_CLEANUP() {
for h in ${HOSTS[*]}; do 
echo  
echo "${bold}${TXT_CLEANUP_NODE:=Cleanup node $h}${normal}" 
echo
echo "- ${TXT_DOCKER_IMAGES_VOLUMES_CLEAN:=Removing docker images and volumes}"
ssh $h "sudo docker ps -qa | xargs sudo docker rm -f ; \
	sudo docker images -q | xargs sudo docker rmi -f  ; \
	sudo docker volume ls -q | xargs sudo docker volume rm ;"

echo "- ${TXT_DOCKER_MOUNT_CLEAN:=Unmounting docker and kubernetes specific directories}"
ssh $h "sudo mount | grep tmpfs | grep '/var/lib/kubelet' | awk '{ print $3 }' | xargs sudo umount ; \
        sudo umount /var/lib/kubelet; sudo umount /var/lib/rancher"

echo "- ${TXT_DOCKER_CLEAN_DIR:=Removing docker and kubernetes specific directories}"
ssh $h "sudo rm -rf /etc/ceph \
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
       /var/run/calico" 
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
# Prereqs binaries
sudo rm -f helm-v*-linux-amd64.tar.gz kubectl rke_linux-amd64
# Docker RPMs
sudo rm -f *.rpm
# Fetched Helm charts
sudo rm -rf cert-manager rancher
}


##################### BEGIN CLEANUP ##################################
question_yn "${DESC_RKE_REMOVE:=Remove RKE cluster?}" COMMAND_RKE_REMOVE
question_yn "${DESC_NODES_CLEANUP:=Cleanup nodes - remove docker images, volumes, mountpoints and directories?}" COMMAND_NODES_CLEANUP
question_yn "${DESC_LOCAL_DOCKER_CLEANUP:=Cleanup local node - remove docker images, volumes, mountpoints and directories?}" COMMAND_LOCAL_DOCKER_CLEANUP
question_yn "${DESC_LOCAL_AIRGAP_RESOURCES_CLEANUP:=Cleanup local Airgap resources created by 00-prepare-airgap script?}" COMMAND_LOCAL_AIRGAP_RESOURCES_CLEANUP
##################### END CLEANUP ####################################

echo "-- ${TXT_END:=END} --"
