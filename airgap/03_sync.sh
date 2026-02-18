HOST_NAME=`hostname -f`


zypper -n in skopeo helm-mirror

## CaaSP 4 images
#curl -O https://documentation.suse.com/external-tree/en-us/suse-caasp/4/skuba-cluster-images.txt
#for name in $(awk '{print$4}' skuba-cluster-images.txt) ; do
#  echo ${name/image\:}
#  skopeo copy docker://${name/image\:} docker://$HOST_NAME:5000/${name/image\:} --dest-tls-verify=false
#done

## RKE
# rke config --system-images
#INFO[0000] Generating images list for version [v1.19.3-rancher1-1]:
SYSTEM_IMAGES="rancher/coreos-etcd:v3.4.13-rancher1 rancher/rke-tools:v0.1.65 rancher/k8s-dns-kube-dns:1.15.10 rancher/k8s-dns-dnsmasq-nanny:1.15.10 rancher/k8s-dns-sidecar:1.15.10 rancher/cluster-proportional-autoscaler:1.8.1 rancher/coredns-coredns:1.7.0 rancher/k8s-dns-node-cache:1.15.13 rancher/hyperkube:v1.19.3-rancher1 rancher/coreos-flannel:v0.13.0-rancher1 rancher/flannel-cni:v0.3.0-rancher6 rancher/calico-node:v3.16.1 rancher/calico-cni:v3.16.1 rancher/calico-kube-controllers:v3.16.1 rancher/calico-ctl:v3.16.1 rancher/calico-pod2daemon-flexvol:v3.16.1 weaveworks/weave-kube:2.7.0 weaveworks/weave-npc:2.7.0 rancher/pause:3.2 rancher/nginx-ingress-controller:nginx-0.35.0-rancher1 rancher/nginx-ingress-controller-defaultbackend:1.5-rancher1 rancher/metrics-server:v0.3.6"
for name in $SYSTEM_IMAGES ; do
	echo $name
	skopeo copy docker://${name} docker://$HOST_NAME:5000/${name} --dest-tls-verify=false
done


## Helm Tiller
name="registry.suse.com/caasp/v4/helm-tiller:2.16.1"
skopeo copy docker://${name} docker://$HOST_NAME:5000/${name} --dest-tls-verify=false

## httpd pour demo
name="docker.io/httpd:latest"
skopeo copy docker://${name} docker://$HOST_NAME:5000/${name} --dest-tls-verify=false

## image pour grafana 
#for name in docker.io/busybox:1.30 docker.io/kiwigrid/k8s-sidecar:0.1.20 ; do
#	echo $name
#	skopeo copy docker://${name} docker://$HOST_NAME:5000/${name} --dest-tls-verify=false
#done

## SUSE Helm Charts
#for name in console grafana log-agent-rsyslog metrics minibroker nginx-ingress prometheus; do
#  helm-mirror inspect-images /srv/www/htdocs/charts/${name}* -o skopeo=sync.yaml
#  skopeo sync --scoped --src yaml --dest docker sync.yaml $HOST_NAME:5000 
#done
#
### Ceph CSI
for name in quay.io/k8scsi/csi-provisioner:v1.6.0 quay.io/k8scsi/csi-resizer:v0.5.0 quay.io/k8scsi/csi-attacher:v2.1.1 quay.io/k8scsi/csi-node-driver-registrar:v1.3.0 quay.io/cephcsi/cephcsi:canary docker.io/redis:4 ; do 
	echo $name
	skopeo copy docker://${name} docker://$HOST_NAME:5000/${name} --dest-tls-verify=false
done
### K8S Dashboard
#for name in docker.io/kubernetesui/metrics-scraper:v1.0.2 docker.io/kubernetesui/dashboard:v2.0.0-rc2; do
#        echo $name
#        skopeo copy docker://${name} docker://$HOST_NAME:5000/${name} --dest-tls-verify=false
#done
#
### Nextcloud Demo
for name in docker.io/nextcloud:18.0.0-apache docker.io/bitnami/mariadb:10.3.20-debian-9-r0 docker.io/dduportal/bats:0.4.0 ; do
	echo $name
        skopeo copy docker://${name} docker://$HOST_NAME:5000/${name} --dest-tls-verify=false
done
