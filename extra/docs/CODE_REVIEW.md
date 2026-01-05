# Analyse du code - Rancher PoC

## Problèmes identifiés et corrections suggérées

### 🔴 Problèmes critiques (Sécurité)

#### 1. **Mot de passe SSH en clair** (`01-os_preparation.sh:35`)
```bash
read -s -p "${TXT_ENTER_CLIENT_PWD:=Please enter target hosts SSH password}: " PASSWD
for h in ${HOSTS[*]};
  do expect -c "set timeout 2; spawn ssh-copy-id -o StrictHostKeyChecking=no $h; expect 'assword:'; send "$PASSWD\\r"; interact"
done;
```

**Problème** : Le mot de passe est stocké dans une variable shell et peut être visible dans les processus.

**Correction suggérée** :
- Utiliser `sshpass` avec des options plus sécurisées
- Ou mieux : forcer l'utilisation de clés SSH uniquement
- Effacer la variable après utilisation : `unset PASSWD`

#### 2. **StrictHostKeyChecking désactivé** (`01-os_preparation.sh:37`)
```bash
ssh-copy-id -o StrictHostKeyChecking=no $h
```

**Problème** : Désactive la vérification des clés d'hôte, ce qui peut permettre des attaques man-in-the-middle.

**Correction suggérée** :
- Utiliser `StrictHostKeyChecking=accept-new` (disponible depuis OpenSSH 7.6)
- Ou pré-configurer les clés d'hôte manuellement

#### 3. **Pas de validation des entrées utilisateur**
Les scripts acceptent n'importe quelle entrée sans validation.

**Correction suggérée** : Ajouter des validations pour :
- Les FQDN (format valide)
- Les adresses IP
- Les versions de logiciels

---

### 🟠 Problèmes importants (Robustesse)

#### 4. **Absence de gestion d'erreurs cohérente**

**Problèmes** :
- Pas de `set -e` dans les scripts principaux (sauf `start-gitea.sh`)
- Pas de vérification des codes de retour
- Les commandes SSH qui échouent ne sont pas détectées

**Correction suggérée** :
```bash
#!/bin/bash
set -euo pipefail  # Arrêt sur erreur, variables non définies, erreurs dans les pipes
```

#### 5. **Pas de vérification d'existence des fichiers**

**Exemples** :
- `02-rke2_deploy.sh:22` : `scp rke2.linux-amd64.tar.gz` sans vérifier que le fichier existe
- `03-rancher_install.sh:81` : Vérifie `cacerts.pem` mais pas de message d'erreur clair

**Correction suggérée** :
```bash
if [[ ! -f rke2.linux-amd64.tar.gz ]]; then
    echo "Erreur: rke2.linux-amd64.tar.gz introuvable" >&2
    exit 1
fi
```

#### 6. **Variables non citées**

**Exemples** :
- `00-common.sh:57` : `${HOSTS[*]}` devrait être `"${HOSTS[@]}"`
- `01-os_preparation.sh:36` : `${HOSTS[*]}` devrait être `"${HOSTS[@]}"`

**Problème** : Peut causer des problèmes avec les espaces dans les noms d'hôtes.

**Correction** : Utiliser `"${HOSTS[@]}"` partout au lieu de `${HOSTS[*]}`

#### 7. **Utilisation de `watch` dans des scripts non-interactifs**

**Problème** : `watch` nécessite un terminal interactif et peut échouer dans des environnements automatisés.

**Exemples** :
- `02-rke2_deploy.sh:104`
- `03-rancher_install.sh:66,131`

**Correction suggérée** :
```bash
# Remplacer watch par une boucle avec timeout
timeout=300
elapsed=0
while ! kubectl get pods -A | grep -q "Running"; do
    sleep 5
    elapsed=$((elapsed + 5))
    if [ $elapsed -ge $timeout ]; then
        echo "Timeout atteint" >&2
        exit 1
    fi
done
```

---

### 🟡 Problèmes modérés (Bonnes pratiques)

#### 8. **Versions potentiellement obsolètes** (`01-vars.sh`)

**Problème** :
```bash
HELM_VERSION="3.8.2"
RKE2_VERSION="v1.26.9+rke2r1"
CERTMGR_VERSION="v1.12.5"
RANCHER_VERSION="2.7.6"
```

**Suggestion** : Documenter les versions minimales requises et vérifier la compatibilité.

#### 9. **Hardcodage de valeurs**

**Exemples** :
- `01-os_preparation.sh:126` : `chronyc`, `ntpq` hardcodés
- `02-rke2_deploy.sh:126` : `ranch1` hardcodé dans la commande SSH

**Correction** : Utiliser des variables de configuration.

#### 10. **Pas de vérification de prérequis système**

**Suggestion** : Ajouter des vérifications pour :
- Version minimale du système d'exploitation
- Espace disque disponible
- Mémoire disponible
- Connexions réseau

#### 11. **Gestion des erreurs SSH**

**Problème** : Les commandes SSH qui échouent ne sont pas toujours détectées.

**Correction suggérée** :
```bash
if ! ssh $h "command"; then
    echo "Erreur sur $h" >&2
    exit 1
fi
```

#### 12. **Nettoyage incomplet en cas d'erreur**

**Problème** : Si un script échoue au milieu, des ressources peuvent rester dans un état incohérent.

**Suggestion** : Implémenter des traps pour le nettoyage :
```bash
cleanup() {
    echo "Nettoyage en cours..."
    # Code de nettoyage
}
trap cleanup EXIT ERR
```

---

### 🔵 Améliorations suggérées

#### 13. **Logging structuré**

**Suggestion** : Ajouter un système de logging :
```bash
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}
```

#### 14. **Mode dry-run**

**Suggestion** : Ajouter une option `--dry-run` pour tester sans exécuter.

#### 15. **Validation des variables de configuration**

**Suggestion** : Ajouter une fonction de validation au début de chaque script :
```bash
validate_config() {
    local errors=0
    [[ -z "$HOST_LIST" ]] && { echo "HOST_LIST non défini" >&2; errors=1; }
    [[ -z "$RKE2_VERSION" ]] && { echo "RKE2_VERSION non défini" >&2; errors=1; }
    return $errors
}
```

#### 16. **Documentation des fonctions**

**Suggestion** : Ajouter des commentaires JSDoc-style pour chaque fonction :
```bash
## COMMAND_RKE2_INSTALL
# Description: Installe RKE2 sur tous les nœuds du cluster
# Paramètres: Aucun
# Retour: 0 si succès, 1 si échec
COMMAND_RKE2_INSTALL() {
    ...
}
```

#### 17. **Tests unitaires**

**Suggestion** : Créer des tests pour les fonctions critiques (validation, parsing, etc.)

---

## Résumé des priorités

1. **Critique** : Sécurité (mot de passe, StrictHostKeyChecking)
2. **Important** : Gestion d'erreurs (`set -euo pipefail`)
3. **Important** : Validation des fichiers et variables
4. **Modéré** : Quotation correcte des variables
5. **Modéré** : Remplacement de `watch` par des boucles avec timeout
6. **Amélioration** : Logging, validation, documentation

---

## Exemple de script corrigé (extrait)

```bash
#!/bin/bash
set -euo pipefail  # Arrêt sur erreur, variables non définies, erreurs dans les pipes

# Source variables
source ./01-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh

# Validation
validate_config() {
    local errors=0
    [[ -z "${HOST_LIST:-}" ]] && { echo "Erreur: HOST_LIST non défini" >&2; errors=1; }
    [[ ${#HOSTS[@]} -eq 0 ]] && { echo "Erreur: Aucun hôte défini" >&2; errors=1; }
    return $errors
}

validate_config || exit 1

## COMMAND_SSH_DEPLOY - Déploie les clés SSH
COMMAND_SSH_DEPLOY() {
    local passwd
    read -s -p "${TXT_ENTER_CLIENT_PWD:=Please enter target hosts SSH password}: " passwd
    echo
    
    for h in "${HOSTS[@]}"; do
        if ! sshpass -p "$passwd" ssh-copy-id -o StrictHostKeyChecking=accept-new "$h"; then
            echo "Erreur: Échec de la copie de la clé SSH vers $h" >&2
            unset passwd
            return 1
        fi
    done
    
    unset passwd  # Effacer le mot de passe de la mémoire
}
```

