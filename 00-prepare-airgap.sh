#!/bin/bash

### Source variables
source ./00-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh

if [[ $AIRGAP_DEPLOY != 1 ]]; then
 echo
 echo -e "${bold}${TXT_AIRGAP_NOT_ENABLED:=Airgap mode not enabled.\nPlease set AIRGAP_DEPLOY=1 in 00-vars.sh and check that everything is properly configured in the AIRGAP SETUP section.}${normal}"
 echo
 exit 1
fi

COMMAND_DL_PREREQ_SCRIPTS() {
# Download images list and import/export scripts
for file in rancher-images.txt rancher-save-images.sh rancher-load-images.sh ; do
  wget https://github.com/rancher/rancher/releases/download/v${RANCHER_VERSION}/$file
done
}

COMMAND_DL_PREREQ_BINARIES() {
# Download RKE binary
curl -LO https://github.com/rancher/rke/releases/download/${RKE_VERSION}/rke_linux-amd64
# Download and install Helm
curl -O https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz
tar zxvf helm-v${HELM_VERSION}-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm
rm -rf linux-amd64/
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
# Cleanup
rm -f cert-manager-${CERTMGR_VERSION}.tgz rancher-${RANCHER_VERSION}.tgz
}

##################### BEGIN COMMANDS ###################################
question_yn "${DESC_DL_PREREQ_SCRIPTS:=Download images list and import/export scripts?}" COMMAND_DL_PREREQ_SCRIPTS
question_yn "${DESC_DL_PREREQ_BINARIES:=Download RKE/Helm binaries and install Helm?}" COMMAND_DL_PREREQ_BINARIES
question_yn "${DESC_FETCH_CERTMGR_IMAGES:=Fetch cert-manager images?}" COMMAND_FETCH_CERTMGR_IMAGES
question_yn "${DESC_SAVE_IMAGES:=Save images locally?}" COMMAND_SAVE_IMAGES
question_yn "${DESC_PUSH_IMAGES:=Push images to registry?\n - Registry URL: ${AIRGAP_REGISTRY_URL}}" COMMAND_PUSH_IMAGES
question_yn "${DESC_HELM_MIRROR:=Fetch Helm charts and render templates?\n - Registry URL: ${AIRGAP_REGISTRY_URL}}" COMMAND_HELM_MIRROR
##################### END COMMANDS ####################################

echo
echo -e "${TXT_PREP_AIRGAP_COMPLETE:=${bold}Airgap preparation is complete.\nCopy the current directory to a system that has access to the Rancher server cluster to complete installation.}${normal}"
echo
echo "-- ${TXT_END:=END} --"