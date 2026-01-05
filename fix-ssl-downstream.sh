#!/bin/bash

### Script pour résoudre les problèmes SSL avec les serveurs downstream Rancher
### Après changement du proxy manager

set -e

source ./01-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh

echo "=========================================="
echo "Diagnostic et correction SSL Rancher"
echo "=========================================="
echo

### 1. Vérifier la configuration actuelle
echo "1. Vérification de la configuration actuelle..."
echo

CURRENT_HOSTNAME=$(helm get values rancher -n cattle-system 2>/dev/null | grep -E "^hostname:" | awk '{print $2}' || echo "non trouvé")
CURRENT_SERVER_URL=$(kubectl get pods -n cattle-system -l app=rancher -o jsonpath='{.items[0].spec.containers[0].env[?(@.name=="CATTLE_SERVER_URL")].value}' 2>/dev/null || echo "non trouvé")

echo "Hostname configuré dans Helm: ${CURRENT_HOSTNAME}"
echo "CATTLE_SERVER_URL: ${CURRENT_SERVER_URL}"
echo

### 2. Vérifier les certificats
echo "2. Vérification des certificats..."
echo

if kubectl get secret tls-rancher-ingress -n cattle-system >/dev/null 2>&1; then
    CERT_SUBJECT=$(kubectl get secret tls-rancher-ingress -n cattle-system -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject 2>/dev/null || echo "Erreur lecture certificat")
    CERT_ISSUER=$(kubectl get secret tls-rancher-ingress -n cattle-system -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -issuer 2>/dev/null || echo "Erreur lecture certificat")
    CERT_DATES=$(kubectl get secret tls-rancher-ingress -n cattle-system -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates 2>/dev/null || echo "Erreur lecture certificat")
    
    echo "Certificat TLS Ingress:"
    echo "  Subject: ${CERT_SUBJECT}"
    echo "  Issuer: ${CERT_ISSUER}"
    echo "  Dates: ${CERT_DATES}"
    echo
fi

### 3. Vérifier l'ingress
echo "3. Vérification de l'ingress..."
echo

kubectl get ingress rancher -n cattle-system -o yaml | grep -A 10 "spec:" || echo "Ingress non trouvé"
echo

### 4. Proposer des solutions
echo "=========================================="
echo "Solutions possibles:"
echo "=========================================="
echo
echo "PROBLÈME IDENTIFIÉ:"
echo "Les serveurs downstream ne peuvent pas s'enregistrer car:"
echo "  1. Le certificat est auto-signé par Rancher (dynamiclistener-ca)"
echo "  2. Le proxy manager intercepte peut-être les connexions SSL"
echo "  3. Incohérence possible entre hostname et CATTLE_SERVER_URL"
echo
echo "SOLUTIONS:"
echo
echo "Solution 1: Configurer Rancher pour utiliser un certificat valide"
echo "  - Utiliser cert-manager avec Let's Encrypt"
echo "  - Ou fournir un certificat personnalisé"
echo
echo "Solution 2: Configurer le proxy manager pour passer les connexions SSL"
echo "  - Désactiver la termination SSL au niveau du proxy"
echo "  - Ou configurer le proxy pour utiliser le certificat de Rancher"
echo
echo "Solution 3: Mettre à jour la configuration Rancher"
echo "  - S'assurer que hostname et CATTLE_SERVER_URL correspondent"
echo "  - Reconfigurer les agents downstream"
echo
echo "=========================================="
echo

### 5. Fonction pour corriger la configuration
FIX_RANCHER_CONFIG() {
    echo "Correction de la configuration Rancher..."
    echo
    
    # S'assurer que hostname et CATTLE_SERVER_URL correspondent
    if [[ "${CURRENT_HOSTNAME}" != "${LB_RANCHER_FQDN}" ]]; then
        echo "Mise à jour du hostname dans Helm..."
        helm upgrade rancher rancher-prime/rancher \
            --namespace cattle-system \
            --reuse-values \
            --set hostname=${LB_RANCHER_FQDN}
    fi
    
    # Vérifier que CATTLE_SERVER_URL correspond
    EXPECTED_URL="https://${LB_RANCHER_FQDN}"
    if [[ "${CURRENT_SERVER_URL}" != "${EXPECTED_URL}" ]]; then
        echo "ATTENTION: CATTLE_SERVER_URL (${CURRENT_SERVER_URL}) ne correspond pas au hostname (${LB_RANCHER_FQDN})"
        echo "Vous devrez peut-être mettre à jour manuellement via l'interface Rancher:"
        echo "  Settings -> Server URL -> ${EXPECTED_URL}"
    fi
    
    echo "Configuration mise à jour."
    echo
}

### 6. Fonction pour configurer un certificat valide
FIX_CERTIFICATE() {
    echo "Configuration d'un certificat valide..."
    echo
    
    if [[ "${TLS_SOURCE}" == "rancher" ]]; then
        echo "Le certificat est actuellement généré par cert-manager (auto-signé)."
        echo
        echo "Pour utiliser un certificat valide, vous pouvez:"
        echo "  1. Configurer Let's Encrypt via cert-manager"
        echo "  2. Fournir un certificat personnalisé (tls.crt et tls.key)"
        echo
        echo "Option 1: Let's Encrypt (nécessite un domaine public)"
        echo "  - Créer un ClusterIssuer Let's Encrypt"
        echo "  - Mettre à jour l'ingress pour utiliser cet issuer"
        echo
        echo "Option 2: Certificat personnalisé"
        echo "  - Placer tls.crt et tls.key dans le répertoire courant"
        echo "  - Exécuter: kubectl -n cattle-system create secret tls tls-rancher-ingress --cert=tls.crt --key=tls.key --dry-run=client -o yaml | kubectl apply -f -"
        echo "  - Mettre à jour l'ingress pour utiliser ce secret"
        echo
    fi
}

### 7. Fonction pour vérifier la connectivité
TEST_CONNECTIVITY() {
    echo "Test de connectivité..."
    echo
    
    echo "Test 1: Connexion HTTPS directe"
    if curl -k -s -o /dev/null -w "%{http_code}" https://${LB_RANCHER_FQDN}/ping | grep -q "200"; then
        echo "  ✓ Connexion HTTPS réussie"
    else
        echo "  ✗ Échec de la connexion HTTPS"
    fi
    
    echo "Test 2: Vérification du certificat"
    CERT_CHECK=$(echo | openssl s_client -connect ${LB_RANCHER_FQDN}:443 -servername ${LB_RANCHER_FQDN} 2>/dev/null | openssl x509 -noout -subject -issuer 2>/dev/null || echo "Erreur")
    if [[ "${CERT_CHECK}" != "Erreur" ]]; then
        echo "  Certificat présenté:"
        echo "    ${CERT_CHECK}"
    else
        echo "  ✗ Impossible de récupérer le certificat"
    fi
    
    echo
}

### Menu principal
echo "Que souhaitez-vous faire ?"
echo "  1) Afficher le diagnostic uniquement"
echo "  2) Corriger la configuration Rancher (hostname/CATTLE_SERVER_URL)"
echo "  3) Afficher les instructions pour configurer un certificat valide"
echo "  4) Tester la connectivité"
echo "  5) Tout faire (diagnostic + correction + tests)"
echo
read -p "Choix [1-5]: " choice

case $choice in
    1)
        echo "Diagnostic terminé."
        ;;
    2)
        FIX_RANCHER_CONFIG
        ;;
    3)
        FIX_CERTIFICATE
        ;;
    4)
        TEST_CONNECTIVITY
        ;;
    5)
        FIX_RANCHER_CONFIG
        FIX_CERTIFICATE
        TEST_CONNECTIVITY
        ;;
    *)
        echo "Choix invalide"
        exit 1
        ;;
esac

echo
echo "=========================================="
echo "Pour résoudre définitivement le problème SSL:"
echo "=========================================="
echo
echo "1. Si vous utilisez un proxy manager externe:"
echo "   - Configurez-le pour passer les connexions SSL telles quelles"
echo "   - Ou configurez-le pour utiliser le certificat de Rancher"
echo "   - Assurez-vous que le proxy ne termine pas SSL si Rancher le fait déjà"
echo
echo "2. Si vous voulez un certificat valide:"
echo "   - Configurez cert-manager avec Let's Encrypt (domaine public requis)"
echo "   - Ou fournissez un certificat personnalisé"
echo
echo "3. Après correction, redémarrez les agents downstream:"
echo "   - Les agents devraient automatiquement se reconnecter"
echo "   - Sinon, réinstallez les agents sur les serveurs downstream"
echo
echo "=========================================="

