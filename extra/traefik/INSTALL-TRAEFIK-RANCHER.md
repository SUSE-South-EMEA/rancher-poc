# Configuration Traefik pour Rancher

Ce guide explique comment configurer Traefik sur rasp01 pour router les requêtes vers Rancher.

## Objectifs

- **Accès utilisateur**: `https://rancher.home.zypp.fr` → `http://rancher.home.lo:80`
- **Agents downstream**: `https://rancher.home.lo` → `http://rancher.home.lo:80`

## Prérequis

1. Traefik installé et fonctionnel sur rasp01
2. Accès SSH à rasp01 avec l'utilisateur `ju` (ju@rasp01)
3. DNS configuré:
   - `rancher.home.zypp.fr` → IP de rasp01
   - `rancher.home.lo` → IP de rasp01
4. Rancher déployé et accessible sur `rancher.home.lo:80`

## Méthodes de configuration

### Méthode 1: Docker Compose (recommandé si Traefik est en Docker)

1. Copiez le fichier `traefik-rancher-docker-compose.yml` sur rasp01
2. Modifiez les labels selon votre configuration
3. Redémarrez le conteneur Traefik

```bash
# Depuis votre machine
scp traefik-rancher-docker-compose.yml ju@rasp01:~/
ssh ju@rasp01 "docker-compose -f traefik-rancher-docker-compose.yml up -d"
```

### Méthode 2: Fichier de configuration dynamique (recommandé)

1. Copiez `traefik-rancher-config.yaml` vers `/etc/traefik/dynamic/rancher.yaml` sur rasp01:
   ```bash
   scp traefik-rancher-config.yaml ju@rasp01:/tmp/
   ssh ju@rasp01 "sudo mkdir -p /etc/traefik/dynamic && sudo cp /tmp/traefik-rancher-config.yaml /etc/traefik/dynamic/rancher.yaml && sudo systemctl restart traefik"
   ```
2. Assurez-vous que Traefik charge les fichiers dynamiques:
   ```yaml
   providers:
     file:
       directory: /etc/traefik/dynamic
       watch: true
   ```
3. Redémarrez Traefik

### Méthode 3: Kubernetes IngressRoute (si Traefik est dans Kubernetes)

1. Appliquez la configuration:
   ```bash
   kubectl apply -f traefik-rancher-kubernetes.yaml
   ```

### Méthode 4: Labels Docker (si Traefik surveille les conteneurs Docker)

Ajoutez ces labels à votre conteneur Traefik ou créez un conteneur proxy:

```yaml
labels:
  - "traefik.http.routers.rancher-zypp.rule=Host(`rancher.home.zypp.fr`)"
  - "traefik.http.routers.rancher-zypp.entrypoints=websecure"
  - "traefik.http.routers.rancher-zypp.tls.certresolver=letsencrypt"
  - "traefik.http.services.rancher-zypp.loadbalancer.server.url=http://rancher.home.lo:80"
  - "traefik.http.services.rancher-zypp.loadbalancer.passhostheader=true"
  
  - "traefik.http.routers.rancher-lo.rule=Host(`rancher.home.lo`)"
  - "traefik.http.routers.rancher-lo.entrypoints=websecure"
  - "traefik.http.routers.rancher-lo.tls.certresolver=letsencrypt"
  - "traefik.http.services.rancher-lo.loadbalancer.server.url=http://rancher.home.lo:80"
  - "traefik.http.services.rancher-lo.loadbalancer.passhostheader=true"
```

## Configuration du certificat TLS

### Option 1: Let's Encrypt (automatique)

Assurez-vous que Traefik a un certificate resolver configuré:

```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      email: your-email@example.com
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
```

### Option 2: Certificat statique

Si vous avez un certificat statique, créez un secret TLS et référencez-le:

```yaml
tls:
  secretName: rancher-tls
```

## Vérification

1. **Test de connectivité**:
   ```bash
   curl -k https://rancher.home.zypp.fr/ping
   curl -k https://rancher.home.lo/ping
   ```

2. **Vérification des logs Traefik**:
   ```bash
   ssh ju@rasp01 "docker logs traefik"
   # ou
   ssh ju@rasp01 "journalctl -u traefik -f"
   ```

3. **Interface web Traefik** (si activée):
   - Accédez à `http://rasp01:8080` (ou le port configuré)
   - Vérifiez que les routes apparaissent

## Dépannage

### Problème: Certificat non généré

- Vérifiez que le port 80 est accessible depuis l'extérieur (pour le challenge HTTP)
- Vérifiez les logs Traefik pour les erreurs ACME
- Vérifiez que l'email est correct dans la configuration

### Problème: 502 Bad Gateway

- Vérifiez que Rancher est accessible sur `rancher.home.lo:80`
- Vérifiez la connectivité réseau entre rasp01 et rancher.home.lo
- Vérifiez les logs Traefik

### Problème: Host header incorrect

- Assurez-vous que `passHostHeader: true` est configuré
- Vérifiez que Rancher accepte les requêtes avec le bon Host header

## Notes importantes

1. **PassHostHeader**: Essentiel pour que Rancher reçoive le bon Host header
2. **Health check**: Le endpoint `/ping` est utilisé pour vérifier que Rancher répond
3. **Timeouts**: Rancher peut être lent, ajustez les timeouts si nécessaire
4. **DNS**: Les deux FQDN doivent pointer vers rasp01

## Fichiers fournis

- `traefik-rancher-config.yaml`: Configuration YAML pour provider file
- `traefik-rancher-docker-compose.yml`: Docker Compose avec labels
- `traefik-rancher-kubernetes.yaml`: IngressRoute pour Kubernetes
- `traefik-rancher-static.yml`: Configuration statique complète

