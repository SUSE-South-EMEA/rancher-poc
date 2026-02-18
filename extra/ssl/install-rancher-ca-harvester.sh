#!/bin/bash
# Script pour installer le certificat CA de Rancher sur un serveur Harvester
# Usage: ./install-rancher-ca-harvester.sh [RANCHER_URL]

set -e

RANCHER_URL="${1:-https://rancher.home.lo}"
CA_DEST="/etc/kubernetes/ssl/certs/serverca"

echo "🔧 Installation du certificat CA de Rancher sur Harvester"
echo "📍 URL Rancher: ${RANCHER_URL}"
echo

# Créer le répertoire de destination
echo "📁 Création du répertoire de destination..."
sudo mkdir -p /etc/kubernetes/ssl/certs

# Télécharger et installer le certificat CA
echo "📥 Téléchargement du certificat CA depuis Rancher..."
curl -k -L -s "${RANCHER_URL}/v3-public/cacerts" | sudo tee ${CA_DEST} > /dev/null

if [ ! -s ${CA_DEST} ]; then
    echo "❌ Erreur: Impossible de télécharger le certificat CA"
    echo "💡 Essayez avec l'IP directe: curl -k -L https://172.16.3.20/v3-public/cacerts"
    exit 1
fi

sudo chmod 644 ${CA_DEST}

echo "✅ Certificat CA installé dans ${CA_DEST}"
echo

# Calculer le checksum
if command -v openssl &> /dev/null; then
    CA_CHECKSUM=$(openssl x509 -in ${CA_DEST} -noout -fingerprint -sha256 2>&1 | cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
    echo "📋 Checksum CA: ${CA_CHECKSUM}"
    echo
    echo "💡 Pour utiliser ce checksum dans la configuration Rancher:"
    echo "   CATTLE_CA_CHECKSUM=${CA_CHECKSUM}"
fi

