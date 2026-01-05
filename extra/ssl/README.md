# SSL/TLS Certificate Management

Ce répertoire contient les scripts et la documentation pour la gestion des certificats SSL/TLS et CA dans Rancher.

## Scripts d'installation du certificat CA

- **`get-rancher-ca.sh`** - Récupère le certificat CA de Rancher depuis le serveur
- **`install-ca-auto.sh`** - Installation automatique du certificat CA
- **`install-ca-downstream.sh`** - Installation du CA pour les clusters downstream
- **`install-rancher-ca-harvester.sh`** - Installation du certificat CA de Rancher sur un serveur Harvester

## Scripts de correction SSL

- **`fix-ssl-certificate.sh`** - Corrige les problèmes de certificat SSL généraux
- **`fix-ssl-downstream.sh`** - Corrige les problèmes SSL spécifiques aux clusters downstream
- **`fix-cloud-init-ssl.sh`** - Corrige les problèmes SSL dans les configurations cloud-init

## Documentation

- **`INSTRUCTIONS-INSTALLATION-CA.md`** - Instructions détaillées pour l'installation du certificat CA
- **`README-SSL-FIX.md`** - Guide de dépannage et correction des problèmes SSL
- **`SOLUTION-SSL-DOWNSTREAM.md`** - Solutions spécifiques pour les problèmes SSL avec les clusters downstream

## Utilisation

Consultez la documentation correspondante pour plus d'informations sur chaque script et les cas d'usage spécifiques.

