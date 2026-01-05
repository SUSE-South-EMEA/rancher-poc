# Rancher PoC

Déploiement de Rancher basé sur un cluster RKE2.

## Objectifs

Cet ensemble de scripts vise à simplifier le déploiement d'un serveur de gestion Rancher hautement disponible sur un cluster RKE2.

Il supporte actuellement les options de déploiement suivantes :
- Accès direct à Internet
- Internet accessible via Proxy
- Airgap
- Systèmes d'exploitation basés sur zypper, yum ou apt (devrait fonctionner sur SLES 15 SP2/SP3, CentOS/RHEL 8, Ubuntu 18.04/20.04)

## Structure du projet

### Scripts principaux

Les scripts suivants sont essentiels pour votre expérience :

- **`00-common.sh`** : Fonctions communes utilisées par tous les scripts
- **`01-vars.sh`** : Variables de configuration
- **`00-prepare-airgap_OPTIONAL.sh`** : Préparation pour le déploiement airgap (optionnel)
- **`02-ssh-keys_create_exchange_check.sh`** : Création, déploiement et vérification des clés SSH
- **`03-os_preparation_PACKAGES.sh`** : Validation et préparation des paquets système
- **`04-os_preparation_NETWORKING.sh`** : Validation et préparation du réseau
- **`05-rke2_deploy.sh`** : Déploiement RKE2
- **`06-rancher_install.sh`** : Déploiement du serveur de gestion Rancher
- **`08-cleanup-destroy.sh`** : Nettoyage des serveurs cibles pour recommencer
- **`09-def_gw-ipv6.sh`** : Configuration de la passerelle par défaut IPv6 (optionnel)

### Répertoire `extra/`

Le répertoire `extra/` contient des scripts et de la documentation additionnels non essentiels au déploiement de base :

- **`extra/ssl/`** : Scripts et documentation pour la gestion SSL/TLS et des certificats CA
- **`extra/traefik/`** : Scripts et configuration pour l'intégration Traefik
- **`extra/docs/`** : Documentation additionnelle sur le projet
- **`extra/examples/`** : Exemples de scripts spécifiques à des hôtes

Voir [extra/README.md](extra/README.md) pour plus de détails.

## Prérequis

### Systèmes

- 1 serveur admin
  > Le serveur que vous utiliserez pour exécuter les scripts

- 3 serveurs de gestion Rancher (ou plus)
  > Ces machines seront utilisées pour un cluster RKE2 qui hébergera l'interface de gestion Rancher
  > Les nœuds auront les rôles : etcd, controlplane et worker

Les serveurs sont déployés en utilisant des standards classiques :
- Configuration réseau fixe
- Accès Internet (avec ou sans proxy) ou déploiement Airgap (avec ou sans proxy)
- L'heure doit être correctement configurée
- Le DNS doit être correct
- Le pare-feu doit être désactivé
- ... les scripts sont là pour essayer et valider que tous vos paramètres sont bons pour le déploiement.

### Réseau

L'interface Rancher nécessitera un FQDN qui équilibre la charge des connexions vers les nœuds du serveur de gestion Rancher.

(optionnel) Vous pourriez également avoir besoin d'un FQDN générique pour accéder facilement à vos applications sur les futurs clusters K8S que vous déploierez.

## Utilisation

### Cloner le dépôt

```bash
git clone https://github.com/SUSE-South-EMEA/rancher-poc.git
cd rancher-poc
```

### hosts.list - Liste des nœuds cibles

Ce fichier contient la liste des nœuds cibles qui seront membres du cluster RKE2 et hébergeront le serveur de gestion Rancher.

1 FQDN ou adresse IP par ligne. Le fichier est généré automatiquement à partir de la variable `HOST_LIST` dans `01-vars.sh`.

### 01-vars.sh - Variables à configurer

Les variables de ce fichier seront utilisées par les scripts.

Éditez ce fichier et configurez tout selon votre environnement et le scénario de déploiement requis (normal, proxy, airgap).

### 00-prepare-airgap_OPTIONAL.sh - Uniquement pour le déploiement Airgap

Ce script est uniquement nécessaire en cas de déploiement airgap.

Il doit être exécuté sur un nœud avec accès Internet et téléchargera tout ce qui est nécessaire pour les étapes suivantes.

Une fois exécuté, copiez tout le répertoire rancher-poc vers le serveur admin (nœud de déploiement) et continuez avec les scripts suivants.

### 02-ssh-keys_create_exchange_check.sh - Clés SSH

Script pour créer, déployer et vérifier les clés SSH sur les nœuds cibles.

```bash
./02-ssh-keys_create_exchange_check.sh
```

### 03-os_preparation_PACKAGES.sh - Préparation des paquets

Script pour valider l'environnement et installer les prérequis de paquets.

```bash
./03-os_preparation_PACKAGES.sh
```

### 04-os_preparation_NETWORKING.sh - Préparation du réseau

Script pour valider et configurer les paramètres réseau (pare-feu, passerelle, synchronisation du temps, IP forwarding).

```bash
./04-os_preparation_NETWORKING.sh
```

### 05-rke2_deploy.sh - Installation du cluster RKE2

Déploie un cluster RKE2 sur les nœuds cibles.

```bash
./05-rke2_deploy.sh
```

### 06-rancher_install.sh - Installation du serveur de gestion Rancher

Déploie le serveur de gestion Rancher sur le cluster RKE2 précédemment déployé.

```bash
./06-rancher_install.sh
```

### 08-cleanup-destroy.sh - Nettoyage (ATTENTION!)

Nettoie tout. Il n'y a pas de retour en arrière.

```bash
./08-cleanup-destroy.sh
```

## Ordre d'exécution recommandé

1. Configurer `01-vars.sh` selon votre environnement
2. (Optionnel) Exécuter `00-prepare-airgap_OPTIONAL.sh` si déploiement airgap
3. Exécuter `02-ssh-keys_create_exchange_check.sh` pour configurer l'accès SSH
4. Exécuter `03-os_preparation_PACKAGES.sh` pour préparer les paquets système
5. Exécuter `04-os_preparation_NETWORKING.sh` pour préparer le réseau
6. Exécuter `05-rke2_deploy.sh` pour déployer le cluster RKE2
7. Exécuter `06-rancher_install.sh` pour installer Rancher
8. (Optionnel) Utiliser les scripts dans `extra/` selon vos besoins spécifiques

## Scripts additionnels

Consultez le répertoire `extra/` pour des scripts additionnels :
- Gestion SSL/TLS et certificats CA
- Intégration Traefik
- Documentation additionnelle
- Exemples de scripts

## Support

Pour plus d'informations, consultez la documentation dans le répertoire `extra/docs/` et les README dans chaque sous-répertoire de `extra/`.
