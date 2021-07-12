# Airgap

## Content = Legacy scripts

`01_install_registry.sh` can be used to deploy a simple docker registry.

Other scripts are remainders of the CaaSP era.

## Deploy docker registry

### Generate certificate

```bash
mkdir -p ~/certs
openssl genrsa 2048 > ~/certs/ca.key
chmod 400 ~/certs/ca.key
openssl req -new -x509 -nodes -sha1 -subj "/CN=$HOSTNAME/C=FR/emailAddress=root@localhost" -days 365 -key ~/certs/ca.key -out ~/certs/ca.crt
```

### Run registry

```bash
docker run -d \
  --restart=always \
  --name registry \
  -v "$(pwd)"/certs:/certs \
  -e REGISTRY_HTTP_ADDR=0.0.0.0:443 \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/ca.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/ca.key \
  -p 443:443 \
  registry:2
```

### Test

```bash
docker pull ubuntu:16.04
docker tag ubuntu:16.04 admin.g2.zypp.lo/my-ubuntu
docker push admin.g2.zypp.lo/my-ubuntu
docker pull admin.g2.zypp.lo/my-ubuntu
```

### Configure clients

```bash
vim /etc/docker/daemon.json
{"registry-mirrors": ["https://${AIRGAP_REGISTRY_URL}"]}

mkdir -p /etc/docker/certs.d/${AIRGAP_REGISTRY_URL}/"
cp ca.crt /etc/docker/certs.d/${AIRGAP_REGISTRY_URL}/ca.crt

systemctl restart docker
```
