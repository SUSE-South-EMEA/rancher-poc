# Intégration Harvester dans Rancher

Ce document décrit le processus complet pour déployer une VM Rancher Manager sur Harvester et importer le cluster Harvester dans Rancher.

## Architecture

```
Client → DNS (Pi-hole) → Traefik (rasp01:443) → RKE2 Ingress (VM:443) → Rancher
                          172.16.3.6               172.16.3.20
```

- **DNS** : `rancher.home.zypp.fr` → 172.16.3.6 (Traefik sur rasp01)
- **Traefik** : Reverse proxy HTTPS avec certificat Let's Encrypt wildcard `*.home.zypp.fr`
- **Rancher VM** : RKE2 + Rancher sur 172.16.3.20, certificat auto-signé en backend
- **Harvester** : VIP 172.16.3.100, nœud 172.16.3.11

## Étape 1 : Créer/Recréer la VM Rancher Manager

### Vérifier le PVC existant

```bash
ssh rancher@172.16.3.11 "sudo /var/lib/rancher/rke2/bin/kubectl \
  --kubeconfig /etc/rancher/rke2/rke2.yaml get pvc -n default | grep rancher"
```

### Manifeste VirtualMachine

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: rancher-manager
  namespace: default
  labels:
    harvesterhci.io/creator: harvester
spec:
  runStrategy: RerunOnFailure
  template:
    metadata:
      labels:
        harvesterhci.io/vmName: rancher-manager
    spec:
      domain:
        cpu:
          cores: 4
        resources:
          requests:
            memory: 8Gi
        devices:
          disks:
            - name: disk-1
              disk:
                bus: virtio
              bootOrder: 1
          interfaces:
            - name: default
              bridge: {}
      networks:
        - name: default
          multus:
            networkName: default/production
      volumes:
        - name: disk-1
          persistentVolumeClaim:
            claimName: rancher-manager-0-disk-1-l68xw
```

Appliquer :

```bash
ssh rancher@172.16.3.11 "sudo /var/lib/rancher/rke2/bin/kubectl \
  --kubeconfig /etc/rancher/rke2/rke2.yaml apply -f -" <<'EOF'
# (coller le manifeste ci-dessus)
EOF
```

### Vérification

```bash
ssh rancher@172.16.3.11 "sudo /var/lib/rancher/rke2/bin/kubectl \
  --kubeconfig /etc/rancher/rke2/rke2.yaml get vm,vmi -n default"
```

## Étape 2 : Vérifier RKE2 et Rancher dans la VM

```bash
# SSH dans la VM (credentials: rancher / susesuse)
ssh rancher@172.16.3.20

# Vérifier RKE2
sudo systemctl status rke2-server
sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes

# Vérifier Rancher
sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -n cattle-system
sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get ingress -n cattle-system
```

## Étape 3 : Configurer le DNS

Ajouter `rancher.home.zypp.fr` dans Pi-hole (v6) sur rasp01 :

```bash
# Récupérer la liste existante et ajouter la nouvelle entrée
docker exec b41a7dff114c_pihole pihole-FTL --config dns.hosts \
  '[..., "172.16.3.6 rancher.home.zypp.fr"]'
```

> **Note** : Pi-hole v6 utilise `pihole-FTL --config dns.hosts` en format JSON array. Le fichier `custom.list` est auto-généré et ne doit pas être modifié directement.

Vérification : `dig rancher.home.zypp.fr @172.16.3.6`

## Étape 4 : Configurer Traefik

### Fichier `dynamic/rancher.yaml`

```yaml
http:
  routers:
    rancher-zypp:
      rule: "Host(`rancher.home.zypp.fr`)"
      entryPoints:
        - websecure
      service: rancher-service
      tls: {}

    rancher-lo:
      rule: "Host(`rancher.home.lo`)"
      entryPoints:
        - websecure
      service: rancher-service
      tls: {}

  services:
    rancher-service:
      loadBalancer:
        servers:
          - url: "https://172.16.3.20:443"
        passHostHeader: true
        serversTransport: rancher-transport

  serversTransports:
    rancher-transport:
      insecureSkipVerify: true
```

**Points clés** :
- Backend en **HTTPS** vers 172.16.3.20:443 (RKE2 ingress controller)
- `insecureSkipVerify: true` car le certificat RKE2 est auto-signé
- `tls: {}` utilise le certificat wildcard Let's Encrypt par défaut
- Supprimer toute entrée rancher de `dynamic.yml` pour éviter les conflits

## Étape 5 : Configurer le hostname Rancher

```bash
# Mettre à jour le Helm release
sudo /usr/local/bin/helm --kubeconfig /etc/rancher/rke2/rke2.yaml \
  upgrade rancher rancher-prime/rancher \
  --namespace cattle-system \
  --set hostname=rancher.home.zypp.fr \
  --set tls=external \
  --set global.cattle.psp.enabled=false

# Mettre à jour CATTLE_SERVER_URL (readonly via API, doit être patché via env)
sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml \
  -n cattle-system set env deploy/rancher CATTLE_SERVER_URL=https://rancher.home.zypp.fr
```

### Reset du mot de passe admin

```bash
sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml \
  -n cattle-system exec deploy/rancher -- reset-password
```

## Étape 6 : Importer Harvester dans Rancher

### Problème de certificat CA

Le `cattle-cluster-agent` sur Harvester a `STRICT_VERIFY=true` et cherche un fichier CA à `/etc/kubernetes/ssl/certs/serverca`. Ce fichier n'existe pas par défaut sur Harvester.

**Solution** : Créer un ConfigMap contenant un bundle CA combiné :

1. **ISRG Root X1** (racine Let's Encrypt)
2. **Let's Encrypt E7** (intermédiaire)
3. **Server CA RKE2** (CA interne Harvester)

```bash
# Sur la machine admin, créer le bundle CA
echo | openssl s_client -connect rancher.home.zypp.fr:443 -servername rancher.home.zypp.fr -showcerts 2>/dev/null \
  | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/{print}' > /tmp/le_chain.pem
cat /etc/ssl/certs/ISRG_Root_X1.pem /tmp/le_chain.pem > /tmp/ca_bundle.pem

# Ajouter la CA RKE2 de Harvester
ssh rancher@172.16.3.11 "sudo cat /var/lib/rancher/rke2/server/tls/server-ca.crt" >> /tmp/ca_bundle.pem

# Transférer sur Harvester
ssh rancher@172.16.3.11 "cat > /tmp/ca_bundle.pem" < /tmp/ca_bundle.pem

# Créer le ConfigMap
ssh rancher@172.16.3.11 "sudo /var/lib/rancher/rke2/bin/kubectl \
  --kubeconfig /etc/rancher/rke2/rke2.yaml -n cattle-system \
  create configmap serverca --from-file=serverca=/tmp/ca_bundle.pem"
```

### Appliquer le manifeste d'import

Récupérer l'URL du manifeste depuis l'API Rancher ou l'UI (Virtualization Management → Import Existing) :

```bash
ssh rancher@172.16.3.11 "curl -sfL '<MANIFEST_URL>' | sudo /var/lib/rancher/rke2/bin/kubectl \
  --kubeconfig /etc/rancher/rke2/rke2.yaml apply -f -"
```

### Monter le ConfigMap dans l'agent

```bash
ssh rancher@172.16.3.11 'sudo /var/lib/rancher/rke2/bin/kubectl \
  --kubeconfig /etc/rancher/rke2/rke2.yaml -n cattle-system \
  patch deploy cattle-cluster-agent --type=json -p '"'"'[
  {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"serverca","configMap":{"name":"serverca"}}},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"serverca","mountPath":"/etc/kubernetes/ssl/certs","readOnly":true}}
]'"'"''
```

### Vérification

```bash
# Agent connecté
ssh rancher@172.16.3.11 "sudo /var/lib/rancher/rke2/bin/kubectl \
  --kubeconfig /etc/rancher/rke2/rke2.yaml -n cattle-system \
  logs -l app=cattle-cluster-agent --tail=5"
# Doit afficher: "Connected to proxy"

# Cluster actif dans Rancher
curl -s -k -H "Authorization: Bearer <TOKEN>" \
  "https://rancher.home.zypp.fr/v3/clusters" | python3 -c "
import sys,json
for c in json.load(sys.stdin)['data']:
    print(f\"{c['name']}: {c['state']} (provider: {c.get('labels',{}).get('provider.cattle.io','')})\")"
```

## État actuel

| Composant | Statut | Détails |
|-----------|--------|---------|
| VM rancher-manager | Running | 4 vCPU, 8Gi RAM, 200Gi disk, IP 172.16.3.20 |
| RKE2 | Active | v1.33.7+rke2r1, 1 nœud |
| Rancher | Active | v2.13.1, hostname=rancher.home.zypp.fr |
| DNS | OK | rancher.home.zypp.fr → 172.16.3.6 (Traefik) |
| Traefik | OK | HTTPS reverse proxy → 172.16.3.20:443 |
| Harvester import | Active | Cluster c-sg2q6, 1 nœud, 8 CPU, 64Gi RAM |
