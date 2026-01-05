#!/bin/bash

### Script pour corriger le problème SSL de cloud-init
### Configure curl pour utiliser le certificat CA Rancher

set -e

DOWNSTREAM_HOST="172.16.3.23"
SSH_USER="rancher"
SSH_KEY="$HOME/.ssh/id_ed25519"

echo "=========================================="
echo "Correction SSL pour cloud-init"
echo "sur ${SSH_USER}@${DOWNSTREAM_HOST}"
echo "=========================================="
echo

# Vérifier que le certificat existe
if ! ssh -i ${SSH_KEY} -o IdentitiesOnly=yes ${SSH_USER}@${DOWNSTREAM_HOST} "test -f /etc/rancher/ssl/cacerts.pem" 2>/dev/null; then
    echo "ERREUR: Le certificat CA n'existe pas sur le serveur."
    echo "Exécutez d'abord: ./install-ca-172.16.3.23.sh"
    exit 1
fi

echo "✓ Certificat CA trouvé sur le serveur"
echo

# Obtenir le hash du certificat
HASH=$(ssh -i ${SSH_KEY} -o IdentitiesOnly=yes ${SSH_USER}@${DOWNSTREAM_HOST} "sudo openssl x509 -in /etc/rancher/ssl/cacerts.pem -noout -hash 2>/dev/null")

echo "→ Configuration des variables SSL pour curl/cloud-init..."
ssh -i ${SSH_KEY} -o IdentitiesOnly=yes ${SSH_USER}@${DOWNSTREAM_HOST} << 'ENDOFSCRIPT'
    # Créer un wrapper curl qui utilise le certificat CA
    sudo bash -c 'cat > /usr/local/bin/curl-rancher << "EOF"
#!/bin/bash
export SSL_CERT_FILE=/etc/ssl/certs/eea339da.0
export SSL_CERT_DIR=/etc/ssl/certs
/usr/bin/curl "$@"
EOF'
    sudo chmod +x /usr/local/bin/curl-rancher
    
    # Créer un lien symbolique ou modifier le PATH pour cloud-init
    # Alternative: créer /etc/cloud/cloud.cfg.d/99-ssl-certs.cfg
    sudo mkdir -p /etc/cloud/cloud.cfg.d
    sudo bash -c 'cat > /etc/cloud/cloud.cfg.d/99-ssl-certs.cfg << "EOF"
# Configuration SSL pour cloud-init
export SSL_CERT_FILE=/etc/ssl/certs/eea339da.0
export SSL_CERT_DIR=/etc/ssl/certs
EOF'
    
    # Ajouter aux variables système pour tous les processus
    sudo bash -c 'cat >> /etc/environment << EOF
SSL_CERT_FILE=/etc/ssl/certs/eea339da.0
SSL_CERT_DIR=/etc/ssl/certs
EOF'
    
    echo "✓ Configuration SSL appliquée"
ENDOFSCRIPT

echo
echo "→ Test de la connexion curl..."
ssh -i ${SSH_KEY} -o IdentitiesOnly=yes ${SSH_USER}@${DOWNSTREAM_HOST} "export SSL_CERT_FILE=/etc/ssl/certs/eea339da.0 && curl https://rancher.home.lo/ping 2>&1 | head -3"

echo
echo "=========================================="
echo "✓ Configuration terminée"
echo "=========================================="
echo
echo "Les variables SSL sont maintenant configurées pour:"
echo "  • curl (utilisé par cloud-init)"
echo "  • Tous les processus système"
echo
echo "Pour vérifier que cloud-init fonctionne:"
echo "  ssh ${SSH_USER}@${DOWNSTREAM_HOST} 'sudo journalctl -u cloud-init -f'"
echo

