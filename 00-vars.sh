# Files
HOST_LIST_FILE=./hosts.list
HOST_MASTERS=./masters.list
HOST_WORKERS=./workers.list
# CaaSP
SALT_MASTER=192.168.101.20
CEPH_MON1="192.168.1.11"
CEPH_MON2="192.168.1.12"
CEPH_MON3="192.168.1.13"
LB_MASTERS="api.apps.zypp.lo"
IP_LIST="192.168.101.22,192.168.101.23"
dom="apps.zypp.lo"
ext_dom="apps.office.zypp.fr"
# Ceph
CLIENT="groupe1"
ADMIN_KEY_64="AQB4D3Jf16SSJhAAoCpNUgxzUarScxrVbvuZ4A=="
MON_LIST="$CEPH_MON1:6789,$CEPH_MON2:6789,$CEPH_MON3:6789"
STORAGE_CLASS="csi-cephfs-sc"
#LDAP et Dex
DS_DM_PASSWORD=root
DS_SUFFIX="dc=example,dc=org"
DATA_DIR=$PWD/389_ds_data
#NextCloud
NAMESPACE="nextcloud"
HELM_CHART=nextcloud-client1
K8S_LABEL="app=mariadb"
NEXTCLOUD_BRANCH=nextcloud/nextcloud
APP_VALUES=values.yaml
#HELM
HELM_VERSION="3.2.4"
