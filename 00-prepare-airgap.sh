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
else
  echo "${TXT_AIRGAP_INTRO:=Airgap configuration defined in} 00-vars.sh:"
  echo
  echo "  AIRGAP_REGISTRY_URL: ${AIRGAP_REGISTRY_URL}"
  echo "  AIRGAP_REGISTRY_CACERT: ${AIRGAP_REGISTRY_CACERT}"
  echo "  AIRGAP_REGISTRY_INSECURE: ${AIRGAP_REGISTRY_INSECURE}"
  echo "  AIRGAP_REGISTRY_USER: ${AIRGAP_REGISTRY_USER}"   
  echo "  AIRGAP_REGISTRY_PASSWD: <THIS_IS_A_SECRET>"
  echo
fi

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

## PRE-CHECK PACKAGE

COMMAND_INSTALL_YUM_UTILS() {
# Install yum-utils package (needed for 'yumdownloader')
sudo yum install -y yum-utils
}

COMMAND_DOCKER_INSTALL_ZYPPER_LOCAL() {
sudo zypper ref ; sudo zypper --non-interactive in docker
sudo systemctl enable docker ; sudo systemctl start docker && echo 'Docker is activated' || echo 'Docker could not start'
}

COMMAND_DOCKER_INSTALL_YUM_LOCAL() {
curl -O https://releases.rancher.com/install-docker/${DOCKER_VERSION}.sh && sudo /bin/sh ${DOCKER_VERSION}.sh
sudo systemctl enable docker ; sudo systemctl start docker && echo 'Docker is activated' || echo 'Docker could not start'
}

COMMAND_CONFIGURE_LOCAL_DOCKER_DAEMON() {
if [ "${AIRGAP_REGISTRY_INSECURE}" == "1" ] ; then
  # Configure docker to use insecure private registry
  sudo tee /etc/docker/daemon.json <<EOF
{"insecure-registries" : ["${AIRGAP_REGISTRY_URL}"]}
EOF
else
  # Configure docker to use private registry
  sudo tee /etc/docker/daemon.json <<EOF
{"registry-mirrors": ["https://${AIRGAP_REGISTRY_URL}"]}
EOF
  echo
  if [[ ! -z ${AIRGAP_REGISTRY_CACERT} ]] ; then
    echo "${TXT_REGISTRY_COPY_CACERT:=Copy registry CA certificate}"
    mkdir -p /etc/docker/certs.d/${AIRGAP_REGISTRY_URL}/
    cp ${AIRGAP_REGISTRY_CACERT} /etc/docker/certs.d/${AIRGAP_REGISTRY_URL}/ca.crt
  fi
fi
# Restart docker
systemctl restart docker
}

COMMAND_DL_PREREQ_BINARIES() {
echo
echo "${TXT_DL_INSTALL_HELM:=Download and install Helm} - version: ${HELM_VERSION}"
curl -O https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz
tar zxvf helm-v${HELM_VERSION}-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm
rm -rf linux-amd64/

echo
echo "${TXT_DL_KUBECTL:=Download latest stable kubectl binary}"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

echo
echo "${TXT_DL_RKE2:=Download rke2 tarball} - version: ${RKE2_VERSION}"
curl -LO https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/rke2.linux-amd64.tar.gz
}

COMMAND_DL_PREREQ_RANCHER() {
# Download Rancher images list and import/export scripts
for file in rancher-images.txt rancher-save-images.sh rancher-load-images.sh ; do
  if [ -f $file ]; then rm $file ; fi
  wget https://github.com/rancher/rancher/releases/download/v${RANCHER_VERSION}/$file
done
sudo chmod +x rancher-save-images.sh rancher-load-images.sh
}

# COMMAND_DL_RKE2_IMAGES_YUM() {
# RKE2_VERSION="v$(rpm --nosignature -q --qf "%{VERSION}\n" rke2-common-*.rpm |tr '~' '+')"
# for file in rke2-images-canal.linux-amd64 rke2-images-core.linux-amd64 ; do
#   if [ -f $file.txt ]; then rm -f $file.txt ; fi
#   if [ -f $file.tar.gz ]; then rm -f $file.tar.gz ; fi
#   wget https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/$file.txt
#   wget https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/$file.tar.gz
#   sed -i 's/docker.io\///g' $file.txt
# done
# }

COMMAND_DL_RKE2_IMAGES() {
for file in rke2-images-canal.linux-amd64 rke2-images-core.linux-amd64 ; do
  if [ -f $file.txt ]; then rm -f $file.txt ; fi
  if [ -f $file.tar.gz ]; then rm -f $file.tar.gz ; fi
  wget https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/$file.txt
  wget https://github.com/rancher/rke2/releases/download/${RKE2_VERSION}/$file.tar.gz
  sed -i 's/docker.io\///g' $file.txt
done
}

COMMAND_PUSH_RKE2_IMAGES() {
if [ ! -f rancher-load-images.sh ] ; then
  wget https://github.com/rancher/rancher/releases/download/v${RANCHER_VERSION}/rancher-load-images.sh
  sudo chmod +x rancher-load-images.sh
fi
if [[ ! -z ${AIRGAP_REGISTRY_USER} ]] ; then
  echo "${AIRGAP_REGISTRY_PASSWD}" | docker login -u ${AIRGAP_REGISTRY_USER} --password-stdin ${AIRGAP_REGISTRY_URL}
fi
for file in rke2-images-canal.linux-amd64 rke2-images-core.linux-amd64 ; do
  sudo ./rancher-load-images.sh -i $file.tar.gz -l $file.txt --registry ${AIRGAP_REGISTRY_URL}
done
}

COMMAND_FETCH_CERTMGR_IMAGES() {
# Fetch cert-manager images
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm fetch jetstack/cert-manager --version ${CERTMGR_VERSION}
helm template ./cert-manager-${CERTMGR_VERSION}.tgz | grep -oP '(?<=image: ").*(?=")' >> ./rancher-images.txt
}

COMMAND_SAVE_RANCHER_IMAGES() {
# Remove overlap between sources
sort -u rancher-images.txt -o rancher-images.txt
# Save images
chmod +x rancher-save-images.sh
sudo ./rancher-save-images.sh --image-list ./rancher-images.txt
echo "${TXT_SAVE_RANCHER_IMAGES:=Images saved in rancher-images.tar.gz.}"
}

COMMAND_PUSH_RANCHER_IMAGES() {
# Push Rancher images
sudo chmod +x rancher-load-images.sh
if [[ ! -z ${AIRGAP_REGISTRY_USER} ]] ; then
  echo "${AIRGAP_REGISTRY_PASSWD}" | docker login -u ${AIRGAP_REGISTRY_USER} --password-stdin ${AIRGAP_REGISTRY_URL}
fi
sudo ./rancher-load-images.sh --image-list ./rancher-images.txt --registry ${AIRGAP_REGISTRY_URL}
}

COMMAND_HELM_MIRROR() {
# Fetch cert manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm fetch jetstack/cert-manager --version ${CERTMGR_VERSION}
# Render cert manager
if [[ $PROXY_DEPLOY == 1 ]] ; then
  RANCHER_NO_PROXY=$(echo ${_NO_PROXY} |sed 's/,/\\,/g')
  echo
  echo "${bold}Cert Manager deployment with Proxy settings:"
  echo "- http_proxy=${_HTTP_PROXY}"
  echo "- https_proxy=${_HTTPS_PROXY}"
  echo "- no_proxy=${RANCHER_NO_PROXY}${normal}"
  echo
  helm template cert-manager ./cert-manager-${CERTMGR_VERSION}.tgz --output-dir . \
    --namespace cert-manager \
    --set image.repository=${AIRGAP_REGISTRY_URL}/quay.io/jetstack/cert-manager-controller \
    --set webhook.image.repository=${AIRGAP_REGISTRY_URL}/quay.io/jetstack/cert-manager-webhook \
    --set cainjector.image.repository=${AIRGAP_REGISTRY_URL}/quay.io/jetstack/cert-manager-cainjector \
    --set startupapicheck.image.repository=${AIRGAP_REGISTRY_URL}/quay.io/jetstack/cert-manager-ctl \
    --set http_proxy=http://${_HTTP_PROXY} \
    --set https_proxy=http://${_HTTPS_PROXY} \
    --set no_proxy=${RANCHER_NO_PROXY}
else
  helm template cert-manager ./cert-manager-${CERTMGR_VERSION}.tgz --output-dir . \
    --namespace cert-manager \
    --set image.repository=${AIRGAP_REGISTRY_URL}/quay.io/jetstack/cert-manager-controller \
    --set webhook.image.repository=${AIRGAP_REGISTRY_URL}/quay.io/jetstack/cert-manager-webhook \
    --set cainjector.image.repository=${AIRGAP_REGISTRY_URL}/quay.io/jetstack/cert-manager-cainjector \
    --set startupapicheck.image.repository=${AIRGAP_REGISTRY_URL}/quay.io/jetstack/cert-manager-ctl
fi
curl -L -o cert-manager/cert-manager-crd.yaml https://github.com/jetstack/cert-manager/releases/download/${CERTMGR_VERSION}/cert-manager.crds.yaml

# Certificates configuration
## Private CA
if [[ $PRIVATE_CA == 1 ]] ; then
  if [[ $TLS_SOURCE == "rancher" ]] ; then echo "Cannot use PRIVATE_CA=1 with TLS_SOURCE=rancher. Exiting..." && exit 1 ; fi
  EXTRA_OPTS="--set privateCA=true"
fi
## User provided certificate
if [[ $TLS_SOURCE == "secret" ]] ; then
  EXTRA_OPTS="${EXTRA_OPTS} --set ingress.tls.source=secret"
elif [[ $TLS_SOURCE == "external" ]] ; then
  EXTRA_OPTS="${EXTRA_OPTS} --set tls=external"
else
  echo "Self-signed certificate will be generated using Cert-manager"
fi

# Fetch rancher
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm fetch rancher-latest/rancher --version=v${RANCHER_VERSION}
# Render rancher
if [[ $PROXY_DEPLOY == 1 ]] ; then
  RANCHER_NO_PROXY=$(echo ${_NO_PROXY} |sed 's/,/\\,/g')
  echo
  echo "${bold}Rancher Management Server deployment with Proxy settings:"
  echo "- proxy=${_HTTP_PROXY}"
  echo "- noProxy=${RANCHER_NO_PROXY}${normal}"
  echo
  helm template rancher ./rancher-${RANCHER_VERSION}.tgz --output-dir . \
    --no-hooks \
    --namespace cattle-system \
    --set hostname=${LB_RANCHER_FQDN} \
    --set rancherImage=${AIRGAP_REGISTRY_URL}/rancher/rancher \
    --set rancherImageTag=v${RANCHER_VERSION} \
    --set systemDefaultRegistry=${AIRGAP_REGISTRY_URL} \
    --set useBundledSystemChart=true \
    --set proxy=http://${_HTTP_PROXY} \
    --set noProxy=${RANCHER_NO_PROXY} ${EXTRA_OPTS}
else
  helm template rancher ./rancher-${RANCHER_VERSION}.tgz --output-dir . \
    --no-hooks \
    --namespace cattle-system \
    --set hostname=${LB_RANCHER_FQDN} \
    --set rancherImage=${AIRGAP_REGISTRY_URL}/rancher/rancher \
    --set rancherImageTag=v${RANCHER_VERSION} \
    --set systemDefaultRegistry=${AIRGAP_REGISTRY_URL} \
    --set useBundledSystemChart=true ${EXTRA_OPTS}
fi
# Cleanup
rm -f cert-manager-${CERTMGR_VERSION}.tgz rancher-${RANCHER_VERSION}.tgz
}

##################### BEGIN PRE-CHECK PACKAGES ##################################
question_yn "${DESC_CHECK_PACKAGE_RPM_LOCAL:=Check if required packages are installed?}" "COMMAND_CHECK_PACKAGE_RPM_LOCAL curl wget"
##################### END PRE-CHECK PACKAGES ####################################
#
#
##################### BEGIN DOCKER PREPARATION###################################
if [[ $pkg_mgr_type == 'zypper' ]]
then
question_yn "$pkg_mgr_type - ${DESC_DOCKER_INSTALL_ZYPPER_LOCAL:=Install, enable and start Docker on local host?}" COMMAND_DOCKER_INSTALL_ZYPPER_LOCAL
elif [[ $pkg_mgr_type == 'yum' ]]
then
question_yn "$pkg_mgr_type - ${DESC_INSTALL_YUM_UTILS:=Install yum-utils package (containing yumdownloader needed for next steps) ?}" COMMAND_INSTALL_YUM_UTILS
question_yn "$pkg_mgr_type - ${DESC_DOCKER_INSTALL_LOCAL_YUM:=Install, enable and start Docker on local host?}" COMMAND_DOCKER_INSTALL_YUM_LOCAL
# question_yn "$pkg_mgr_type - ${DESC_DL_RKE2_YUM:=Add RKE2 repo and download RKE2 RPMs?}" COMMAND_DL_RKE2_YUM
fi
question_yn "${DESC_CONFIGURE_DOCKER_DAEMON:=Configure docker daemon to use private registry?}" COMMAND_CONFIGURE_LOCAL_DOCKER_DAEMON
##################### END DOCKER PREPARATION ####################################
#
##################### BEGIN DOWNLOAD/PREPARE RESOURCES ##########################
# /!\ Internet connection required.
question_yn "${DESC_DL_PREREQ_BINARIES:=Download Helm/kubectl/rke2 binaries and install Helm?}" COMMAND_DL_PREREQ_BINARIES
question_yn "${DESC_DL_PREREQ_RANCHER:=Download images list and import/export scripts?}" COMMAND_DL_PREREQ_RANCHER
question_yn "${DESC_DL_RKE2_IMAGES:=Download RKE2 images?}" COMMAND_DL_RKE2_IMAGES
question_yn "${DESC_FETCH_CERTMGR_IMAGES:=Fetch cert-manager images?}" COMMAND_FETCH_CERTMGR_IMAGES
question_yn "${DESC_SAVE_RANCHER_IMAGES:=Save images locally?}" COMMAND_SAVE_RANCHER_IMAGES
question_yn "${DESC_HELM_MIRROR:=Fetch Helm charts and render templates?\n - Registry URL: ${AIRGAP_REGISTRY_URL}}" COMMAND_HELM_MIRROR
##################### END DOWNLOAD/PREPARE RESOURCES ############################
#
##################### BEGIN PUSH IMAGES TO REGISTRY #############################
# Everything should already be downloaded locally, no Internet connection required.
question_yn "${DESC_PUSH_RKE2_IMAGES:=Push RKE2 images to private registry?}" COMMAND_PUSH_RKE2_IMAGES
question_yn "${DESC_PUSH_RANCHER_IMAGES:=Push images to registry?\n - Registry URL: ${AIRGAP_REGISTRY_URL}}" COMMAND_PUSH_RANCHER_IMAGES
##################### END PUSH IMAGES TO REGISTRY ###############################

echo
echo -e "${TXT_PREP_AIRGAP_COMPLETE:=${bold}Airgap preparation is complete.\nCopy the current directory to a system that has access to the Rancher server cluster to complete installation.}${normal}"
echo
echo "-- ${TXT_END:=END} --"
