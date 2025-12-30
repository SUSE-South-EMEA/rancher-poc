# Configuration de l'utilisateur SSH

## Vue d'ensemble

Les scripts ont été modifiés pour permettre l'exécution des commandes SSH avec un utilisateur spécifique configuré dans `00-vars.sh`. Cela permet de gérer les déploiements où l'utilisateur SSH n'est pas le même que l'utilisateur actuel.

## Configuration

### Dans `00-vars.sh`

Ajoutez ou modifiez la variable `SSH_USER` :

```bash
######################## SSH CONFIGURATION #######################
## SSH user to use for remote commands
## Leave empty to use current user or user from SSH config
## Example: SSH_USER="admin" or SSH_USER=""
SSH_USER=""
```

### Exemples

1. **Utiliser un utilisateur spécifique** :
   ```bash
   SSH_USER="admin"
   ```
   Toutes les commandes SSH utiliseront `admin@hostname`

2. **Utiliser l'utilisateur actuel** (comportement par défaut) :
   ```bash
   SSH_USER=""
   ```
   Les commandes SSH utiliseront l'utilisateur actuel ou celui défini dans la configuration SSH

## Fonctions helper

Deux fonctions helper ont été ajoutées dans `00-common.sh` :

### `ssh_host(host, command)`

Exécute une commande SSH sur un hôte distant en utilisant l'utilisateur configuré.

**Exemple** :
```bash
# Avant
ssh node1 "sudo systemctl status docker"

# Maintenant
ssh_host "node1" "sudo systemctl status docker"
```

### `scp_host(source, destination)`

Copie un fichier vers un hôte distant en utilisant l'utilisateur configuré.

**Exemple** :
```bash
# Avant
scp config.yaml node1:/tmp/

# Maintenant
scp_host config.yaml "node1:/tmp/"
```

## Scripts modifiés

Les scripts suivants ont été mis à jour pour utiliser ces fonctions :

- `00-common.sh` - Ajout des fonctions helper
- `01-os_preparation.sh` - Toutes les commandes SSH/SCP
- `02-rke2_deploy.sh` - Toutes les commandes SSH/SCP
- `04-cleanup-destroy.sh` - Toutes les commandes SSH

## Migration

Si vous avez des scripts personnalisés qui utilisent directement `ssh` ou `scp`, vous pouvez les migrer :

**Avant** :
```bash
for h in ${HOSTS[*]}; do
  ssh $h "sudo systemctl restart docker"
done
```

**Après** :
```bash
for h in "${HOSTS[@]}"; do
  ssh_host "$h" "sudo systemctl restart docker"
done
```

## Notes importantes

1. **Quotation des variables** : Les tableaux `HOSTS` utilisent maintenant `"${HOSTS[@]}"` au lieu de `${HOSTS[*]}` pour une meilleure gestion des espaces dans les noms d'hôtes.

2. **Compatibilité** : Si `SSH_USER` est vide, le comportement est identique à l'ancien code (utilise l'utilisateur actuel).

3. **Clés SSH** : Assurez-vous que les clés SSH sont configurées pour l'utilisateur spécifié dans `SSH_USER` si vous en utilisez un.

4. **Permissions sudo** : L'utilisateur configuré doit avoir les permissions sudo nécessaires sur les nœuds distants.

## Exemple complet

```bash
# Dans 00-vars.sh
SSH_USER="deploy"

# Les commandes suivantes utiliseront automatiquement deploy@hostname
ssh_host "node1" "sudo systemctl status docker"
scp_host "config.yaml" "node1:/tmp/"
```

