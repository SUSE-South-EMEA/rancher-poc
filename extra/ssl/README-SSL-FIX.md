# Résolution des problèmes SSL avec les serveurs downstream Rancher

## Problème

Après avoir changé le proxy manager et fait des modifications sur l'interface Rancher, les serveurs downstream ne peuvent plus s'enregistrer à cause d'une erreur SSL.

## Causes possibles

1. **Certificat auto-signé non reconnu**: Rancher utilise un certificat auto-signé généré par cert-manager, et les agents downstream ne peuvent pas le valider.

2. **Proxy manager intercepte SSL**: Le proxy manager peut intercepter les connexions SSL et utiliser son propre certificat, ce qui cause des problèmes de validation.

3. **Incohérence de configuration**: Le hostname configuré dans Helm peut ne pas correspondre au CATTLE_SERVER_URL.

## Solutions

### Solution 1: Utiliser un certificat personnalisé (Recommandé)

1. Préparez vos fichiers de certificat (`tls.crt` et `tls.key`) dans le répertoire `rancher-poc/`.

2. Exécutez le script de correction:
   ```bash
   cd /root/rancher-poc
   ./fix-ssl-certificate.sh
   ```
   Choisissez l'option 1 pour utiliser un certificat personnalisé.

3. Vérifiez la configuration:
   ```bash
   kubectl get secret tls-rancher-ingress -n cattle-system
   kubectl describe ingress rancher -n cattle-system
   ```

### Solution 2: Configurer Let's Encrypt (Pour domaines publics)

1. Assurez-vous que cert-manager est installé:
   ```bash
   kubectl get namespace cert-manager
   ```

2. Exécutez le script:
   ```bash
   cd /root/rancher-poc
   ./fix-ssl-certificate.sh
   ```
   Choisissez l'option 2 pour configurer Let's Encrypt.

3. Le certificat sera généré automatiquement par cert-manager (peut prendre quelques minutes).

### Solution 3: Accepter les certificats auto-signés (Temporaire)

Si vous devez utiliser les certificats auto-signés de Rancher:

1. Exécutez le script:
   ```bash
   cd /root/rancher-poc
   ./fix-ssl-certificate.sh
   ```
   Choisissez l'option 3.

2. Téléchargez le certificat CA de Rancher:
   ```bash
   kubectl get secret tls-rancher -n cattle-system -o jsonpath='{.data.ca\.crt}' | base64 -d > rancher-ca.crt
   ```

3. Sur chaque serveur downstream, copiez le certificat CA:
   ```bash
   sudo mkdir -p /etc/rancher/ssl
   sudo cp rancher-ca.crt /etc/rancher/ssl/cacerts.pem
   ```

4. Redémarrez les agents Rancher sur les serveurs downstream.

### Solution 4: Configuration du proxy manager

Si vous utilisez un proxy manager externe (comme Nginx Proxy Manager):

1. **Option A - Passer les connexions SSL telles quelles**:
   - Configurez le proxy pour ne pas terminer SSL
   - Laissez Rancher gérer SSL directement
   - Le proxy fait juste du forwarding TCP

2. **Option B - Utiliser le certificat de Rancher**:
   - Exportez le certificat de Rancher
   - Configurez le proxy manager pour utiliser ce certificat
   - Assurez-vous que le proxy termine SSL correctement

3. **Option C - Désactiver SSL au niveau de Rancher**:
   - Configurez Rancher avec `--set tls=external`
   - Laissez le proxy manager gérer SSL complètement

## Diagnostic

Pour diagnostiquer le problème:

```bash
cd /root/rancher-poc
./fix-ssl-downstream.sh
```

Ce script affichera:
- La configuration actuelle de Rancher
- Les certificats utilisés
- Les problèmes identifiés
- Des suggestions de correction

## Vérification

Après avoir appliqué une solution, vérifiez:

1. **Connectivité HTTPS**:
   ```bash
   curl -k https://rancher.home.lo/ping
   ```

2. **Certificat présenté**:
   ```bash
   echo | openssl s_client -connect rancher.home.lo:443 -servername rancher.home.lo 2>/dev/null | openssl x509 -noout -subject -issuer
   ```

3. **Statut des certificats cert-manager**:
   ```bash
   kubectl get certificate -n cattle-system
   kubectl describe certificate -n cattle-system
   ```

4. **Logs Rancher**:
   ```bash
   kubectl logs -n cattle-system -l app=rancher --tail=50 | grep -i "ssl\|tls\|cert\|downstream"
   ```

## Redémarrage des agents downstream

Après avoir corrigé le problème SSL, les agents downstream devraient automatiquement se reconnecter. Si ce n'est pas le cas:

1. Vérifiez les logs des agents sur les serveurs downstream
2. Redémarrez les agents si nécessaire
3. Réinstallez les agents si le problème persiste

## Notes importantes

- **Sécurité**: Les certificats auto-signés sont moins sécurisés. Utilisez des certificats valides en production.
- **Proxy manager**: Si vous utilisez un proxy manager, assurez-vous qu'il ne crée pas de conflit avec la gestion SSL de Rancher.
- **CATTLE_SERVER_URL**: Assurez-vous que cette variable correspond au hostname configuré dans Helm.
- **DNS**: Vérifiez que le DNS est correctement configuré pour résoudre le FQDN de Rancher.

## Support

Pour plus d'informations, consultez:
- [Documentation Rancher - SSL/TLS](https://rancher.com/docs/rancher/v2.6/en/installation/resources/tls-secrets/)
- [Documentation cert-manager](https://cert-manager.io/docs/)

