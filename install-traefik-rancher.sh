#!/bin/bash

### Script d'installation des règles Traefik pour Rancher
### À exécuter sur rasp01 ou depuis un serveur avec accès à rasp01

set -e

# Couleurs
bold=$(tput bold)
normal=$(tput sgr0)
red=$(tput setaf 1)
green=$(tput setaf 2)

# Source variables
if [[ -f ./01-vars.sh ]]; then
    source ./01-vars.sh
else
    echo "${red}Erreur: 01-vars.sh non trouvé${normal}"
    exit 1
fi

# Configuration
RANCHER_HOST="${LB_RANCHER_FQDN:-rancher.home.lo}"
RANCHER_USER_FQDN="${LB2_RANCHER_FQDN:-rancher.home.zypp.fr}"
TRAEFIK_HOST="${TRAEFIK_HOST:-rasp01}"
TRAEFIK_USER="${TRAEFIK_USER:-ju}"

echo "${bold}╔══════════════════════════════════════════════════════════════╗${normal}"
echo "${bold}║  Installation des règles Traefik pour Rancher                ║${normal}"
echo "${bold}╚══════════════════════════════════════════════════════════════╝${normal}"
echo
echo "Configuration:"
echo "  - Rancher host: ${RANCHER_HOST}"
echo "  - Rancher user FQDN: ${RANCHER_USER_FQDN}"
echo "  - Traefik host: ${TRAEFIK_USER}@${TRAEFIK_HOST}"
echo

# Demander le type de déploiement Traefik
echo "Quel est le type de déploiement Traefik sur ${TRAEFIK_HOST}?"
echo "  1) Docker Compose"
echo "  2) Docker avec labels"
echo "  3) Kubernetes (IngressRoute)"
echo "  4) Fichier de configuration statique/dynamique"
echo "  5) Je ne sais pas (détection automatique)"
echo
read -p "Choix [1-5]: " deploy_type

case $deploy_type in
    1)
        echo
        echo "${bold}Méthode: Docker Compose${normal}"
        echo "Copiez traefik-rancher-docker-compose.yml sur ${TRAEFIK_USER}@${TRAEFIK_HOST} et exécutez:"
        echo "  scp traefik-rancher-docker-compose.yml ${TRAEFIK_USER}@${TRAEFIK_HOST}:~/"
        echo "  ssh ${TRAEFIK_USER}@${TRAEFIK_HOST} 'docker-compose -f traefik-rancher-docker-compose.yml up -d'"
        ;;
    2)
        echo
        echo "${bold}Méthode: Docker avec labels${normal}"
        echo "Ajoutez les labels suivants à votre conteneur Traefik:"
        echo
        cat << EOF
labels:
  - "traefik.http.routers.rancher-zypp.rule=Host(\`${RANCHER_USER_FQDN}\`)"
  - "traefik.http.routers.rancher-zypp.entrypoints=websecure"
  - "traefik.http.routers.rancher-zypp.tls.certresolver=letsencrypt"
  - "traefik.http.services.rancher-zypp.loadbalancer.server.url=http://${RANCHER_HOST}:80"
  - "traefik.http.services.rancher-zypp.loadbalancer.passhostheader=true"
  
  - "traefik.http.routers.rancher-lo.rule=Host(\`${RANCHER_HOST}\`)"
  - "traefik.http.routers.rancher-lo.entrypoints=websecure"
  - "traefik.http.routers.rancher-lo.tls.certresolver=letsencrypt"
  - "traefik.http.services.rancher-lo.loadbalancer.server.url=http://${RANCHER_HOST}:80"
  - "traefik.http.services.rancher-lo.loadbalancer.passhostheader=true"
EOF
        ;;
    3)
        echo
        echo "${bold}Méthode: Kubernetes${normal}"
        echo "Appliquez la configuration:"
        echo "  kubectl apply -f traefik-rancher-kubernetes.yaml"
        ;;
    4)
        echo
        echo "${bold}Méthode: Fichier de configuration${normal}"
        echo "Copiez traefik-rancher-config.yaml vers /etc/traefik/dynamic/rancher.yaml sur ${TRAEFIK_USER}@${TRAEFIK_HOST}"
        echo
        read -p "Voulez-vous générer les commandes pour copier le fichier? (y/n): " generate_commands
        if [[ "$generate_commands" == "y" ]]; then
            echo
            echo "Commandes à exécuter:"
            echo "  scp traefik-rancher-config.yaml ${TRAEFIK_USER}@${TRAEFIK_HOST}:/tmp/"
            echo "  ssh ${TRAEFIK_USER}@${TRAEFIK_HOST} 'sudo mkdir -p /etc/traefik/dynamic && sudo cp /tmp/traefik-rancher-config.yaml /etc/traefik/dynamic/rancher.yaml && sudo systemctl restart traefik'"
        fi
        ;;
    5)
        echo
        echo "${bold}Détection automatique${normal}"
        echo "Tentative de détection du type de déploiement..."
        echo
        echo "Vérifiez manuellement sur ${TRAEFIK_USER}@${TRAEFIK_HOST}:"
        echo "  ssh ${TRAEFIK_USER}@${TRAEFIK_HOST} 'docker ps | grep traefik'"
        echo "  ssh ${TRAEFIK_USER}@${TRAEFIK_HOST} 'kubectl get pods | grep traefik'"
        echo "  ssh ${TRAEFIK_USER}@${TRAEFIK_HOST} 'systemctl status traefik'"
        echo "  ssh ${TRAEFIK_USER}@${TRAEFIK_HOST} 'ls -la /etc/traefik/'"
        echo
        echo "Puis relancez ce script avec le bon choix."
        ;;
    *)
        echo "${red}Choix invalide${normal}"
        exit 1
        ;;
esac

echo
echo "${bold}╔══════════════════════════════════════════════════════════════╗${normal}"
echo "${bold}║  Vérification de la configuration                            ║${normal}"
echo "${bold}╚══════════════════════════════════════════════════════════════╝${normal}"
echo
echo "Après installation, vérifiez avec:"
echo "  curl -k https://${RANCHER_USER_FQDN}/ping"
echo "  curl -k https://${RANCHER_HOST}/ping"
echo
echo "Les deux doivent retourner 'pong'"
echo
echo "Pour plus de détails, consultez INSTALL-TRAEFIK-RANCHER.md"
echo

