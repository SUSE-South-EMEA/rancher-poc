#!/bin/bash

### Script pour ajouter la clé publique SSH à authorized_keys sur 172.16.3.23
### Puis installer le certificat CA Rancher

set -e

DOWNSTREAM_HOST="172.16.3.23"
SSH_USER="rancher"

echo "=========================================="
echo "Ajout de la clé publique SSH"
echo "sur ${SSH_USER}@${DOWNSTREAM_HOST}"
echo "=========================================="
echo

# Trouver la clé publique
PUBLIC_KEY=""
for key in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub ~/.ssh/id_dsa.pub; do
    if [[ -f "${key}" ]] && [[ -r "${key}" ]]; then
        PUBLIC_KEY="${key}"
        break
    fi
done

if [[ -z "${PUBLIC_KEY}" ]]; then
    echo "ERREUR: Aucune clé publique trouvée."
    echo "Générez une clé SSH avec: ssh-keygen -t ed25519"
    exit 1
fi

echo "✓ Clé publique trouvée: ${PUBLIC_KEY}"
echo
echo "Clé publique à ajouter:"
cat "${PUBLIC_KEY}"
echo
echo "=========================================="
echo "INSTRUCTIONS:"
echo "=========================================="
echo
echo "Pour ajouter cette clé à authorized_keys sur ${DOWNSTREAM_HOST}:"
echo
echo "Option 1 - Si vous avez un accès (mot de passe, autre clé, etc.):"
echo "  ssh ${SSH_USER}@${DOWNSTREAM_HOST}"
echo "  mkdir -p ~/.ssh"
echo "  chmod 700 ~/.ssh"
echo "  echo '$(cat ${PUBLIC_KEY})' >> ~/.ssh/authorized_keys"
echo "  chmod 600 ~/.ssh/authorized_keys"
echo
echo "Option 2 - En une seule commande (si vous avez un accès):"
echo "  ssh ${SSH_USER}@${DOWNSTREAM_HOST} \"mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$(cat ${PUBLIC_KEY})' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys\""
echo
echo "Option 3 - Copier manuellement:"
echo "  1. Connectez-vous au serveur ${DOWNSTREAM_HOST}"
echo "  2. Exécutez: mkdir -p ~/.ssh && chmod 700 ~/.ssh"
echo "  3. Ajoutez cette ligne à ~/.ssh/authorized_keys:"
echo "     $(cat ${PUBLIC_KEY})"
echo "  4. Exécutez: chmod 600 ~/.ssh/authorized_keys"
echo
echo "=========================================="
echo

read -p "Voulez-vous essayer d'ajouter la clé automatiquement ? (y/n): " try_auto

if [[ "${try_auto}" == "y" ]] || [[ "${try_auto}" == "Y" ]]; then
    echo
    echo "Tentative d'ajout automatique de la clé..."
    echo "(Cela nécessite un accès par mot de passe ou autre méthode)"
    echo
    
    # Essayer avec ssh-copy-id si disponible
    if command -v ssh-copy-id >/dev/null 2>&1; then
        echo "Utilisation de ssh-copy-id..."
        ssh-copy-id -i "${PUBLIC_KEY}" "${SSH_USER}@${DOWNSTREAM_HOST}" 2>&1 || {
            echo "✗ ssh-copy-id a échoué. Utilisez les instructions manuelles ci-dessus."
            exit 1
        }
    else
        # Essayer manuellement
        KEY_CONTENT=$(cat "${PUBLIC_KEY}")
        ssh "${SSH_USER}@${DOWNSTREAM_HOST}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '${KEY_CONTENT}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 2>&1 || {
            echo "✗ Échec de l'ajout automatique. Utilisez les instructions manuelles ci-dessus."
            exit 1
        }
    fi
    
    echo "✓ Clé publique ajoutée avec succès !"
    echo
    
    # Tester la connexion
    echo "Test de la connexion SSH..."
    if ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i "${PUBLIC_KEY%.pub}" "${SSH_USER}@${DOWNSTREAM_HOST}" "echo 'Connexion OK' && hostname" 2>&1; then
        echo "✓ Connexion SSH réussie !"
        echo
        echo "Vous pouvez maintenant installer le certificat CA avec:"
        echo "  cd /root/rancher-poc"
        echo "  ./install-ca-172.16.3.23.sh"
    else
        echo "⚠ La connexion a échoué. Vérifiez que la clé a bien été ajoutée."
    fi
else
    echo
    echo "Suivez les instructions ci-dessus pour ajouter la clé manuellement."
    echo "Ensuite, vous pourrez installer le certificat CA avec:"
    echo "  cd /root/rancher-poc"
    echo "  ./install-ca-172.16.3.23.sh"
fi

echo
echo "=========================================="

