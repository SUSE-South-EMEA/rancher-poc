#!/bin/bash

### Script pour installer le certificat CA sur le serveur downstream 172.16.3.23

set -e

DOWNSTREAM_HOST="172.16.3.23"
SSH_USER="rancher"
CA_FILE="/root/rancher-poc/rancher-ca.crt"

echo "=========================================="
echo "Installation du certificat CA Rancher"
echo "sur le serveur downstream ${DOWNSTREAM_HOST}"
echo "=========================================="
echo

# Vérifier que le certificat existe
if [[ ! -f "${CA_FILE}" ]] || [[ ! -s "${CA_FILE}" ]]; then
    echo "ERREUR: Le fichier ${CA_FILE} n'existe pas ou est vide."
    exit 1
fi

echo "✓ Certificat CA trouvé: ${CA_FILE}"
openssl x509 -in "${CA_FILE}" -noout -subject -issuer -dates 2>/dev/null
echo

# Trouver une clé SSH valide
SSH_KEY=""
for key in ~/.ssh/id_rsa ~/.ssh/id_ed25519 ~/.ssh/id_ecdsa ~/.ssh/id_dsa; do
    if [[ -f "${key}" ]] && [[ -r "${key}" ]]; then
        SSH_KEY="${key}"
        break
    fi
done

# Construire la commande SSH
SSH_CMD="ssh"
if [[ -n "${SSH_KEY}" ]]; then
    SSH_CMD="${SSH_CMD} -i ${SSH_KEY}"
fi
SSH_CMD="${SSH_CMD} -o IdentitiesOnly=yes"
SSH_CMD="${SSH_CMD} -o StrictHostKeyChecking=no"
SSH_CMD="${SSH_CMD} -o ConnectTimeout=10"
SSH_CMD="${SSH_CMD} ${SSH_USER}@${DOWNSTREAM_HOST}"

SCP_CMD="scp"
if [[ -n "${SSH_KEY}" ]]; then
    SCP_CMD="${SCP_CMD} -i ${SSH_KEY}"
fi
SCP_CMD="${SCP_CMD} -o IdentitiesOnly=yes"
SCP_CMD="${SCP_CMD} -o StrictHostKeyChecking=no"
SCP_CMD="${SCP_CMD} -o ConnectTimeout=10"

echo "Test de connexion SSH..."
if ! ${SSH_CMD} "echo 'Connexion OK' && hostname" 2>&1; then
    echo
    echo "✗ Échec de connexion SSH à ${SSH_USER}@${DOWNSTREAM_HOST}"
    echo
    echo "Vérifiez:"
    echo "  1. Que l'utilisateur ${SSH_USER} existe sur le serveur"
    echo "  2. Que votre clé SSH est autorisée"
    echo "  3. Que le serveur est accessible"
    echo
    echo "Vous pouvez tester manuellement:"
    echo "  ssh ${SSH_USER}@${DOWNSTREAM_HOST}"
    exit 1
fi

echo
echo "✓ Connexion SSH réussie"
echo

echo "Installation du certificat CA..."
echo

# Créer le répertoire
echo "→ Création du répertoire /etc/rancher/ssl..."
if ! ${SSH_CMD} "sudo mkdir -p /etc/rancher/ssl" 2>&1; then
    echo "✗ Échec de création du répertoire"
    exit 1
fi
echo "  ✓ Répertoire créé"

# Copier le certificat
echo "→ Copie du certificat..."
if ! ${SCP_CMD} "${CA_FILE}" "${SSH_USER}@${DOWNSTREAM_HOST}:/tmp/rancher-ca.crt" 2>&1; then
    echo "✗ Échec de copie du certificat"
    exit 1
fi
echo "  ✓ Certificat copié"

# Installer le certificat
echo "→ Installation du certificat..."
if ! ${SSH_CMD} "sudo mv /tmp/rancher-ca.crt /etc/rancher/ssl/cacerts.pem && sudo chmod 644 /etc/rancher/ssl/cacerts.pem" 2>&1; then
    echo "✗ Échec d'installation du certificat"
    exit 1
fi
echo "  ✓ Certificat installé"

# Vérifier l'installation
echo "→ Vérification de l'installation..."
${SSH_CMD} "sudo ls -lh /etc/rancher/ssl/cacerts.pem && echo '---' && sudo openssl x509 -in /etc/rancher/ssl/cacerts.pem -noout -subject -issuer -dates 2>/dev/null" 2>&1

# Redémarrer l'agent Rancher si présent
echo
echo "→ Redémarrage de l'agent Rancher (si présent)..."
${SSH_CMD} "sudo systemctl restart rancher-agent 2>/dev/null && echo 'Agent Rancher redémarré' || sudo systemctl restart rancher-agent.service 2>/dev/null && echo 'Agent Rancher redémarré (service)' || echo 'Agent Rancher non trouvé (normal si pas encore installé)'" 2>&1

echo
echo "=========================================="
echo "✓ Installation terminée avec succès !"
echo "=========================================="
echo
echo "Le certificat CA a été installé sur ${DOWNSTREAM_HOST}"
echo
echo "Prochaines étapes:"
echo "  1. Vérifiez dans l'interface Rancher que le serveur apparaît"
echo "  2. Vérifiez les logs de l'agent:"
echo "     ssh ${SSH_USER}@${DOWNSTREAM_HOST} 'sudo journalctl -u rancher-agent -f'"
echo
echo "=========================================="

