#!/bin/bash

### Script pour installer automatiquement le certificat CA de Rancher
### sur les serveurs downstream

set -e

source ./01-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh

echo "=========================================="
echo "Installation automatique du certificat CA"
echo "sur les serveurs downstream"
echo "=========================================="
echo

### Vérifier que le certificat CA existe
if [[ ! -f rancher-ca.crt ]] || [[ ! -s rancher-ca.crt ]]; then
    echo "Téléchargement du certificat CA de Rancher..."
    ./get-rancher-ca.sh
    if [[ ! -f rancher-ca.crt ]] || [[ ! -s rancher-ca.crt ]]; then
        echo "ERREUR: Impossible de récupérer le certificat CA."
        exit 1
    fi
fi

echo "✓ Certificat CA trouvé: rancher-ca.crt"
openssl x509 -in rancher-ca.crt -noout -subject -issuer -dates 2>/dev/null
echo

### Détecter les serveurs downstream
echo "Détection des serveurs downstream..."
echo

# Option 1: Depuis hosts.list (exclure le manager)
DOWNSTREAM_HOSTS=()
if [[ -f hosts.list ]]; then
    while IFS= read -r host || [[ -n "$host" ]]; do
        [[ -z "$host" || "$host" =~ ^# ]] && continue
        # Exclure le serveur manager
        if [[ ! "$host" =~ "rancher-manager" ]] && [[ ! "$host" =~ "manager" ]]; then
            DOWNSTREAM_HOSTS+=("$host")
        fi
    done < hosts.list
fi

# Option 2: Demander à l'utilisateur
if [[ ${#DOWNSTREAM_HOSTS[@]} -eq 0 ]]; then
    echo "Aucun serveur downstream trouvé dans hosts.list"
    echo
    echo "Entrez les noms d'hôtes des serveurs downstream (un par ligne, ligne vide pour terminer):"
    while true; do
        read -p "Hostname (ou vide pour terminer): " host
        [[ -z "$host" ]] && break
        DOWNSTREAM_HOSTS+=("$host")
    done
fi

if [[ ${#DOWNSTREAM_HOSTS[@]} -eq 0 ]]; then
    echo "Aucun serveur downstream spécifié."
    echo
    echo "Le certificat CA est disponible dans: $(pwd)/rancher-ca.crt"
    echo "Vous pouvez l'installer manuellement sur chaque serveur:"
    echo "  sudo mkdir -p /etc/rancher/ssl"
    echo "  sudo cp rancher-ca.crt /etc/rancher/ssl/cacerts.pem"
    echo "  sudo chmod 644 /etc/rancher/ssl/cacerts.pem"
    echo "  sudo systemctl restart rancher-agent"
    exit 0
fi

echo "Serveurs downstream à configurer: ${#DOWNSTREAM_HOSTS[@]}"
for host in "${DOWNSTREAM_HOSTS[@]}"; do
    echo "  - ${host}"
done
echo

read -p "Continuer avec l'installation ? (y/n): " confirm
if [[ "${confirm}" != "y" ]] && [[ "${confirm}" != "Y" ]]; then
    echo "Annulé."
    exit 0
fi

echo
echo "Installation du certificat CA sur les serveurs downstream..."
echo

SUCCESS=0
FAILED=0

for host in "${DOWNSTREAM_HOSTS[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "→ Installation sur ${host}..."
    echo
    
    # Test de connexion
    if ! ssh_host "$host" "echo 'Connexion OK'" >/dev/null 2>&1; then
        echo "  ✗ Échec de connexion SSH à ${host}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Créer le répertoire
    if ! ssh_host "$host" "sudo mkdir -p /etc/rancher/ssl" 2>/dev/null; then
        echo "  ✗ Échec de création du répertoire sur ${host}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Copier le certificat
    if ! scp_host rancher-ca.crt "$host:/tmp/rancher-ca.crt" 2>/dev/null; then
        echo "  ✗ Échec de copie du certificat vers ${host}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    # Installer le certificat
    if ! ssh_host "$host" "sudo mv /tmp/rancher-ca.crt /etc/rancher/ssl/cacerts.pem && sudo chmod 644 /etc/rancher/ssl/cacerts.pem" 2>/dev/null; then
        echo "  ✗ Échec d'installation du certificat sur ${host}"
        FAILED=$((FAILED + 1))
        continue
    fi
    
    echo "  ✓ Certificat CA installé sur ${host}"
    
    # Vérifier l'installation
    if ssh_host "$host" "test -f /etc/rancher/ssl/cacerts.pem && openssl x509 -in /etc/rancher/ssl/cacerts.pem -noout -subject 2>/dev/null" >/dev/null 2>&1; then
        echo "  ✓ Vérification: certificat valide"
    fi
    
    # Redémarrer l'agent Rancher si présent
    echo "  → Redémarrage de l'agent Rancher (si présent)..."
    ssh_host "$host" "sudo systemctl restart rancher-agent 2>/dev/null || sudo systemctl restart rancher-agent.service 2>/dev/null || echo 'Agent Rancher non trouvé (normal si pas encore installé)'" 2>/dev/null || true
    
    SUCCESS=$((SUCCESS + 1))
    echo
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "Résumé de l'installation:"
echo "  ✓ Succès: ${SUCCESS}"
echo "  ✗ Échecs: ${FAILED}"
echo

if [[ ${SUCCESS} -gt 0 ]]; then
    echo "✓ Installation terminée avec succès sur ${SUCCESS} serveur(s)."
    echo
    echo "Prochaines étapes:"
    echo "  1. Vérifiez dans l'interface Rancher que les clusters downstream"
    echo "     apparaissent et sont en état 'Active'"
    echo "  2. Si les agents ne se connectent toujours pas, vérifiez les logs:"
    echo "     sudo journalctl -u rancher-agent -f"
    echo
fi

if [[ ${FAILED} -gt 0 ]]; then
    echo "⚠ Certaines installations ont échoué."
    echo "  Vérifiez la connectivité SSH et les permissions."
    echo
fi

echo "=========================================="

