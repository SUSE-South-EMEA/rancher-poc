# Rancher PoC - High Availability

## Objectif & Contenu

This set of scripts is trying to ease a highly available Rancher management deployment:
- with or without proxy
- for ZYPPER based or YUM based OSes
- APT based OSes will come

The following files are crucial for your experience:
hosts.list
00-vars.sh
01-os_preparation.sh
02-rke_deploy.sh
03-rancher_install.sh
0X-rke_destroy-airgap.sh

## Pre-requisite

### Systems
- 1 admin machine
 > The machine you will use to execute the scripts
- 3 rancher management machines
 > These 3 machines will for a 3 nodes RKE cluster which will hold the Rancher Management UI
 > The 3 nodes will have: ETCD role, Controlplane role and Worker role

The machines are deployed using classic standards
 > Fixed network settings
 > Internet access (with or without proxy) / Airgap deployment is also possible but not yet implemented in the scripts
 > Time should be well set
 > DNS should be correct
 > Firewall should be deactivated
 > ... the scripts are here to try and validate that all your settings are good for deployment.

### Network
The Rancher management UI will need a FQDN which load balances the connections toward the rancher management machines
(optional) You may also need a wildcard FQDN to easily access your applications on the future K8S clusters you will then deploy

2. Repository clone

```bash
mkdir rancher && cd rancher
git config --global http.sslVerify false
git clone http://git.zypp.fr/se/rancher-poc.git
cd rancher-poc
```

## hosts.list - Declaration des machines a piloter
Ce fichier contient la liste des machines à piloter à distance qui seront membres du futur cluster K8S à déployer.
1 FQDN ou IP doit etre present par ligne.

## 00-vars.sh
Ce fichier contient les variables à utiliser par les scripts.
Veuillez editer ce fichier au prealable, des commentaires/aides sont presents a l'interieur.
Dans le cadre de l'utilisation d'un proxy, il faut ajouter dans le repertoire courant du script le fichier representant la clef du certificat d'autorité.

## 01-os_preparation.sh - Preparation et verification des socles

Exécution des scripts de validation de l'environnement

```bash
./01-os_preparation.sh
```

## 02-rke_deploy.sh - RKE Cluster installation

Exécution des scripts de validation de l'environnement

```bash
./02-rke_deploy.sh
```

## 03-rancher_install.sh - Rancher Management installation

Exécution des scripts de validation de l'environnement

```bash
./03-rancher_install.sh
```

## 0X-rke_destroy-airgap.sh - Cleanup (CAREFUL!)

If you're fed up about all this, try this script it will clean.
There's no turning back.

```bash
./0X-rke_destroy-airgap.sh
```

