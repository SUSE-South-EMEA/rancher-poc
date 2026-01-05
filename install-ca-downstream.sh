#!/bin/bash

### Script pour installer le certificat CA de Rancher sur les serveurs downstream
### Résout les problèmes SSL lors de l'enregistrement des serveurs

set -e

source ./01-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh

echo "=========================================="
echo "Installation du certificat CA Rancher"
echo "sur les serveurs downstream"
echo "=========================================="
echo

### Vérifier que le certificat CA existe
if [[ ! -f rancher-ca.crt ]]; then
    echo "Téléchargement du certificat CA de Rancher..."
    kubectl get secret tls-rancher -n cattle-system -o jsonpath='{.data.ca\.crt}' | base64 -d > rancher-ca.crt
    if [[ ! -f rancher-ca.crt ]] || [[ ! -s rancher-ca.crt ]]; then
        echo "ERREUR: Impossible de télécharger le certificat CA."
        echo "Vérifiez que Rancher est installé et que le secret tls-rancher existe."
        exit 1
    fi
    echo "✓ Certificat CA téléchargé: rancher-ca.crt"
else
    echo "✓ Certificat CA trouvé: rancher-ca.crt"
fi

echo
echo "Informations du certificat CA:"
openssl x509 -in rancher-ca.crt -noout -subject -issuer -dates 2>/dev/null
echo

### Demander les serveurs downstream
echo
echo "Sur quels serveurs downstream voulez-vous installer le certificat CA ?"
echo "  1) Tous les serveurs listés dans hosts.list"
echo "  2) Spécifier manuellement"
echo "  3) Copier le certificat localement uniquement"
echo
read -p "Choix [1-3]: " choice

case $choice in
    1)
        ### Installer sur tous les serveurs de hosts.list
        if [[ ! -f hosts.list ]] || [[ ! -s hosts.list ]]; then
            echo "ERREUR: Le fichier hosts.list n'existe pas ou est vide."
            exit 1
        fi
        
        echo
        echo "Installation du certificat CA sur les serveurs downstream..."
        echo
        
        while IFS= read -r host || [[ -n "$host" ]]; do
            # Ignorer les lignes vides et les commentaires
            [[ -z "$host" || "$host" =~ ^# ]] && continue
            
            echo "→ Installation sur ${host}..."
            
            # Créer le répertoire et copier le certificat
            ssh_host "$host" "sudo mkdir -p /etc/rancher/ssl" || {
                echo "  ✗ Échec de connexion à ${host}"
                continue
            }
            
            scp_host rancher-ca.crt "$host:/tmp/rancher-ca.crt" || {
                echo "  ✗ Échec de copie vers ${host}"
                continue
            }
            
            ssh_host "$host" "sudo mv /tmp/rancher-ca.crt /etc/rancher/ssl/cacerts.pem && sudo chmod 644 /etc/rancher/ssl/cacerts.pem" || {
                echo "  ✗ Échec d'installation sur ${host}"
                continue
            }
            
            echo "  ✓ Certificat CA installé sur ${host}"
            
            # Redémarrer l'agent Rancher si présent
            echo "  → Redémarrage de l'agent Rancher (si présent)..."
            ssh_host "$host" "sudo systemctl restart rancher-agent 2>/dev/null || sudo systemctl restart rancher-agent.service 2>/dev/null || echo 'Agent Rancher non trouvé (normal si pas encore installé)'" || true
            
        done < hosts.list
        
        echo
        echo "✓ Installation terminée sur tous les serveurs."
        ;;
        
    2)
        ### Installer sur des serveurs spécifiques
        echo
        echo "Entrez les noms d'hôtes (un par ligne, ligne vide pour terminer):"
        hosts=()
        while true; do
            read -p "Hostname (ou vide pour terminer): " host
            [[ -z "$host" ]] && break
            hosts+=("$host")
        done
        
        if [[ ${#hosts[@]} -eq 0 ]]; then
            echo "Aucun serveur spécifié."
            exit 0
        fi
        
        echo
        echo "Installation du certificat CA sur ${#hosts[@]} serveur(s)..."
        echo
        
        for host in "${hosts[@]}"; do
            echo "→ Installation sur ${host}..."
            
            ssh_host "$host" "sudo mkdir -p /etc/rancher/ssl" || {
                echo "  ✗ Échec de connexion à ${host}"
                continue
            }
            
            scp_host rancher-ca.crt "$host:/tmp/rancher-ca.crt" || {
                echo "  ✗ Échec de copie vers ${host}"
                continue
            }
            
            ssh_host "$host" "sudo mv /tmp/rancher-ca.crt /etc/rancher/ssl/cacerts.pem && sudo chmod 644 /etc/rancher/ssl/cacerts.pem" || {
                echo "  ✗ Échec d'installation sur ${host}"
                continue
            }
            
            echo "  ✓ Certificat CA installé sur ${host}"
            
            # Redémarrer l'agent Rancher si présent
            echo "  → Redémarrage de l'agent Rancher (si présent)..."
            ssh_host "$host" "sudo systemctl restart rancher-agent 2>/dev/null || sudo systemctl restart rancher-agent.service 2>/dev/null || echo 'Agent Rancher non trouvé (normal si pas encore installé)'" || true
        done
        
        echo
        echo "✓ Installation terminée."
        ;;
        
    3)
        ### Copier localement uniquement
        echo
        echo "Le certificat CA est disponible dans: $(pwd)/rancher-ca.crt"
        echo
        echo "Pour l'installer manuellement sur un serveur downstream:"
        echo "  1. Copiez le fichier rancher-ca.crt sur le serveur"
        echo "  2. Exécutez sur le serveur:"
        echo "     sudo mkdir -p /etc/rancher/ssl"
        echo "     sudo cp rancher-ca.crt /etc/rancher/ssl/cacerts.pem"
        echo "     sudo chmod 644 /etc/rancher/ssl/cacerts.pem"
        echo "  3. Redémarrez l'agent Rancher:"
        echo "     sudo systemctl restart rancher-agent"
        echo
        ;;
        
    *)
        echo "Choix invalide"
        exit 1
        ;;
esac

echo
echo "=========================================="
echo "Prochaines étapes:"
echo "=========================================="
echo
echo "1. Vérifiez que les agents downstream peuvent se connecter:"
echo "   - Consultez les logs des agents:"
echo "     sudo journalctl -u rancher-agent -f"
echo
echo "2. Dans l'interface Rancher, vérifiez que les clusters downstream"
echo "   apparaissent et sont en état 'Active'"
echo
echo "3. Si les agents ne se connectent toujours pas:"
echo "   - Vérifiez la connectivité réseau vers ${LB_RANCHER_FQDN}:443"
echo "   - Vérifiez les logs Rancher:"
echo "     kubectl logs -n cattle-system -l app=rancher --tail=50"
echo
echo "=========================================="

