#!/bin/bash

### Script pour récupérer le certificat CA de Rancher
### Utilise plusieurs méthodes pour obtenir le certificat

set -e

source ./01-vars.sh

echo "=========================================="
echo "Récupération du certificat CA de Rancher"
echo "=========================================="
echo

CA_FILE="rancher-ca.crt"
RANCHER_URL="${LB_RANCHER_FQDN}"

echo "Tentative de récupération du certificat CA depuis ${RANCHER_URL}..."
echo

### Méthode 1: Via l'API Rancher
echo "Méthode 1: Via l'API Rancher..."
CA_API=$(curl -k -s "https://${RANCHER_URL}/v3-public/cacerts" 2>/dev/null || echo "")

if [[ -n "${CA_API}" ]] && [[ "${CA_API}" != "null" ]] && [[ "${CA_API}" =~ "BEGIN" ]]; then
    echo "${CA_API}" > "${CA_FILE}"
    echo "✓ Certificat CA récupéré via l'API"
    openssl x509 -in "${CA_FILE}" -noout -subject -issuer -dates 2>/dev/null
    echo
    exit 0
fi

### Méthode 2: Depuis la chaîne de certificats SSL
echo "Méthode 2: Depuis la chaîne de certificats SSL..."
CHAIN=$(echo | openssl s_client -connect "${RANCHER_URL}:443" -servername "${RANCHER_URL}" -showcerts 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p')

if [[ -n "${CHAIN}" ]]; then
    # Extraire le certificat CA (généralement le dernier certificat de la chaîne)
    echo "${CHAIN}" | awk '/BEGIN CERTIFICATE/{i++}i>1' > "${CA_FILE}" 2>/dev/null || echo "${CHAIN}" | tail -n +$(echo "${CHAIN}" | grep -n "BEGIN CERTIFICATE" | tail -1 | cut -d: -f1) > "${CA_FILE}" 2>/dev/null
    
    if [[ -s "${CA_FILE}" ]] && openssl x509 -in "${CA_FILE}" -noout -subject 2>/dev/null >/dev/null; then
        echo "✓ Certificat CA récupéré depuis la chaîne SSL"
        openssl x509 -in "${CA_FILE}" -noout -subject -issuer -dates 2>/dev/null
        echo
        exit 0
    fi
fi

### Méthode 3: Depuis le pod Rancher
echo "Méthode 3: Depuis le pod Rancher..."
POD_NAME=$(kubectl get pods -n cattle-system -l app=rancher -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "${POD_NAME}" ]]; then
    CA_POD=$(kubectl exec "${POD_NAME}" -n cattle-system -- cat /etc/rancher/ssl/cacerts.pem 2>/dev/null || echo "")
    
    if [[ -n "${CA_POD}" ]] && [[ "${CA_POD}" =~ "BEGIN" ]]; then
        echo "${CA_POD}" > "${CA_FILE}"
        echo "✓ Certificat CA récupéré depuis le pod Rancher"
        openssl x509 -in "${CA_FILE}" -noout -subject -issuer -dates 2>/dev/null
        echo
        exit 0
    fi
fi

### Méthode 4: Depuis le secret Kubernetes
echo "Méthode 4: Depuis les secrets Kubernetes..."
for secret in tls-rancher tls-rancher-internal-ca; do
    CA_SECRET=$(kubectl get secret "${secret}" -n cattle-system -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    
    if [[ -n "${CA_SECRET}" ]] && [[ "${CA_SECRET}" =~ "BEGIN" ]]; then
        echo "${CA_SECRET}" > "${CA_FILE}"
        echo "✓ Certificat CA récupéré depuis le secret ${secret}"
        openssl x509 -in "${CA_FILE}" -noout -subject -issuer -dates 2>/dev/null
        echo
        exit 0
    fi
done

### Si aucune méthode n'a fonctionné
echo
echo "✗ Impossible de récupérer automatiquement le certificat CA."
echo
echo "SOLUTION MANUELLE:"
echo "1. Connectez-vous à l'interface Rancher: https://${RANCHER_URL}"
echo "2. Allez dans Settings → Certificates"
echo "3. Téléchargez le certificat CA"
echo "4. Enregistrez-le dans: $(pwd)/${CA_FILE}"
echo
echo "OU utilisez cette commande pour extraire le certificat depuis la connexion SSL:"
echo "  echo | openssl s_client -connect ${RANCHER_URL}:443 -servername ${RANCHER_URL} 2>/dev/null | openssl x509 -outform PEM > ${CA_FILE}"
echo
exit 1

