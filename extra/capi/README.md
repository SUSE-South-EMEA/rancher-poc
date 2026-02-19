# CAPI Provider Harvester (CAPHV) — PoC reproductible

Provisionnement automatise de clusters Kubernetes downstream sur Harvester
via Cluster API (CAPI) avec le provider CAPHV.

## Composants

| Composant | Namespace | Role |
|-----------|-----------|------|
| Rancher Turtles | cattle-turtles-system | Integration CAPI dans Rancher |
| CAPI Core | cattle-capi-system | Orchestration Cluster API |
| RKE2 Bootstrap/CP | rke2-*-system | Bootstrap et control plane RKE2 |
| CAPHV | caphv-system | Infrastructure provider Harvester |

## Quick Start

```bash
# 1. Verifier les prerequis
./scripts/00-check-prerequisites.sh

# 2. Installer CAPHV (si pas deja present)
./scripts/01-install-caphv.sh

# 3. Creer namespace, cle SSH, identity secret
export HV_KUBECONFIG_B64=$(base64 -w0 < harvester-kubeconfig.yaml)
./scripts/02-create-prerequisites.sh

# 4. Deployer le cluster (Cluster + ControlPlane)
./scripts/03-deploy-cluster.sh

# 5. Deployer les addons CCM/CSI (ClusterResourceSets)
./scripts/04-deploy-addons.sh

# 6. Ajouter des workers
./scripts/05-add-workers.sh

# 7. Verifier
./scripts/06-verify-cluster.sh
```

## Configuration

Les variables sont definies dans `configs/capi-vars.sh` (valeurs par defaut).
Pour surcharger, creer `configs/capi-homelab.sh` (gitignore) et passer via `--config` :

```bash
./scripts/03-deploy-cluster.sh --config=configs/capi-homelab.sh
```

Voir `configs/capi-homelab.sh.example` pour un exemple.

## Structure

```
configs/
  capi-vars.sh               Variables par defaut
  capi-homelab.sh.example     Exemple de surcharge homelab
manifests/
  00-namespace.yaml           Namespace du cluster
  01-identity-secret.yaml.tmpl Template du secret Harvester
  02-cluster.yaml             Cluster + HarvesterCluster
  03-control-plane.yaml       RKE2ControlPlane + MachineTemplate
  04-workers.yaml             MachineDeployment workers
  addons/
    cluster-resource-set.yaml ClusterResourceSets CCM/CSI/Calico
    harvester-ccm-configmap.yaml  Manifestes CCM
    harvester-csi-configmap.yaml  Manifestes CSI
    calico-helm-config.yaml       Config Calico tolerations
provider/
  caphv-install.yaml          Manifestes d'installation CAPHV
scripts/
  00-check-prerequisites.sh   Verifie les providers CAPI
  01-install-caphv.sh         Installe/upgrade CAPHV
  02-create-prerequisites.sh  Namespace, cle SSH, identity secret
  03-deploy-cluster.sh        Deploie le cluster (CP)
  04-deploy-addons.sh         Deploie CCM/CSI via CRS
  05-add-workers.sh           Ajoute les workers
  06-verify-cluster.sh        Verification complete
  07-scale-workers.sh         Scale up/down les workers
  08-cleanup.sh               Supprime le cluster
```

## Scaling

```bash
# Scale a 2 workers
./scripts/07-scale-workers.sh --replicas 2

# Scale a zero (supprime les workers)
./scripts/07-scale-workers.sh --replicas 0
```

## Nettoyage

```bash
# Interactif (demande confirmation)
./scripts/08-cleanup.sh

# Force (sans confirmation)
./scripts/08-cleanup.sh --force
```

## Architecture

```
                   Management Cluster (rancher-manager-0)
                   +-----------------------------------------+
                   | Rancher v2.13.1 + Turtles               |
                   | CAPI Core + RKE2 Bootstrap/CP           |
                   | CAPHV Controller                        |
                   |                                         |
                   | Cluster + HarvesterCluster              |
                   | RKE2ControlPlane                        |
                   | MachineDeployment (workers)             |
                   | ClusterResourceSets (CCM/CSI/Calico)    |
                   +-----------+-----------------------------+
                               |
                               | provisions VMs via
                               v
                   Harvester HCI (172.16.3.100)
                   +-----------------------------------------+
                   | VM: downstream CP node                  |
                   | VM: downstream worker node(s)           |
                   | LB: API server endpoint (DHCP)          |
                   +-----------+-----------------------------+
                               |
                               | runs
                               v
                   Downstream Cluster
                   +-----------------------------------------+
                   | RKE2 + Calico CNI                       |
                   | Harvester CCM (cloud-provider)          |
                   | Harvester CSI (storage)                 |
                   | Ingress NGINX                           |
                   | Auto-imported into Rancher              |
                   +-----------------------------------------+
```

## Troubleshooting

### Le cluster reste en phase "Provisioning"
```bash
# Verifier les machines
ssh rancher@172.16.3.20 "$KUBECTL get machines -n <namespace> -o wide"
# Verifier les logs CAPHV
ssh rancher@172.16.3.20 "$KUBECTL logs -n caphv-system deploy/caphv-controller-manager -f"
```

### CCM/CSI ne demarre pas
```bash
# Verifier que le ClusterResourceSet a applique les ressources
ssh rancher@172.16.3.20 "$KUBECTL get clusterresourceset -n <namespace>"
# Verifier le secret cloud-config sur le downstream
kubectl --kubeconfig /tmp/downstream.kubeconfig get secret cloud-config -n kube-system
```

### Le downstream n'est pas visible dans Rancher
Le namespace doit avoir le label `cluster-api.cattle.io/rancher-auto-import: "true"`.
L'import peut prendre 2-3 minutes.
