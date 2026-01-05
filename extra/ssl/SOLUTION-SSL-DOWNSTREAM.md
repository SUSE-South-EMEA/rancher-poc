# Solution pour résoudre les problèmes SSL avec les serveurs downstream

## Problème résolu

Après avoir changé le proxy manager, les serveurs downstream ne peuvent plus s'enregistrer à cause d'une erreur SSL.

## Diagnostic effectué

1. ✅ Certificat personnalisé créé (`tls.crt` et `tls.key`)
2. ✅ Secret TLS mis à jour dans Kubernetes
3. ✅ Cert-manager désactivé pour éviter la régénération automatique
4. ⚠️ Rancher utilise son propre mécanisme (dynamiclistener) qui génère des certificats auto-signés

## Solution appliquée (Option 1 - Certificat personnalisé)

### Ce qui a été fait

1. **Certificat créé** : Un certificat auto-signé a été créé pour les domaines Rancher :
   - `rancher.home.lo`
   - `rancher.home.zypp.fr`
   - `ranchvip.home.lo`
   - IPs: 172.16.3.22, 172.16.3.20

2. **Secret Kubernetes mis à jour** : Le secret `tls-rancher-ingress` contient maintenant le certificat personnalisé

3. **Cert-manager désactivé** : Le certificate resource a été supprimé pour éviter la régénération

### Fichiers créés

- `/root/rancher-poc/tls.crt` - Certificat
- `/root/rancher-poc/tls.key` - Clé privée
- `/root/rancher-poc/fix-ssl-downstream.sh` - Script de diagnostic
- `/root/rancher-poc/fix-ssl-certificate.sh` - Script de configuration
- `/root/rancher-poc/install-ca-downstream.sh` - Script d'installation du CA sur les downstream

## Problème restant

Rancher utilise son propre mécanisme de gestion SSL (dynamiclistener) qui génère des certificats auto-signés. Même si l'ingress utilise notre certificat, Rancher présente toujours son certificat auto-signé aux agents downstream.

## Solutions pour les serveurs downstream

### Solution A : Installer le certificat CA de Rancher sur les serveurs downstream

1. **Télécharger le certificat CA depuis l'interface Rancher** :
   - Connectez-vous à l'interface Rancher
   - Allez dans **Settings** → **Certificates**
   - Téléchargez le certificat CA

2. **Ou depuis la ligne de commande** :
   ```bash
   # Le certificat CA est généré par Rancher et peut être récupéré via l'API
   # ou depuis l'interface web Rancher
   ```

3. **Installer sur chaque serveur downstream** :
   ```bash
   sudo mkdir -p /etc/rancher/ssl
   sudo cp rancher-ca.crt /etc/rancher/ssl/cacerts.pem
   sudo chmod 644 /etc/rancher/ssl/cacerts.pem
   ```

4. **Redémarrer l'agent Rancher** :
   ```bash
   sudo systemctl restart rancher-agent
   ```

### Solution B : Utiliser le script d'installation automatique

```bash
cd /root/rancher-poc
./install-ca-downstream.sh
```

Ce script vous permettra de :
- Télécharger automatiquement le certificat CA
- L'installer sur tous les serveurs downstream listés dans `hosts.list`
- Redémarrer les agents Rancher

### Solution C : Configurer le proxy manager

Si vous utilisez un proxy manager externe (comme Nginx Proxy Manager) :

1. **Option 1 - Passer SSL tel quel** :
   - Configurez le proxy pour faire du forwarding TCP (pas de termination SSL)
   - Laissez Rancher gérer SSL directement

2. **Option 2 - Utiliser le certificat de Rancher** :
   - Exportez le certificat depuis Rancher
   - Configurez le proxy manager pour utiliser ce certificat
   - Assurez-vous que le proxy termine SSL correctement

3. **Option 3 - Désactiver SSL au niveau de Rancher** :
   ```bash
   helm upgrade rancher rancher-prime/rancher \
     --namespace cattle-system \
     --reuse-values \
     --set tls=external
   ```
   Puis configurez le proxy manager pour gérer SSL complètement.

## Vérification

### Vérifier la connectivité

```bash
# Test de connexion HTTPS
curl -k https://rancher.home.lo/ping

# Vérifier le certificat présenté
echo | openssl s_client -connect rancher.home.lo:443 -servername rancher.home.lo 2>/dev/null | openssl x509 -noout -subject -issuer
```

### Vérifier les logs Rancher

```bash
kubectl logs -n cattle-system -l app=rancher --tail=50 | grep -i "downstream\|ssl\|tls"
```

### Vérifier les agents downstream

Sur chaque serveur downstream :
```bash
sudo journalctl -u rancher-agent -f
```

## Recommandations

1. **Pour la production** : Utilisez un certificat valide (Let's Encrypt ou certificat d'une autorité de certification reconnue)

2. **Pour le développement/test** : Utilisez la solution A ou B pour installer le CA sur les serveurs downstream

3. **Si vous utilisez un proxy manager** : Assurez-vous qu'il ne crée pas de conflit avec la gestion SSL de Rancher

## Prochaines étapes

1. ✅ Certificat personnalisé créé et configuré
2. ⏳ Installer le certificat CA sur les serveurs downstream (Solution A ou B)
3. ⏳ Vérifier que les agents downstream peuvent se connecter
4. ⏳ Vérifier dans l'interface Rancher que les clusters downstream apparaissent

## Support

Si le problème persiste après avoir installé le certificat CA sur les serveurs downstream :

1. Vérifiez la connectivité réseau entre les downstream et Rancher
2. Vérifiez les logs des agents downstream
3. Vérifiez les logs Rancher pour les erreurs de connexion
4. Consultez la documentation Rancher : https://rancher.com/docs/rancher/v2.6/en/installation/resources/tls-secrets/

