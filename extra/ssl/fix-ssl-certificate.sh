#!/bin/bash

### Script pour configurer un certificat SSL valide pour Rancher
### Résout les problèmes d'enregistrement des serveurs downstream

set -e

source ./01-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh

echo "=========================================="
echo "Configuration certificat SSL Rancher"
echo "=========================================="
echo

### Vérifier les prérequis
if ! kubectl get namespace cattle-system >/dev/null 2>&1; then
    echo "ERREUR: Le namespace cattle-system n'existe pas."
    echo "Rancher n'est peut-être pas installé."
    exit 1
fi

### Menu de configuration
echo "Choisissez une méthode pour configurer le certificat SSL:"
echo
echo "  1) Utiliser un certificat personnalisé (tls.crt et tls.key)"
echo "  2) Configurer Let's Encrypt via cert-manager (nécessite un domaine public)"
echo "  3) Configurer l'ingress pour accepter les certificats auto-signés (solution temporaire)"
echo "  4) Afficher la configuration actuelle"
echo
read -p "Choix [1-4]: " choice

case $choice in
    1)
        ### Option 1: Certificat personnalisé
        echo
        echo "Configuration avec certificat personnalisé..."
        echo
        
        if [[ ! -f tls.crt ]] || [[ ! -f tls.key ]]; then
            echo "ERREUR: Les fichiers tls.crt et tls.key doivent être présents dans le répertoire courant."
            echo
            echo "Pour créer un certificat auto-signé (à des fins de test uniquement):"
            echo "  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \\"
            echo "    -keyout tls.key -out tls.crt \\"
            echo "    -subj \"/CN=${LB_RANCHER_FQDN}/O=Rancher\" \\"
            echo "    -addext \"subjectAltName=DNS:${LB_RANCHER_FQDN},DNS:${LB2_RANCHER_FQDN}\""
            exit 1
        fi
        
        echo "Création du secret TLS..."
        kubectl -n cattle-system create secret tls tls-rancher-ingress \
            --cert=tls.crt \
            --key=tls.key \
            --dry-run=client -o yaml | kubectl apply -f -
        
        echo "Mise à jour de l'ingress pour utiliser le certificat..."
        kubectl patch ingress rancher -n cattle-system --type=json -p='
        [
            {
                "op": "replace",
                "path": "/spec/tls/0/secretName",
                "value": "tls-rancher-ingress"
            }
        ]' || echo "L'ingress utilise déjà ce secret."
        
        echo
        echo "✓ Certificat personnalisé configuré."
        echo "  Le secret tls-rancher-ingress a été créé/mis à jour."
        echo
        ;;
        
    2)
        ### Option 2: Let's Encrypt
        echo
        echo "Configuration Let's Encrypt via cert-manager..."
        echo
        
        if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
            echo "ERREUR: cert-manager n'est pas installé."
            echo "Installez cert-manager d'abord avec le script 03-rancher_install.sh"
            exit 1
        fi
        
        echo "ATTENTION: Let's Encrypt nécessite:"
        echo "  - Un domaine public accessible depuis Internet"
        echo "  - Un accès HTTP/HTTPS depuis Internet vers votre serveur"
        echo "  - Une adresse IP publique ou un DNS configuré"
        echo
        read -p "Continuer ? (y/n): " confirm
        if [[ "${confirm}" != "y" ]]; then
            echo "Annulé."
            exit 0
        fi
        
        echo
        echo "Création d'un ClusterIssuer Let's Encrypt..."
        echo
        
        read -p "Email pour Let's Encrypt: " email
        
        cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${email}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
        
        echo
        echo "Mise à jour de l'ingress pour utiliser Let's Encrypt..."
        kubectl annotate ingress rancher -n cattle-system \
            cert-manager.io/issuer=letsencrypt-prod \
            cert-manager.io/issuer-kind=ClusterIssuer \
            --overwrite
        
        echo
        echo "✓ Configuration Let's Encrypt appliquée."
        echo "  Le certificat sera généré automatiquement par cert-manager."
        echo "  Cela peut prendre quelques minutes."
        echo
        echo "Pour vérifier le statut:"
        echo "  kubectl get certificate -n cattle-system"
        echo "  kubectl describe certificate -n cattle-system"
        echo
        ;;
        
    3)
        ### Option 3: Configuration pour accepter les certificats auto-signés
        echo
        echo "Configuration pour accepter les certificats auto-signés..."
        echo "ATTENTION: Cette solution est temporaire et moins sécurisée."
        echo
        
        echo "Cette option configure l'ingress pour utiliser le certificat auto-signé de Rancher."
        echo "Les agents downstream devront accepter les certificats auto-signés."
        echo
        read -p "Continuer ? (y/n): " confirm
        if [[ "${confirm}" != "y" ]]; then
            echo "Annulé."
            exit 0
        fi
        
        echo
        echo "Vérification que le certificat auto-signé existe..."
        if kubectl get secret tls-rancher-ingress -n cattle-system >/dev/null 2>&1; then
            echo "✓ Le secret tls-rancher-ingress existe déjà."
        else
            echo "Le secret n'existe pas. Rancher devrait le créer automatiquement."
            echo "Attendez quelques instants et réessayez."
            exit 1
        fi
        
        echo
        echo "Configuration de l'ingress..."
        kubectl patch ingress rancher -n cattle-system --type=json -p='
        [
            {
                "op": "replace",
                "path": "/spec/tls/0/secretName",
                "value": "tls-rancher-ingress"
            }
        ]' || echo "L'ingress est déjà configuré."
        
        echo
        echo "✓ Configuration appliquée."
        echo
        echo "IMPORTANT: Pour que les agents downstream acceptent le certificat auto-signé:"
        echo "  1. Téléchargez le certificat CA de Rancher:"
        echo "     kubectl get secret tls-rancher -n cattle-system -o jsonpath='{.data.ca\.crt}' | base64 -d > rancher-ca.crt"
        echo
        echo "  2. Sur chaque serveur downstream, copiez le certificat CA:"
        echo "     sudo mkdir -p /etc/rancher/ssl"
        echo "     sudo cp rancher-ca.crt /etc/rancher/ssl/cacerts.pem"
        echo
        echo "  3. Redémarrez les agents Rancher sur les serveurs downstream"
        echo
        ;;
        
    4)
        ### Option 4: Afficher la configuration actuelle
        echo
        echo "Configuration actuelle:"
        echo
        
        echo "Ingress:"
        kubectl get ingress rancher -n cattle-system -o yaml | grep -A 20 "spec:" || echo "Ingress non trouvé"
        echo
        
        echo "Secrets TLS:"
        kubectl get secret -n cattle-system | grep -E "tls|ca" || echo "Aucun secret TLS trouvé"
        echo
        
        echo "Certificat actuel:"
        if kubectl get secret tls-rancher-ingress -n cattle-system >/dev/null 2>&1; then
            kubectl get secret tls-rancher-ingress -n cattle-system -o jsonpath='{.data.tls\.crt}' | \
                base64 -d | openssl x509 -noout -subject -issuer -dates 2>/dev/null || echo "Erreur lecture certificat"
        else
            echo "Aucun certificat trouvé dans tls-rancher-ingress"
        fi
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
echo "1. Vérifiez que le certificat est correctement configuré:"
echo "   kubectl get certificate -n cattle-system"
echo "   kubectl describe ingress rancher -n cattle-system"
echo
echo "2. Testez la connexion HTTPS:"
echo "   curl -k https://${LB_RANCHER_FQDN}/ping"
echo
echo "3. Si vous utilisez un proxy manager externe:"
echo "   - Assurez-vous qu'il ne termine pas SSL si Rancher le fait déjà"
echo "   - Ou configurez-le pour utiliser le certificat de Rancher"
echo
echo "4. Redémarrez les agents downstream pour qu'ils se reconnectent:"
echo "   - Les agents devraient automatiquement se reconnecter"
echo "   - Sinon, réinstallez les agents sur les serveurs downstream"
echo
echo "=========================================="

