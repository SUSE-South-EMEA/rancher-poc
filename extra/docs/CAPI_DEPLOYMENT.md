# Guide CAPI : Deploiement de clusters downstream sur Harvester

## Vue d'ensemble

Ce guide detaille le deploiement de clusters Kubernetes downstream sur Harvester HCI
via Cluster API (CAPI) et le provider CAPHV. Les clusters sont automatiquement importes
dans Rancher Manager pour la gestion centralisee.

## Prerequis

### Infrastructure

| Composant | Version | Requis |
|-----------|---------|--------|
| Rancher Manager | v2.13.1+ | Avec Turtles active |
| Harvester HCI | v1.6.x | Avec reseau VM configure |
| CAPHV | v0.2.0-rc6 | Build custom ou upstream |

### Ressources Harvester minimales

| Role | CPU | RAM | Disque |
|------|-----|-----|--------|
| Control Plane | 2 vCPU | 4 Gi | 40 Gi |
| Worker | 1 vCPU | 4 Gi | 40 Gi |

Le control plane necessite au minimum 2 vCPU / 4 Gi pour RKE2 + les composants systeme.
Les workers peuvent fonctionner avec 1 vCPU pour un PoC.

### Reseau

- Reseau VM Harvester : `default/production` (bridge sur le reseau physique)
- Les VMs obtiennent des IPs statiques via cloud-init network config
- Le load balancer CAPI utilise DHCP (IP dans la plage 172.16.10.x)
- DNS interne pour la resolution `.home.lo`

## Stack CAPI

### Composants sur le management cluster

1. **Rancher Turtles** : Integration native CAPI dans Rancher v2.13+. Gere l'auto-import
   des clusters CAPI dans Rancher et la reconciliation des ressources.

2. **CAPI Core** (`cattle-capi-system`) : Orchestre le lifecycle des clusters, machines,
   et machine deployments. Gere les ClusterResourceSets pour les addons.

3. **RKE2 Bootstrap/ControlPlane** (`rke2-bootstrap-system`, `rke2-control-plane-system`) :
   Providers CAPI pour bootstrapper des clusters RKE2 et gerer le control plane.

4. **CAPHV** (`caphv-system`) : Infrastructure provider qui cree les VMs sur Harvester,
   configure le reseau, et gere le load balancer.

### Ressources CAPI

```
Cluster                    # Definition du cluster (labels ccm/csi/cni: external)
  |
  +-- HarvesterCluster     # Config infra Harvester (LB, identity, target namespace)
  |
  +-- RKE2ControlPlane     # Config control plane (replicas, version, CNI)
  |     |
  |     +-- HarvesterMachineTemplate (CP)   # Specs VM control plane
  |
  +-- MachineDeployment    # Definition des workers (replicas, rolling update)
        |
        +-- RKE2ConfigTemplate              # Config bootstrap worker
        +-- HarvesterMachineTemplate (WK)   # Specs VM worker
```

### Addons via ClusterResourceSets

Les ClusterResourceSets (CRS) deploient automatiquement des ressources sur les
clusters downstream qui matchent des labels specifiques :

| CRS | Label | Contenu |
|-----|-------|---------|
| `crs-harvester-ccm` | `ccm: external` | CCM + cloud-config Secret |
| `crs-harvester-csi` | `csi: external` | CSI DaemonSet + Controller + StorageClass |
| `crs-calico-chart-config` | `cni: external` | Calico tolerations pour cloud-provider |

Le CRS CCM contient le Secret `cloud-config` avec le kubeconfig Harvester.
Ce kubeconfig est auto-genere par CAPHV et injecte dans le ConfigMap.

## Deploiement pas a pas

### Etape 1 : Verifier les prerequis

```bash
cd extra/capi
./scripts/00-check-prerequisites.sh
```

Verifie que tous les providers CAPI sont running et les CRDs sont presentes.

### Etape 2 : Installer CAPHV

Si CAPHV n'est pas deja deploye :

```bash
./scripts/01-install-caphv.sh
```

Le manifest d'installation est dans `provider/caphv-install.yaml`.
L'image est construite depuis le fork Gitea et pushee dans le registre Gitea.

### Etape 3 : Creer les prerequis

```bash
# Obtenir le kubeconfig Harvester (depuis l'UI Harvester > Advanced > Download)
export HV_KUBECONFIG_B64=$(base64 -w0 < harvester-kubeconfig.yaml)

./scripts/02-create-prerequisites.sh
```

Cree le namespace (avec label auto-import), la keypair SSH sur Harvester,
et le secret d'identite.

### Etape 4 : Deployer le cluster

```bash
./scripts/03-deploy-cluster.sh
```

Applique les manifestes `Cluster`, `HarvesterCluster`, `RKE2ControlPlane`,
et `HarvesterMachineTemplate`. Attend que le cluster atteigne la phase `Provisioned`.

Duree typique : 10-15 minutes (creation VM + bootstrap RKE2).

### Etape 5 : Deployer les addons CCM/CSI

```bash
./scripts/04-deploy-addons.sh
```

1. Recupere le cloud-config genere par CAPHV
2. Cree les ConfigMaps avec les manifestes CCM et CSI
3. Cree les ClusterResourceSets

Les CRS appliquent automatiquement les manifestes sur le downstream.

### Etape 6 : Ajouter des workers

```bash
./scripts/05-add-workers.sh
```

Deploie le `MachineDeployment` avec le nombre de replicas configure.

### Etape 7 : Verification

```bash
./scripts/06-verify-cluster.sh
```

## Scaling

```bash
# Scale up
./scripts/07-scale-workers.sh --replicas 3

# Scale down
./scripts/07-scale-workers.sh --replicas 1

# Supprimer tous les workers
./scripts/07-scale-workers.sh --replicas 0
```

Le MachineDeployment gere automatiquement la creation/suppression de VMs sur Harvester.

## Nettoyage

```bash
./scripts/08-cleanup.sh
```

L'ordre de suppression est important :
1. Scale workers a 0
2. Supprime le MachineDeployment
3. Supprime les ClusterResourceSets
4. Supprime le Cluster (cascade vers CP, machines, infra)
5. Attend la suppression des machines/VMs
6. Nettoie ConfigMaps et secrets
7. Supprime le namespace

## Variables de configuration

| Variable | Defaut | Description |
|----------|--------|-------------|
| `CAPI_CLUSTER_NAME` | `downstream-rke2` | Nom du cluster |
| `CAPI_NAMESPACE` | `capi-downstream` | Namespace sur le management cluster |
| `CAPI_K8S_VERSION` | `v1.31.6+rke2r1` | Version RKE2 |
| `CAPI_CP_REPLICAS` | `1` | Nombre de noeuds control plane |
| `CAPI_CP_CPU` | `2` | vCPU par noeud CP |
| `CAPI_CP_MEMORY` | `4Gi` | RAM par noeud CP |
| `CAPI_CP_DISK` | `40Gi` | Disque par noeud CP |
| `CAPI_WORKER_REPLICAS` | `1` | Nombre de workers |
| `CAPI_WORKER_CPU` | `1` | vCPU par worker |
| `CAPI_WORKER_MEMORY` | `4Gi` | RAM par worker |
| `CAPI_WORKER_DISK` | `40Gi` | Disque par worker |
| `CAPI_NETWORK` | `default/production` | Reseau VM Harvester |
| `CAPI_VM_ADDRESS` | `172.16.3.40/16` | Adresse IP statique VM |
| `CAPI_CNI` | `calico` | Plugin CNI |
| `RANCHER_HOST` | `172.16.3.20` | IP du management cluster |

## Limitations connues

- **LB DHCP** : Le load balancer CAPI utilise DHCP, l'IP peut changer au redemarrage.
  Configurer un pool IP statique pour la production.
- **Single CP node** : Le PoC utilise 1 seul noeud control plane. Pour la HA,
  passer `CAPI_CP_REPLICAS=3` (necessite 3x les ressources).
- **VM address statique unique** : Avec `networkConfig.address`, toutes les VMs
  du meme template ont la meme IP. Pour plusieurs replicas, utiliser DHCP.
- **Image SLES minimale** : L'image cloud n'a pas de repos. Les packages sont
  limites a ce qui est dans l'image.
