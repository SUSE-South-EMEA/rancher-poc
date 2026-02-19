# Extra - Scripts et Documentation Additionnels

Ce répertoire contient des scripts et de la documentation qui ne sont pas essentiels au déploiement de base de Rancher, mais qui peuvent être utiles pour des cas d'usage spécifiques.

## Structure

### `ssl/` - Gestion SSL/TLS et certificats CA

Contient tous les scripts et la documentation pour la gestion des certificats SSL/TLS et CA :
- Scripts d'installation du certificat CA
- Scripts de correction des problèmes SSL
- Documentation SSL/TLS

Voir [ssl/README.md](ssl/README.md) pour plus de détails.

### `traefik/` - Intégration Traefik

Contient les scripts et fichiers de configuration pour intégrer Traefik avec Rancher :
- Scripts d'installation et de configuration
- Fichiers de configuration (Kubernetes, Docker Compose, etc.)
- Documentation Traefik

Voir [traefik/README.md](traefik/README.md) pour plus de détails.

### `capi/` - Cluster API Provider Harvester (CAPHV)

Contient les manifestes, scripts et documentation pour le provisionnement de clusters Kubernetes downstream sur Harvester via Cluster API :
- Manifestes CAPI (Cluster, ControlPlane, MachineDeployment, ClusterResourceSets)
- Scripts reproductibles de deploiement et scaling
- Provider CAPHV (installation manifests)
- Configuration parametrable

Voir [capi/README.md](capi/README.md) pour plus de details.

### `docs/` - Documentation additionnelle

Contient la documentation generale sur le projet :
- Analyse du code
- Documentation de configuration
- Guide de deploiement CAPI

Voir [docs/README.md](docs/README.md) pour plus de details.

## Utilisation

Ces scripts sont optionnels et peuvent être utilisés selon vos besoins spécifiques. Consultez la documentation dans chaque sous-répertoire pour plus d'informations.

