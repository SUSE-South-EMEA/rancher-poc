# Rancher PoC - High Availability

## Agenda

TODO

## Pré-requis

1. Connexion à la machine d'admin

```bash
ssh -p <port> <user>@<ip>
```

2. Clone du repository

```bash
mkdir workshops && cd workshops
git config --global http.sslVerify false
git clone http://git.zypp.fr/workshops/caasp4.git
cd caasp4
```

3. Basculer sur votre groupe

```bash
export GROUPE=<groupe>
```

Exemple:

```bash
export GROUPE=groupe1
```

## Atelier 1 : Initialisation du cluster CaaSP

### Validation de l'environnement

Exécution des scripts de validation de l'environnement

```bash
./01-ssh_key-network.sh
```

```bash
./02-prep-deploy.sh
```

### Installation de CaaSP

Exécution des scripts de déploiement CaaSPv4.

Le script effectue les actions suivantes :

- Deploiement de CaaSP
- Ajout Master
- Ajout Workers

```bash
./03-caasp-admin.sh
```

### Premiers pas

1. Déploiement d'un pod nginx basique

```bash
./04-services_nginx.sh
```

2. Commandes de base pour l'utilisation / gestion d'un cluster Kubernetes

```
kubectl get pods <pod> (-o wide)
kubectl describe pods <pod>
kubectl logs <pod>
kubectl get events
```

## Atelier 2 : Utilisation du cluster

### Storage Class avec Ceph

```bash
./05-ceph_caasp.sh
```

Commandes utiles

```bash
kubectl get sc
kubectl get pvc
kubectl get pv
kubectl describe pv <pv>
```

> Optionnel : montrer le subvolume créé côté Ceph.

### Helm

- Using Tiller/Helm
- NGINX Ingress Load balancer
- Stratos Dashboard

1. Installation Helm et Stratos

```bash
./06-helm_setup.sh
```

Stratos disponible à l'adresse : https://stratos.gX.zypp.fr/
> Login : admin/admin

2. Configuration de Stratos

Récupérer les infos du cluster CaaSP et enregistrer un nouveau endpoint dans Stratos

```bash
# configuration du cluster
kubectl config view

# Fichier kubeconfig
cat ~/.kube/config
```

Ajouter endpoint Helm Charts

- Name: SUSE
- Endpoint address: https://kubernetes-charts.suse.com/

3. Utilisation

Explorer les menus Kubernetes et Helm de Stratos.

### Monitoring avec Prometheus et Grafana

1. Installation

```bash
cd prometheus-grafana
./install.sh

# Suivre le déploiement
watch -d kubectl get pods,pvc -n monitoring
```

2. Utilisation

Grafana disponible à l'adresse : http://grafana.gX.zypp.fr
> Login : admin/admin

Explorer l'interface Grafana

- `Home > CaaSP Cluster`
- `Home > CaaSP Namespaces`

### Deploiement d'une Application

Stay tuned...
