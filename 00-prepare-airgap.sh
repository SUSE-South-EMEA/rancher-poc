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
echo "${TXT_SAVE_IMAGES:=Images saved in rancher-images.tar.gz.}"
}

COMMAND_PUSH_IMAGES() {
# Push images
chmod +x rancher-load-images.sh
#docker login ${AIRGAP_REGISTRY_URL}
./rancher-load-images.sh --image-list ./rancher-images.txt --registry ${AIRGAP_REGISTRY_URL}
}

COMMAND_HELM_MIRROR() {
# Fetch rancher
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm fetch rancher-latest/rancher --version=v${RANCHER_VERSION}
# Fetch cert manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm fetch jetstack/cert-manager --version ${CERTMGR_VERSION}
# Render cert manager
helm template cert-manager ./cert-manager-${CERTMGR_VERSION}.tgz --output-dir . \
    --namespace cert-manager \
    --set image.repository=${AIRGAP_REGISTRY_URL}/quay.io/jetstack/cert-manager-controller \
    --set webhook.image.repository=${AIRGAP_REGISTRY_URL}/quay.io/jetstack/cert-manager-webhook \
    --set cainjector.image.repository=${AIRGAP_REGISTRY_URL}/quay.io/jetstack/cert-manager-cainjector
curl -L -o cert-manager/cert-manager-crd.yaml https://github.com/jetstack/cert-manager/releases/download/${CERTMGR_VERSION}/cert-manager.crds.yaml
# Render rancher
helm template rancher ./rancher-${RANCHER_VERSION}.tgz --output-dir . \
    --no-hooks \
    --namespace cattle-system \
    --set hostname=${LB_RANCHER_FQDN} \
    --set certmanager.version=${CERTMGR_VERSION} \
    --set rancherImage=${AIRGAP_REGISTRY_URL}/rancher/rancher \
    --set systemDefaultRegistry=${AIRGAP_REGISTRY_URL} \
    --set useBundledSystemChart=true
}

##################### BEGIN COMMANDS ###################################
question_yn "${DESC_DOWNLOAD_PREREQ:=Download images list and import/export scripts?}" COMMAND_DOWNLOAD_PREREQ
question_yn "${DESC_FETCH_CERTMGR_IMAGES:=Fetch cert-manager images?}" COMMAND_FETCH_CERTMGR_IMAGES
question_yn "${DESC_SAVE_IMAGES:=Save images locally?}" COMMAND_SAVE_IMAGES
question_yn "${DESC_PUSH_IMAGES:=Push images to registry?\n - Registry URL: ${AIRGAP_REGISTRY_URL}}" COMMAND_PUSH_IMAGES
question_yn "${DESC_HELM_MIRROR:=Fetch Helm charts and render templates?\n - Registry URL: ${AIRGAP_REGISTRY_URL}}" COMMAND_HELM_MIRROR
##################### END COMMANDS ####################################

echo
echo "${TXT_PREP_AIRGAP_COMPLETE:=Copy the rendered manifest directories to a system that has access to the Rancher server cluster to complete installation.}"
echo "-- ${TXT_END:=END} --"
