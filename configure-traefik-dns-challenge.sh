#!/bin/bash
# Script pour configurer Traefik avec un challenge DNS pour Let's Encrypt
# Usage: ./configure-traefik-dns-challenge.sh <provider> <email> [api_key] [api_secret]

set -e

PROVIDER="${1:-cloudflare}"
EMAIL="${2:-your-email@example.com}"
API_KEY="${3:-}"
API_SECRET="${4:-}"

TRAEFIK_USER="ju"
TRAEFIK_HOST="rasp01"
TRAEFIK_DIR="/home/ju/docker-compose/traefik"

echo "🔧 Configuration du challenge DNS pour Traefik"
echo "Provider: $PROVIDER"
echo "Email: $EMAIL"
echo

# Liste des providers supportés
case "$PROVIDER" in
  cloudflare)
    ENV_VARS="CF_API_EMAIL=${EMAIL}
CF_DNS_API_TOKEN=${API_KEY}"
    ;;
  route53)
    ENV_VARS="AWS_ACCESS_KEY_ID=${API_KEY}
AWS_SECRET_ACCESS_KEY=${API_SECRET}
AWS_REGION=${AWS_REGION:-us-east-1}"
    ;;
  digitalocean)
    ENV_VARS="DO_AUTH_TOKEN=${API_KEY}"
    ;;
  ovh)
    ENV_VARS="OVH_ENDPOINT=${OVH_ENDPOINT:-ovh-eu}
OVH_APPLICATION_KEY=${API_KEY}
OVH_APPLICATION_SECRET=${API_SECRET}
OVH_CONSUMER_KEY=${OVH_CONSUMER_KEY:-}"
    ;;
  gandiv5)
    ENV_VARS="GANDIV5_API_KEY=${API_KEY}"
    ;;
  *)
    echo "❌ Provider non supporté: $PROVIDER"
    echo "Providers supportés: cloudflare, route53, digitalocean, ovh, gandiv5"
    exit 1
    ;;
esac

# Créer la configuration traefik.yml avec dnschallenge
cat > /tmp/traefik-dns.yml << EOF
api:
  dashboard: true
  insecure: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      # Challenge DNS
      dnschallenge:
        provider: ${PROVIDER}
        delayBeforeCheck: 30
        resolvers:
          - "1.1.1.1:53"
          - "8.8.8.8:53"
      email: ${EMAIL}
      storage: /letsencrypt/acme.json
      # Pour utiliser le serveur de staging (pour tests)
      # caServer: https://acme-staging-v02.api.letsencrypt.org/directory

# Utiliser les certificats existants de nginx-proxy-manager
tls:
  stores:
    default:
      defaultCertificate:
        certFile: /letsencrypt/live/npm-1/fullchain.pem
        keyFile: /letsencrypt/live/npm-1/privkey.pem

providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true
  docker:
    exposedByDefault: false

log:
  level: INFO

accessLog: {}
EOF

echo "📝 Configuration Traefik créée"
echo

# Copier la configuration
scp /tmp/traefik-dns.yml ${TRAEFIK_USER}@${TRAEFIK_HOST}:/tmp/traefik.yml

# Mettre à jour docker-compose.yml avec les variables d'environnement
echo "📝 Mise à jour du docker-compose.yml..."
ssh ${TRAEFIK_USER}@${TRAEFIK_HOST} << EOF
cd ${TRAEFIK_DIR}

# Sauvegarder l'ancienne config
cp docker-compose-traefik.yml docker-compose-traefik.yml.backup.\$(date +%Y%m%d_%H%M%S)

# Ajouter les variables d'environnement
cat > /tmp/docker-compose-update.sh << 'SCRIPT'
#!/bin/bash
# Mettre à jour docker-compose.yml avec les variables d'environnement DNS

COMPOSE_FILE="docker-compose-traefik.yml"

# Vérifier si les variables sont déjà présentes
if grep -q "CF_API_EMAIL\|AWS_ACCESS_KEY_ID\|DO_AUTH_TOKEN" "\$COMPOSE_FILE" 2>/dev/null; then
  echo "⚠️  Des variables DNS sont déjà présentes dans \$COMPOSE_FILE"
  echo "Veuillez les mettre à jour manuellement."
  exit 1
fi

# Ajouter les variables dans la section environment
# Note: Cette approche simple fonctionne si environment: est déjà présent
# Sinon, il faudra modifier manuellement
echo "⚠️  Veuillez ajouter manuellement les variables suivantes dans la section 'environment:' de \$COMPOSE_FILE:"
echo ""
echo "${ENV_VARS}"
echo ""
echo "Exemple:"
echo "    environment:"
echo "      - TZ=Europe/Paris"
echo "      - CF_API_EMAIL=${EMAIL}"
echo "      - CF_DNS_API_TOKEN=\${CF_DNS_API_TOKEN}"
SCRIPT

chmod +x /tmp/docker-compose-update.sh
/tmp/docker-compose-update.sh
EOF

# Copier traefik.yml
ssh ${TRAEFIK_USER}@${TRAEFIK_HOST} "cp /tmp/traefik.yml ${TRAEFIK_DIR}/traefik.yml"

echo
echo "✅ Configuration DNS challenge appliquée"
echo
echo "📋 PROCHAINES ÉTAPES:"
echo
echo "1. Ajoutez les variables d'environnement dans ${TRAEFIK_DIR}/docker-compose-traefik.yml:"
echo "   ${ENV_VARS}"
echo
echo "2. Redémarrez Traefik:"
echo "   ssh ${TRAEFIK_USER}@${TRAEFIK_HOST} 'cd ${TRAEFIK_DIR} && docker-compose restart traefik'"
echo
echo "3. Vérifiez les logs:"
echo "   ssh ${TRAEFIK_USER}@${TRAEFIK_HOST} 'docker logs traefik --tail 50'"
echo
echo "⚠️  NOTE: rancher.home.lo utilise maintenant le certificat par défaut"
echo "   (car .lo ne peut pas être validé par Let's Encrypt)"
echo

