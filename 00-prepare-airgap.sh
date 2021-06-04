#!/bin/bash

### Source variables
source ./00-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh


COMMAND_DOWNLOAD_PREREQ() {
# Download images list and import/export scripts
for file in rancher-images.txt rancher-save-images.sh rancher-load-images.sh ; do
  wget https://github.com/rancher/rancher/releases/download/v${RANCHER_VERSION}/$file
done
}

COMMAND_FETCH_CERTMGR_IMAGES() {
# Fetch cert-manager images
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm fetch jetstack/cert-manager --version ${CERTMGR_VERSION}
helm template ./cert-manager-${CERTMGR_VERSION}.tgz | grep -oP '(?<=image: ").*(?=")' >> ./rancher-images.txt
}

COMMAND_SAVE_IMAGES() {
# Remove overlap between sources
sort -u rancher-images.txt -o rancher-images.txt
# Save images
chmod +x rancher-save-images.sh
./rancher-save-images.sh --image-list ./rancher-images.txt
}

COMMAND_PUSH_IMAGES() {
# Push images
chmod +x rancher-load-images.sh
#docker login ${AIRGAP_REGISTRY_URL}
./rancher-load-images.sh --image-list ./rancher-images.txt --registry ${AIRGAP_REGISTRY_URL}
}


##################### BEGIN COMMANDS ###################################
question_yn "${DESC_DOWNLOAD_PREREQ:=Download images list and import/export scripts?}" COMMAND_DOWNLOAD_PREREQ
question_yn "${DESC_FETCH_CERTMGR_IMAGES:=Fetch cert-manager images?}" COMMAND_FETCH_CERTMGR_IMAGES
question_yn "${DESC_SAVE_IMAGES:=Save images locally?}" COMMAND_SAVE_IMAGES
question_yn "${DESC_PUSH_IMAGES:=Push images to registry?\n - Registry URL: ${AIRGAP_REGISTRY_URL}}" COMMAND_PUSH_IMAGES
##################### END COMMANDS ####################################

echo
echo "-- ${TXT_END:=END} --"
