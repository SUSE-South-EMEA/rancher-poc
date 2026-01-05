# Instructions d'installation du certificat CA Rancher

## ✅ Ce qui a été fait

1. **Certificat CA récupéré** : `rancher-ca.crt` (912 bytes)
   - Certificat CA de Rancher (dynamiclistener-ca)
   - Valide jusqu'au 2 avril 2026

2. **Scripts créés** :
   - `get-rancher-ca.sh` - Récupère le certificat CA depuis Rancher
   - `install-ca-auto.sh` - Installation automatique sur plusieurs serveurs
   - `install-ca-downstream.sh` - Installation interactive

## 🚀 Installation sur les serveurs downstream

### Option 1 : Script automatique (Recommandé)

```bash
cd /root/rancher-poc
./install-ca-auto.sh
```

Le script va :
1. Vérifier que le certificat CA existe
2. Vous demander les noms des serveurs downstream
3. Installer le certificat sur chaque serveur
4. Redémarrer les agents Rancher

### Option 2 : Installation manuelle

Sur **chaque serveur downstream**, exécutez :

```bash
# 1. Créer le répertoire
sudo mkdir -p /etc/rancher/ssl

# 2. Copier le certificat CA
sudo scp rancher@rancher-manager-0.home.lo:/root/rancher-poc/rancher-ca.crt /etc/rancher/ssl/cacerts.pem

# 3. Définir les permissions
sudo chmod 644 /etc/rancher/ssl/cacerts.pem

# 4. Redémarrer l'agent Rancher
sudo systemctl restart rancher-agent
```

### Option 3 : Via le script interactif

```bash
cd /root/rancher-poc
./install-ca-downstream.sh
```

Choisissez l'option 2 pour spécifier manuellement les serveurs.

## 📋 Liste des serveurs downstream

Pour identifier vos serveurs downstream, vous pouvez :

1. **Vérifier dans l'interface Rancher** :
   - Connectez-vous à https://rancher.home.lo
   - Allez dans **Cluster Management**
   - Les clusters downstream listent leurs nœuds

2. **Via kubectl** :
   ```bash
   kubectl get nodes
   ```

3. **Vérifier les agents Rancher** :
   ```bash
   # Sur chaque serveur, vérifier si l'agent est installé
   sudo systemctl status rancher-agent
   ```

## ✅ Vérification après installation

### 1. Vérifier que le certificat est installé

Sur chaque serveur downstream :
```bash
sudo ls -lh /etc/rancher/ssl/cacerts.pem
sudo openssl x509 -in /etc/rancher/ssl/cacerts.pem -noout -subject -issuer -dates
```

### 2. Vérifier les logs de l'agent

```bash
sudo journalctl -u rancher-agent -f
```

Vous devriez voir des messages de connexion réussie au serveur Rancher.

### 3. Vérifier dans l'interface Rancher

1. Connectez-vous à https://rancher.home.lo
2. Allez dans **Cluster Management**
3. Les clusters downstream devraient apparaître en état **Active**
4. Les nœuds devraient être visibles et en état **Ready**

## 🔧 Dépannage

### Si l'agent ne se connecte toujours pas

1. **Vérifier la connectivité réseau** :
   ```bash
   curl -k https://rancher.home.lo/ping
   ```

2. **Vérifier les logs détaillés** :
   ```bash
   sudo journalctl -u rancher-agent -n 100 --no-pager
   ```

3. **Vérifier que le certificat CA est correct** :
   ```bash
   # Sur le serveur downstream
   sudo openssl x509 -in /etc/rancher/ssl/cacerts.pem -noout -text | head -20
   ```

4. **Vérifier les logs Rancher** :
   ```bash
   kubectl logs -n cattle-system -l app=rancher --tail=50 | grep -i "downstream\|ssl\|tls"
   ```

### Si vous obtenez des erreurs SSL

1. Vérifiez que le certificat CA correspond à celui présenté par Rancher :
   ```bash
   # Sur le serveur manager
   echo | openssl s_client -connect rancher.home.lo:443 -servername rancher.home.lo 2>/dev/null | openssl x509 -noout -issuer
   
   # Sur le serveur downstream
   sudo openssl x509 -in /etc/rancher/ssl/cacerts.pem -noout -subject
   ```

2. Les deux doivent correspondre (même issuer).

## 📝 Notes importantes

- Le certificat CA doit être installé sur **tous les nœuds** des clusters downstream
- Après installation, les agents Rancher devraient automatiquement se reconnecter
- Si vous ajoutez de nouveaux nœuds, n'oubliez pas d'y installer le certificat CA
- Le certificat CA est valide jusqu'au 2 avril 2026

## 🆘 Support

Si le problème persiste après avoir installé le certificat CA :

1. Consultez `/root/rancher-poc/SOLUTION-SSL-DOWNSTREAM.md`
2. Vérifiez la documentation Rancher : https://rancher.com/docs/rancher/v2.6/en/installation/resources/tls-secrets/
3. Vérifiez les logs des agents et de Rancher pour identifier l'erreur exacte

