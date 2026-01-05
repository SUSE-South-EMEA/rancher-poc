# Extra - Scripts et Documentation Additionnels

Ce répertoire contient des scripts et de la documentation qui ne sont pas essentiels au déploiement de base de Rancher, mais qui peuvent être utiles pour des cas d'usage spécifiques.

## Scripts SSL/TLS

### Gestion des certificats CA

- **`get-rancher-ca.sh`** - Récupère le certificat CA de Rancher
- **`install-ca-auto.sh`** - Installation automatique du certificat CA
- **`install-ca-downstream.sh`** - Installation du CA pour les clusters downstream
- **`install-rancher-ca-harvester.sh`** - Installation du certificat CA de Rancher sur un serveur Harvester

### Correction des problèmes SSL

- **`fix-ssl-certificate.sh`** - Corrige les problèmes de certificat SSL
- **`fix-ssl-downstream.sh`** - Corrige les problèmes SSL pour les clusters downstream
- **`fix-cloud-init-ssl.sh`** - Corrige les problèmes SSL dans cloud-init

## Intégration Traefik

- **`install-traefik-rancher.sh`** - Installe Traefik pour Rancher
- **`configure-traefik-dns-challenge.sh`** - Configure le défi DNS pour Traefik

## Documentation

- **`CODE_REVIEW.md`** - Analyse du code et suggestions d'amélioration
- **`SSH_USER_CONFIG.md`** - Documentation sur la configuration de l'utilisateur SSH
- **`INSTALL-TRAEFIK-RANCHER.md`** - Instructions d'installation de Traefik avec Rancher
- **`INSTRUCTIONS-INSTALLATION-CA.md`** - Instructions pour l'installation du certificat CA
- **`SOLUTION-SSL-DOWNSTREAM.md`** - Solutions pour les problèmes SSL avec les clusters downstream
- **`README-SSL-FIX.md`** - Guide de correction des problèmes SSL

## Utilisation

Ces scripts sont optionnels et peuvent être utilisés selon vos besoins spécifiques. Consultez la documentation correspondante pour plus d'informations sur chaque script.

