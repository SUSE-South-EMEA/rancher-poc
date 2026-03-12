# Keycloak + OpenLDAP — Rancher OIDC Authentication

Extra pour rancher-poc : deploie Keycloak + OpenLDAP sur une VM dediee et configure
l'authentification OIDC dans Rancher Manager. Ce document est la reference complete
issue du deploiement reel et couvre tous les problemes rencontres.

## Table des matieres

- [Architecture](#architecture)
- [DNS (Pi-hole)](#dns-pi-hole)
- [Pre-requis](#pre-requis)
- [Etape 0 : Provisionner la VM (Terraform)](#etape-0--provisionner-la-vm-terraform)
- [Etape 1 : Deployer OpenLDAP](#etape-1--deployer-openldap)
- [Etape 2 : Deployer Keycloak](#etape-2--deployer-keycloak)
- [Etape 3 : Configurer le DNS](#etape-3--configurer-le-dns)
- [Etape 4 : Configurer Keycloak (realm, LDAP, OIDC client)](#etape-4--configurer-keycloak-realm-ldap-oidc-client)
- [Etape 5 : Integrer Rancher OIDC](#etape-5--integrer-rancher-oidc)
- [Etape 6 : Verification end-to-end](#etape-6--verification-end-to-end)
- [Etape 7 : Nettoyage](#etape-7--nettoyage)
- [Groupes et RBAC Rancher](#groupes-et-rbac-rancher)
- [Inspection des tokens (JWT)](#inspection-des-tokens-jwt)
- [Depannage detaille](#depannage-detaille)
- [Interface web](#interface-web)
- [Variables](#variables)

## Architecture

```
                  +--------------------------+
                  |  VM idp (172.16.3.12)    |
                  |  openSUSE Leap 15.6 / Podman    |
                  |                          |
                  |  +--------+  +--------+  |
                  |  |OpenLDAP|  |Keycloak|  |
                  |  |  :1389 |<-|  :8443 |  |
                  |  +--------+  +--------+  |
                  +-------------|------------+
                                |
                    OIDC (HTTPS self-signed)
                                |
                  +-------------|------------+
                  |  Rancher Manager         |
                  |  (172.16.3.20)           |
                  |  rancher.home.zypp.fr    |
                  +--------------------------+
```

**Flux reseau detaille :**

```
Navigateur utilisateur
    |
    | HTTPS (Let's Encrypt via Traefik sur rasp01)
    v
rancher.home.zypp.fr (172.16.3.6:443 -> 172.16.3.20:443)
    |
    | 1. Login OIDC -> redirect vers Keycloak
    v
keycloak.home.lo:8443 (172.16.3.12, self-signed)
    |
    | 2. Auth utilisateur (credentials verifies via LDAP)
    |
    | LDAP interne (conteneur openldap:389 via reseau Podman keycloak-net)
    |
    | 3. Token OIDC (JWT avec claim "groups")
    v
rancher.home.zypp.fr/verify-auth (callback)
    |
    | 4. Rancher valide le token aupres de Keycloak (server-side)
    |    IMPORTANT: les pods Rancher doivent truster le CA self-signed
```

- **OpenLDAP** (osixia/openldap:1.5.0) : annuaire LDAP avec OUs, groupes et utilisateurs de demo.
  Port 389 **a l'interieur du conteneur**, mappe sur `127.0.0.1:1389` cote hote.
  Keycloak y accede via le reseau Podman `keycloak-net` sur `openldap:389` (nom DNS conteneur).
- **Keycloak** (quay.io/keycloak/keycloak:26.2) : IdP OIDC avec federation LDAP, realm `rancher`, client OIDC confidential.
  Port principal HTTPS 8443 (application), port management 9000 (health checks).
- **Rancher** : authentification externe via `keyCloakOIDCConfig` (API v3). Necessite le CA
  self-signed dans les **pods** (pas seulement sur la VM hote).

## DNS (Pi-hole)

| Hostname | IP | Usage |
|----------|-----|-------|
| idp.home.lo | 172.16.3.12 | Alias generique pour la VM |
| keycloak.home.lo | 172.16.3.12 | FQDN utilise dans le certificat TLS et l'URL Keycloak |
| ldap.home.lo | 172.16.3.12 | Acces LDAP (optionnel, pour debug) |

Ces entrees sont creees automatiquement par le script `03-configure-dns.sh`.

## Pre-requis

### 1. Harvester HCI operationnel

```bash
# Verifier que Harvester repond
ssh rancher@172.16.3.11 "sudo /var/lib/rancher/rke2/bin/kubectl \
    --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes"
# Sortie attendue : 1 noeud Ready
```

### 2. Image openSUSE Leap 15.6 dans Harvester

```bash
# Verifier que l'image existe
ssh rancher@172.16.3.11 "sudo /var/lib/rancher/rke2/bin/kubectl \
    --kubeconfig /etc/rancher/rke2/rke2.yaml \
    get virtualmachineimages.harvesterhci.io -n default" | grep opensuse-leap
# Doit afficher : opensuse-leap-cloud
```

**IMPORTANT : Pourquoi openSUSE Leap et pas SLES 15 SP7 ?**
L'image cloud SLES 15 SP7 minimale (`image-nhtf9`) n'a **aucun depot logiciel** configure.
Il est impossible d'installer `podman` sans ajouter des repos (ce qui necessite un enregistrement SCC
ou des repos MLM). openSUSE Leap 15.6 a les repos OSS actifs par defaut et `podman` s'installe
directement via cloud-init `packages:`.

Si l'image n'existe pas, la telecharger :

```bash
# URL de l'image cloud openSUSE Leap 15.6
# https://download.opensuse.org/distribution/leap/15.6/appliances/openSUSE-Leap-15.6-Minimal-VM.x86_64-Cloud.qcow2
# Importer via Harvester UI > Images > Create
```

### 3. Terraform installe avec le provider Harvester

```bash
terraform -version
# terraform v1.x.x

ls /home/ju/workspace/TERRAFORM/KEYCLOAK/
# provider.tf  variables.tf  virtualmachine.tf
```

### 4. HashiCorp Vault accessible avec les secrets configures

```bash
# Verifier l'acces Vault (ne jamais afficher le token)
vault status
# Sealed: false, Version: 1.x.x

# Verifier que les secrets existent
vault kv get -field=admin_password secret/services/keycloak >/dev/null && echo "OK"
vault kv get -field=ldap_admin_password secret/services/keycloak >/dev/null && echo "OK"
vault kv get -field=oidc_client_secret secret/services/keycloak >/dev/null && echo "OK"
```

Si les secrets n'existent pas, les creer :

```bash
# Generer un UUID pour le client secret OIDC
OIDC_SECRET=$(uuidgen)

vault kv put secret/services/keycloak \
    admin_password="<mot-de-passe-admin-keycloak>" \
    ldap_admin_password="<mot-de-passe-admin-ldap>" \
    oidc_client_secret="$OIDC_SECRET"
```

### 5. Rancher Manager fonctionnel

```bash
# Verifier que Rancher repond
curl -sk https://rancher.home.zypp.fr/ping
# pong

# Verifier le login API
RANCHER_PW=$(vault kv get -field=password secret/services/rancher)
curl -sk -X POST https://rancher.home.zypp.fr/v3-public/localProviders/local?action=login \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"admin\",\"password\":\"${RANCHER_PW}\"}" | python3 -c "
import sys,json; d=json.load(sys.stdin); print('OK' if d.get('token') else 'FAIL')"
```

### 6. Pi-hole DNS accessible

```bash
# Verifier que Pi-hole repond au DNS
dig +short google.com @172.16.3.6
# Doit retourner une IP

# Verifier l'acces SSH a rasp01
ssh ju@172.16.3.6 "docker exec b41a7dff114c_pihole pihole-FTL --config dns.hosts" 2>/dev/null
# Doit afficher la liste JSON des hosts
```

### 7. Acces SSH depuis node1

```bash
# Tester la connectivite vers la plage d'IP Harvester
ping -c 1 172.16.3.12
# Doit repondre (si la VM est deja creee) ou timeout (normal si pas encore creee)
```

### 8. Outils necessaires sur node1

```bash
# Verifier les outils CLI
which python3 dig curl openssl ssh ldapsearch
# Tous doivent etre presents

# ldapsearch est dans le paquet openldap2-client (openSUSE) ou ldap-utils (Debian)
```

---

## Etape 0 : Provisionner la VM (Terraform)

**Script :** Pas de script bash — utilisation directe de Terraform.

**Ce que ca fait :**
- Cree une VM `idp` sur Harvester via le provider Terraform Harvester
- Specs : 2 vCPU, 4 Gi RAM, 40 Gi disque, openSUSE Leap 15.6
- IP statique : 172.16.3.12/16 (gateway 172.16.0.1)
- Cloud-init installe `podman`, active `qemu-guest-agent`, configure le DNS

**Variables cles (variables.tf) :**

| Variable | Valeur | Description |
|----------|--------|-------------|
| `vm_image` | `default/opensuse-leap-cloud` | Image Harvester a utiliser |
| `vm_ip` | `172.16.3.12/16` | IP statique de la VM |
| `network_gateway` | `172.16.0.1` | Passerelle reseau |
| `network_nameservers` | `["172.16.3.6"]` | DNS Pi-hole |
| `network_name` | `default/production` | Reseau bridge Harvester |

**Cloud-init important :** Le cloud-init fait deux choses critiques :
1. Installe `podman` via `packages:`
2. Force le DNS via `NETCONFIG_DNS_STATIC_SERVERS` dans `/etc/sysconfig/network/config`
   (voir section Depannage pour pourquoi c'est necessaire sur Leap)

**Commandes :**

```bash
cd /home/ju/workspace/TERRAFORM/KEYCLOAK
terraform init
terraform plan
terraform apply
```

**Verification :**

```bash
# Attendre 1-2 minutes que cloud-init termine
ssh opensuse@172.16.3.12 hostname
# Sortie attendue : idp

ssh opensuse@172.16.3.12 podman --version
# Sortie attendue : podman version 4.x.x

# Verifier que le DNS fonctionne dans la VM
ssh opensuse@172.16.3.12 "cat /etc/resolv.conf"
# Doit contenir : nameserver 172.16.3.6

ssh opensuse@172.16.3.12 "dig +short google.com"
# Doit retourner une IP (preuve que le DNS fonctionne)
```

**Erreurs courantes :**
- `ssh: connect to host 172.16.3.12 port 22: Connection refused` : la VM n'a pas encore fini de booter, attendre 30-60s
- `podman: command not found` : cloud-init n'a pas fini, verifier avec `ssh opensuse@172.16.3.12 "cloud-init status"`
- DNS ne fonctionne pas dans la VM : voir section [Cloud-init DNS sur openSUSE Leap](#cloud-init-dns-ne-fonctionne-pas-sur-opensuse-leap)

---

## Etape 1 : Deployer OpenLDAP

**Script :** `01-deploy-openldap.sh`

**Ce que le script fait (en detail) :**

1. **Charge les variables** depuis `keycloak-vars.sh` et les fonctions de log depuis `00-common.sh`
2. **Recupere le mot de passe admin LDAP** depuis Vault (`secret/services/keycloak` -> `ldap_admin_password`)
3. **Genere 3 fichiers LDIF** dans un repertoire temporaire :
   - `00-base.ldif` : cree les OUs `People` et `Groups`, puis les groupes (`rancher-admins`, `rancher-users`, `rancher-readonly`) avec un membre `cn=placeholder` (requis car `groupOfNames` exige au moins un `member`)
   - `01-users.ldif` : cree les utilisateurs (`jniedergang`, `demouser`, `viewer`) avec `objectClass: inetOrgPerson` + `posixAccount` + `shadowAccount`, mot de passe `changeme`
   - `02-memberships.ldif` : operations `ldapmodify` (changetype: modify) pour ajouter chaque utilisateur dans son groupe
4. **Cree le reseau Podman** `keycloak-net` sur la VM (permet a Keycloak de joindre OpenLDAP par nom DNS `openldap`)
5. **Transfere les LDIF** sur la VM via SSH + `cat >` (pas scp, car Harvester bloque parfois scp)
6. **Deploie le conteneur** `osixia/openldap:1.5.0` :
   - Port : `127.0.0.1:1389:389` (ecoute seulement en local)
   - Reseau : `keycloak-net` (pour communication avec Keycloak)
   - Variables : `LDAP_ORGANISATION`, `LDAP_DOMAIN`, `LDAP_ADMIN_PASSWORD`
   - Flag `--copy-service` requis par l'image osixia
7. **Attend que slapd soit pret** (boucle ldapsearch, max 30 tentatives x 2s + 3s de grace)
8. **Importe les LDIF** dans l'ordre : base -> users -> memberships (avec retry pour la base car slapd peut etre lent au demarrage)
9. **Verifie** le nombre d'utilisateurs et groupes importes

**Variables cles :**

| Variable | Valeur | Description |
|----------|--------|-------------|
| `KC_VM_HOST` | `172.16.3.12` | IP de la VM |
| `KC_VM_SSH_USER` | `opensuse` | Utilisateur SSH |
| `LDAP_CONTAINER_NAME` | `openldap` | Nom du conteneur (= DNS dans keycloak-net) |
| `LDAP_IMAGE` | `docker.io/osixia/openldap:1.5.0` | Image Docker |
| `LDAP_PORT` | `1389` | Port **hote** (mappe sur 389 dans le conteneur) |
| `LDAP_DOMAIN` | `home.lo` | Domaine LDAP |
| `LDAP_BASE_DN` | `dc=home,dc=lo` | Base DN |
| `LDAP_GROUPS` | `rancher-admins rancher-users rancher-readonly` | Groupes a creer |
| `LDAP_DEMO_USERS` | `uid:prenom:nom:groupe` | Utilisateurs de demo |

**Commandes manuelles equivalentes :**

```bash
# Creer le reseau
ssh opensuse@172.16.3.12 "sudo podman network create keycloak-net"

# Lancer OpenLDAP
ssh opensuse@172.16.3.12 "sudo podman run -d \
    --name openldap \
    --network keycloak-net \
    -p 127.0.0.1:1389:389 \
    -e LDAP_ORGANISATION='Homelab' \
    -e LDAP_DOMAIN='home.lo' \
    -e LDAP_ADMIN_PASSWORD='<vault>' \
    docker.io/osixia/openldap:1.5.0 --copy-service"

# Importer les LDIF (depuis la VM)
ldapadd -x -c -H ldap://127.0.0.1:1389 \
    -D 'cn=admin,dc=home,dc=lo' -w '<vault>' -f /tmp/ldap-init/00-base.ldif
ldapadd -x -c -H ldap://127.0.0.1:1389 \
    -D 'cn=admin,dc=home,dc=lo' -w '<vault>' -f /tmp/ldap-init/01-users.ldif
ldapmodify -x -H ldap://127.0.0.1:1389 \
    -D 'cn=admin,dc=home,dc=lo' -w '<vault>' -f /tmp/ldap-init/02-memberships.ldif
```

**Verification :**

```bash
# Verifier que le conteneur tourne
ssh opensuse@172.16.3.12 "sudo podman ps --format '{{.Names}} {{.Status}}'" | grep openldap
# openldap Up X minutes

# Lister les utilisateurs
ssh opensuse@172.16.3.12 "ldapsearch -x -H ldap://127.0.0.1:1389 \
    -D 'cn=admin,dc=home,dc=lo' -w '<vault>' -b 'ou=People,dc=home,dc=lo' '(uid=*)' uid cn mail"
# Doit afficher 3 utilisateurs : jniedergang, demouser, viewer

# Lister les groupes et leurs membres
ssh opensuse@172.16.3.12 "ldapsearch -x -H ldap://127.0.0.1:1389 \
    -D 'cn=admin,dc=home,dc=lo' -w '<vault>' -b 'ou=Groups,dc=home,dc=lo' '(objectClass=groupOfNames)' cn member"
# Doit afficher 3 groupes avec leurs membres respectifs

# Verifier un utilisateur specifique
ssh opensuse@172.16.3.12 "ldapsearch -x -H ldap://127.0.0.1:1389 \
    -D 'cn=admin,dc=home,dc=lo' -w '<vault>' -b 'dc=home,dc=lo' '(uid=jniedergang)'"
```

**Erreurs courantes :**
- `ldap_bind: Invalid credentials (49)` : le mot de passe Vault ne correspond pas
- `Can't contact LDAP server (-1)` : le conteneur n'est pas encore pret, attendre quelques secondes
- `Already exists (68)` sur ldapadd : les entrees existent deja (idempotent, pas une erreur)

### Personnaliser les utilisateurs

Editer `keycloak-vars.sh` avant de lancer le script :

```bash
LDAP_GROUPS=("rancher-admins" "rancher-users" "rancher-readonly")
LDAP_DEMO_USERS=(
    "jniedergang:Julien:Niedergang:rancher-admins"
    "demouser:Demo:User:rancher-users"
    "viewer:Read:Only:rancher-readonly"
)
```

Format : `uid:prenom:nom:groupe` — le mot de passe par defaut est `changeme` pour tous.

---

## Etape 2 : Deployer Keycloak

**Script :** `02-deploy-keycloak.sh`

**Ce que le script fait (en detail) :**

1. **Recupere le mot de passe admin Keycloak** depuis Vault
2. **Genere un certificat TLS self-signed** sur la VM :
   - RSA 2048, valide 365 jours
   - CN = `keycloak.home.lo`
   - SANs = `DNS:keycloak.home.lo`, `DNS:idp.home.lo`, `IP:172.16.3.12`
   - Sauvegarde : `/tmp/keycloak-certs/tls.{key,crt}` sur la VM
3. **Copie le certificat en local** dans `extra/keycloak/.certs/keycloak-ca.crt` (sera utilise a l'etape 5)
4. **Deploie le conteneur Keycloak 26.2** :
   - Port application : `0.0.0.0:8443:8443` (HTTPS, accessible de l'exterieur)
   - Port management : `127.0.0.1:9000:9000` (health checks, local seulement)
   - Mode `start` (production, pas `start-dev`)
   - Variables : admin bootstrap, hostname, TLS, health enabled, HTTP disabled
5. **Attend que Keycloak soit pret** en testant `https://127.0.0.1:8443/realms/master` (pas le health endpoint !)

**Variables cles :**

| Variable | Valeur | Description |
|----------|--------|-------------|
| `KC_IMAGE` | `quay.io/keycloak/keycloak:26.2` | Image Keycloak |
| `KC_HTTPS_PORT` | `8443` | Port HTTPS principal |
| `KC_FQDN` | `keycloak.home.lo` | FQDN dans le certificat |
| `KC_ADMIN_USER` | `admin` | Utilisateur admin initial |
| `KC_PODMAN_NETWORK` | `keycloak-net` | Reseau partage avec OpenLDAP |

**Variables d'environnement Keycloak :**

| Variable conteneur | Valeur | Description |
|--------------------|--------|-------------|
| `KC_BOOTSTRAP_ADMIN_USERNAME` | `admin` | Admin initial (26.x, remplace KEYCLOAK_ADMIN) |
| `KC_BOOTSTRAP_ADMIN_PASSWORD` | `<vault>` | Mot de passe admin |
| `KC_HTTPS_CERTIFICATE_FILE` | `/opt/keycloak/conf/tls.crt` | Certificat TLS |
| `KC_HTTPS_CERTIFICATE_KEY_FILE` | `/opt/keycloak/conf/tls.key` | Cle TLS |
| `KC_HOSTNAME` | `https://keycloak.home.lo:8443` | URL publique (inclut le port) |
| `KC_HEALTH_ENABLED` | `true` | Active les endpoints /health/* |
| `KC_HTTP_ENABLED` | `false` | Desactive HTTP (HTTPS only) |

**Commandes manuelles equivalentes :**

```bash
# Generer le certificat
ssh opensuse@172.16.3.12 "mkdir -p /tmp/keycloak-certs && openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /tmp/keycloak-certs/tls.key -out /tmp/keycloak-certs/tls.crt -days 365 \
    -subj '/CN=keycloak.home.lo' \
    -addext 'subjectAltName=DNS:keycloak.home.lo,DNS:idp.home.lo,IP:172.16.3.12'"

# Copier le cert en local
ssh opensuse@172.16.3.12 "cat /tmp/keycloak-certs/tls.crt" > .certs/keycloak-ca.crt

# Lancer Keycloak
ssh opensuse@172.16.3.12 "sudo podman run -d \
    --name keycloak --network keycloak-net \
    -p 0.0.0.0:8443:8443 -p 127.0.0.1:9000:9000 \
    -e KC_BOOTSTRAP_ADMIN_USERNAME=admin \
    -e KC_BOOTSTRAP_ADMIN_PASSWORD='<vault>' \
    -e KC_HTTPS_CERTIFICATE_FILE=/opt/keycloak/conf/tls.crt \
    -e KC_HTTPS_CERTIFICATE_KEY_FILE=/opt/keycloak/conf/tls.key \
    -e KC_HOSTNAME='https://keycloak.home.lo:8443' \
    -e KC_HEALTH_ENABLED=true \
    -e KC_HTTP_ENABLED=false \
    -v /tmp/keycloak-certs/tls.crt:/opt/keycloak/conf/tls.crt:Z \
    -v /tmp/keycloak-certs/tls.key:/opt/keycloak/conf/tls.key:Z \
    quay.io/keycloak/keycloak:26.2 start"
```

**Verification :**

```bash
# Verifier que le conteneur tourne
ssh opensuse@172.16.3.12 "sudo podman ps" | grep keycloak
# keycloak  Up X minutes

# Tester le realm master (methode la plus fiable)
curl -sk https://172.16.3.12:8443/realms/master | python3 -m json.tool | head -5
# Sortie attendue : { "realm": "master", "public_key": "...", ... }

# Tester le health endpoint (port management 9000, local seulement)
ssh opensuse@172.16.3.12 "curl -sk https://127.0.0.1:9000/health/ready"
# {"status":"UP","checks":[...]}

# NE PAS tester le health sur le port 8443 :
# curl -sk https://172.16.3.12:8443/health/ready  -> 404 ou vide !
# Le health est servi sur le port management 9000 uniquement.

# Verifier les logs si ca ne demarre pas
ssh opensuse@172.16.3.12 "sudo podman logs --tail 30 keycloak"
```

**Erreurs courantes :**
- Keycloak met 30-90 secondes a demarrer, c'est normal
- `HTTPS required` dans les logs : verifier que les volumes TLS sont bien montes (`:Z` important pour SELinux/Podman)
- Le health endpoint `/health/ready` repond seulement sur le port **9000** (management), pas sur 8443

---

## Etape 3 : Configurer le DNS

**Script :** `03-configure-dns.sh`

**Ce que le script fait (en detail) :**

1. **Lit la configuration DNS actuelle** de Pi-hole via SSH + `pihole-FTL --config dns.hosts`
2. **Fusionne** les nouvelles entrees avec les existantes via un script Python inline
   (necessaire car Pi-hole v6 retourne un format qui n'est pas du JSON valide standard)
3. **Ecrit le JSON** dans un fichier temporaire sur rasp01 puis l'applique via `pihole-FTL --config`
4. **Verifie** la resolution DNS avec `dig`

**Variables cles :**

| Variable | Valeur | Description |
|----------|--------|-------------|
| `PIHOLE_HOST` | `172.16.3.6` | IP de rasp01 (Pi-hole) |
| `PIHOLE_SSH_USER` | `ju` | Utilisateur SSH |
| `PIHOLE_CONTAINER` | `b41a7dff114c_pihole` | Nom du conteneur Docker Pi-hole |
| `DNS_ENTRIES` | tableau | Entrees IP hostname a ajouter |

**Pourquoi Python et pas jq ?**
Pi-hole v6 (`pihole-FTL --config dns.hosts`) retourne un format non-standard :
`[ 172.16.3.6 pihole.home.lo, 172.16.0.1 gateway.home.lo ]` — les valeurs ne sont
pas quotees. `jq` echoue sur ce format. Le script Python parse ce format manuellement
et genere du JSON valide pour la mise a jour.

**Commandes manuelles equivalentes :**

```bash
# Lire les DNS actuels
ssh ju@172.16.3.6 "docker exec b41a7dff114c_pihole pihole-FTL --config dns.hosts"

# Ajouter manuellement (attention au format JSON)
# Methode : construire le tableau complet puis l'appliquer
ssh ju@172.16.3.6 "docker exec b41a7dff114c_pihole pihole-FTL --config dns.hosts \
    '[\"172.16.3.12 idp.home.lo\", \"172.16.3.12 keycloak.home.lo\", \"172.16.3.12 ldap.home.lo\"]'"
```

**Verification :**

```bash
# Tester la resolution DNS
dig +short keycloak.home.lo @172.16.3.6
# 172.16.3.12

dig +short idp.home.lo @172.16.3.6
# 172.16.3.12

dig +short ldap.home.lo @172.16.3.6
# 172.16.3.12

# Depuis la VM Rancher aussi (important pour l'etape 5)
ssh rancher@172.16.3.20 "dig +short keycloak.home.lo"
# 172.16.3.12
```

**Erreurs courantes :**
- `Error: malformed JSON` : le format Pi-hole v6 n'est pas du JSON standard, utiliser le wrapper Python
- La resolution peut prendre 2-3 secondes pour se propager apres la mise a jour

---

## Etape 4 : Configurer Keycloak (realm, LDAP, OIDC client)

**Script :** `04-configure-keycloak-ldap.sh`

**Ce que le script fait (en detail) :**

Le script utilise exclusivement l'**API Admin REST** de Keycloak (pas la CLI `kcadm.sh`).
Il effectue 6 operations, avec refresh du token admin entre chaque (les tokens expirent apres 60 secondes).

### 4.1 Obtenir un token admin

```bash
curl -sk -X POST "https://keycloak.home.lo:8443/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli" \
    -d "username=admin" \
    -d "password=<vault>" \
    -d "grant_type=password"
# Retourne : { "access_token": "eyJ...", "expires_in": 60, ... }
```

**IMPORTANT :** Le `grant_type=password` (Direct Access Grant) doit etre active sur le client
`admin-cli` dans le realm `master`. C'est le cas par defaut.

### 4.2 Creer le realm `rancher`

```bash
curl -sk -X POST "https://keycloak.home.lo:8443/admin/realms" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"realm": "rancher", "enabled": true, "displayName": "Rancher SSO"}'
```

Idempotent : verifie d'abord si le realm existe (GET `/admin/realms/rancher` -> 200 = existe deja).

### 4.3 Configurer la federation LDAP

Cree un composant `UserStorageProvider` avec le provider `ldap` :

| Parametre | Valeur | Detail |
|-----------|--------|--------|
| `connectionUrl` | `ldap://openldap:389` | Via reseau Podman (pas `127.0.0.1:1389`) |
| `bindDn` | `cn=admin,dc=home,dc=lo` | Utilisateur admin LDAP |
| `usersDn` | `ou=People,dc=home,dc=lo` | OU contenant les utilisateurs |
| `usernameLDAPAttribute` | `uid` | Attribut de login |
| `userObjectClasses` | `inetOrgPerson` | Filtre de recherche |
| `editMode` | `READ_ONLY` | Pas de modifications LDAP via Keycloak |
| `importEnabled` | `true` | Import les utilisateurs dans la base Keycloak |

**ATTENTION sur l'URL LDAP :** Keycloak est dans le meme reseau Podman `keycloak-net` qu'OpenLDAP.
Il utilise le nom DNS du conteneur `openldap` et le port **interne** `389` (pas le port hote `1389`).

### 4.4 Ajouter un Group Mapper LDAP

Cree un sous-composant `LDAPStorageMapper` attache a la federation :

```json
{
    "name": "group-mapper",
    "providerId": "group-ldap-mapper",
    "config": {
        "groups.dn": ["ou=Groups,dc=home,dc=lo"],
        "group.name.ldap.attribute": ["cn"],
        "group.object.classes": ["groupOfNames"],
        "membership.ldap.attribute": ["member"],
        "membership.attribute.type": ["DN"],
        "mode": ["READ_ONLY"]
    }
}
```

### 4.5 Declencher la synchro LDAP

```bash
curl -sk -X POST "https://keycloak.home.lo:8443/admin/realms/rancher/user-storage/$FED_ID/sync?action=triggerFullSync" \
    -H "Authorization: Bearer $TOKEN"
# Retourne : {"added": 3, "updated": 0, "removed": 0, "failed": 0}
```

### 4.6 Creer le client OIDC `rancher`

| Parametre | Valeur | Explication |
|-----------|--------|-------------|
| `clientId` | `rancher` | Identifiant du client |
| `publicClient` | `false` | Client **confidential** (avec secret) |
| `secret` | `<vault>` | Secret partage avec Rancher |
| `redirectUris` | `["https://rancher.home.zypp.fr/verify-auth"]` | Callback Rancher |
| `standardFlowEnabled` | `true` | Authorization Code Flow (login web) |
| `directAccessGrantsEnabled` | `true` | Resource Owner Password Grant (pour tests CLI) |
| `serviceAccountsEnabled` | `false` | Pas de compte de service |

**IMPORTANT sur `directAccessGrantsEnabled` :**
Ce flag doit etre `true` pour pouvoir tester l'authentification via `curl` (grant_type=password).
Sans ce flag, seul le flow navigateur (redirect) fonctionne.

### 4.7 Ajouter le protocol mapper `groups`

Ajoute un **protocol mapper** directement sur le **client** (pas un scope global) :

```json
{
    "name": "groups",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-group-membership-mapper",
    "config": {
        "full.path": "false",
        "id.token.claim": "true",
        "access.token.claim": "true",
        "claim.name": "groups",
        "userinfo.token.claim": "true"
    }
}
```

**IMPORTANT :** Le claim `groups` dans le token est ajoute via un **protocol mapper** sur le client,
PAS via un "client scope". Un scope `groups` ne suffirait pas a injecter le claim dans le token.
Le mapper type `oidc-group-membership-mapper` itere les groupes Keycloak de l'utilisateur et les
ajoute comme tableau JSON dans le claim `groups`.

`full.path: false` = seulement le nom du groupe (e.g. `rancher-admins`), pas le chemin complet
(e.g. `/rancher-admins`).

**Verification :**

```bash
# OIDC Discovery
curl -sk https://keycloak.home.lo:8443/realms/rancher/.well-known/openid-configuration | python3 -m json.tool
# Doit contenir : issuer, authorization_endpoint, token_endpoint, etc.

# Lister les utilisateurs du realm
TOKEN=$(curl -sk -X POST "https://keycloak.home.lo:8443/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli&username=admin&password=<vault>&grant_type=password" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

curl -sk -H "Authorization: Bearer $TOKEN" \
    "https://keycloak.home.lo:8443/admin/realms/rancher/users" | python3 -m json.tool
# Doit lister jniedergang, demouser, viewer

# Lister les groupes du realm
curl -sk -H "Authorization: Bearer $TOKEN" \
    "https://keycloak.home.lo:8443/admin/realms/rancher/groups" | python3 -m json.tool
# Doit lister rancher-admins, rancher-users, rancher-readonly

# Tester le login OIDC d'un utilisateur (Direct Access Grant)
curl -sk -X POST "https://keycloak.home.lo:8443/realms/rancher/protocol/openid-connect/token" \
    -d "client_id=rancher" \
    -d "client_secret=<vault-oidc-client-secret>" \
    -d "username=jniedergang" \
    -d "password=changeme" \
    -d "grant_type=password" \
    -d "scope=openid profile email" | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK' if 'access_token' in d else d)"
```

**Erreurs courantes :**
- `401 Unauthorized` : le token admin a expire (> 60s), le script le rafraichit automatiquement
- `Conflict` (409) : le composant existe deja (idempotent, pas une erreur)
- `Client not found` apres creation : rafraichir le token et re-lister

---

## Etape 5 : Integrer Rancher OIDC

**Script :** `05-configure-rancher-oidc.sh`

C'est l'etape la plus complexe. Elle gere 3 problemes distincts :
1. Le CA self-signed doit etre trust par les **pods** Rancher (pas juste la VM)
2. L'API Rancher utilise un endpoint specifique pour Keycloak OIDC
3. Helm peut entrer en conflit avec des patches kubectl manuels

**Ce que le script fait (en detail) :**

### 5.1 Installer le CA sur la VM Rancher (trust store hote)

```bash
# Copier le cert (via cat, pas scp)
cat .certs/keycloak-ca.crt | ssh rancher@172.16.3.20 "cat > /tmp/keycloak-ca.crt"
ssh rancher@172.16.3.20 "sudo cp /tmp/keycloak-ca.crt /etc/pki/trust/anchors/keycloak-ca.crt \
    && sudo update-ca-certificates"
```

Ceci met a jour le trust store de la VM hote. Mais ce n'est **pas suffisant** :
les pods Rancher ont leur propre trust store base sur le CA bundle de l'image conteneur.

### 5.2 Creer le secret `tls-ca` pour les pods Rancher

```bash
# Sur la VM Rancher
kubectl -n cattle-system create secret generic tls-ca --from-file=cacerts.pem=/tmp/keycloak-ca.pem
```

Ce secret sera monte automatiquement dans les pods Rancher quand `privateCA=true` est active dans Helm.
Rancher lit le fichier `cacerts.pem` du secret `tls-ca` et l'ajoute a son trust store interne.

**POURQUOI c'est necessaire :**
Quand Rancher recoit le callback OIDC, il doit valider le token en contactant Keycloak
**depuis l'interieur du pod** (pas depuis la VM). Sans le CA dans le pod, on obtient :
`x509: certificate signed by unknown authority`.

### 5.3 Helm upgrade avec `privateCA=true`

```bash
sudo KUBECONFIG=/etc/rancher/rke2/rke2.yaml /usr/local/bin/helm upgrade rancher rancher-prime/rancher \
    -n cattle-system \
    --set hostname=rancher.home.zypp.fr \
    --set tls=external \
    --set privateCA=true \
    --set replicas=1 \
    --set systemDefaultRegistry=registry.rancher.com \
    --set global.cattle.psp.enabled=false \
    --set startupProbe.failureThreshold=60
```

**ATTENTION :** Tous les `--set` doivent etre passes a chaque `helm upgrade`, sinon Helm
reinitialise les valeurs non specifiees a leurs defauts. En particulier :
- `startupProbe.failureThreshold=60` est critique (la valeur par defaut fait crasher les pods
  au demarrage quand Rancher met du temps a initialiser le catalogue git)
- `replicas=1` car on est sur un noeud unique

### 5.4 Attendre que Rancher soit pret

Attend le rollout du deployment et que `/ping` reponde 200.

### 5.5 Verifier la connectivite Keycloak depuis le pod

```bash
kubectl exec -n cattle-system deploy/rancher -- \
    curl -sf https://keycloak.home.lo:8443/realms/rancher/.well-known/openid-configuration
```

Si cette commande reussit, le CA est bien monte dans le pod ET le DNS fonctionne depuis le pod.

### 5.6 Configurer OIDC via l'API Rancher v3

```bash
# Login Rancher
TOKEN=$(curl -sk -X POST https://rancher.home.zypp.fr/v3-public/localProviders/local?action=login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"<vault>"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")

# Configurer OIDC
curl -sk -X PUT "https://rancher.home.zypp.fr/v3/keyCloakOIDCConfigs/keycloakoidc" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "accessMode": "unrestricted",
        "enabled": true,
        "type": "keyCloakOIDCConfig",
        "rancherUrl": "https://rancher.home.zypp.fr/verify-auth",
        "clientId": "rancher",
        "clientSecret": "<vault-oidc-client-secret>",
        "issuer": "https://keycloak.home.lo:8443/realms/rancher",
        "authEndpoint": "https://keycloak.home.lo:8443/realms/rancher/protocol/openid-connect/auth",
        "tokenEndpoint": "https://keycloak.home.lo:8443/realms/rancher/protocol/openid-connect/token",
        "scope": "openid profile email",
        "groupSearchEnabled": true
    }'
```

**ATTENTION sur l'endpoint API :**
- L'endpoint est `keyCloakOIDCConfigs/keycloakoidc` (avec un **s** et l'ID `keycloakoidc`)
- PAS `keyCloakOIDCConfig` (singulier sans ID) — cela retourne 404
- Pour lire la config : `GET /v3/authConfigs/keycloakoidc` (pas le meme chemin que pour PUT !)
- Pour desactiver : `POST /v3/keyCloakOIDCConfigs/keycloakoidc?action=disable`

**Verification :**

```bash
# Verifier que OIDC est active
curl -sk -H "Authorization: Bearer $TOKEN" \
    https://rancher.home.zypp.fr/v3/authConfigs/keycloakoidc | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(f'enabled={d[\"enabled\"]}, issuer={d.get(\"issuer\",\"N/A\")}')"
# enabled=True, issuer=https://keycloak.home.lo:8443/realms/rancher

# Verifier que le pod peut joindre Keycloak
ssh rancher@172.16.3.20 "sudo /var/lib/rancher/rke2/bin/kubectl \
    --kubeconfig /etc/rancher/rke2/rke2.yaml \
    exec -n cattle-system deploy/rancher -- \
    curl -sf https://keycloak.home.lo:8443/realms/rancher/.well-known/openid-configuration 2>/dev/null | head -c 80"
# {"issuer":"https://keycloak.home.lo:8443/realms/rancher",...

# Ouvrir https://rancher.home.zypp.fr dans un navigateur
# -> Le bouton "Log in with Keycloak" doit apparaitre
```

---

## Etape 6 : Verification end-to-end

**Script :** `06-verify.sh`

**Ce que le script fait :**
Execute 8 verifications automatisees avec un compteur pass/fail :

| # | Check | Methode |
|---|-------|---------|
| 1 | VM SSH accessible | `ssh hostname` |
| 2 | Conteneur OpenLDAP tourne | `podman ps` |
| 3 | Conteneur Keycloak tourne | `podman ps` |
| 4 | LDAP peuple (>=1 user) | `ldapsearch (uid=*)` |
| 5 | Keycloak sain | Health port 9000, fallback realm master port 8443 |
| 6 | OIDC discovery accessible | `curl .well-known/openid-configuration` |
| 7 | DNS resout (3 entrees) | `dig @pihole` |
| 8 | Rancher OIDC active | API v3 `authConfigs/keycloakoidc` |

```bash
cd /home/ju/workspace/rancher-poc/extra/keycloak
bash 06-verify.sh
```

Sortie attendue :

```
[INFO] [PASS] VM SSH reachable
[INFO] [PASS] OpenLDAP container running
[INFO] [PASS] Keycloak container running
[INFO] [PASS] LDAP users present (3)
[INFO] [PASS] Keycloak health
[INFO] [PASS] OIDC discovery endpoint
[INFO] [PASS] DNS idp.home.lo
[INFO] [PASS] DNS keycloak.home.lo
[INFO] [PASS] DNS ldap.home.lo
[INFO] [PASS] Rancher OIDC enabled
=== Results: 10 checks, 10 passed, 0 failed ===
```

**Test login complet (manuel) :**

```bash
# 1. Test login OIDC via curl (Direct Access Grant)
OIDC_SECRET=$(vault kv get -field=oidc_client_secret secret/services/keycloak)
curl -sk -X POST "https://keycloak.home.lo:8443/realms/rancher/protocol/openid-connect/token" \
    -d "client_id=rancher" \
    -d "client_secret=${OIDC_SECRET}" \
    -d "username=jniedergang" \
    -d "password=changeme" \
    -d "grant_type=password" \
    -d "scope=openid profile email" | python3 -c "
import sys,json
d = json.load(sys.stdin)
if 'access_token' in d:
    print('LOGIN OK')
    print(f'  Token type: {d[\"token_type\"]}')
    print(f'  Expires in: {d[\"expires_in\"]}s')
else:
    print(f'LOGIN FAILED: {d}')
"

# 2. Test navigateur : ouvrir https://rancher.home.zypp.fr -> "Log in with Keycloak"
#    Credentials : jniedergang / changeme
```

---

## Etape 7 : Nettoyage

**Script :** `07-cleanup.sh`

**Ce que le script fait (en detail) :**

1. **Desactive OIDC dans Rancher** : `POST /v3/keyCloakOIDCConfigs/keycloakoidc?action=disable`
2. **Supprime le CA de la VM Rancher** : `rm /etc/pki/trust/anchors/keycloak-ca.crt` + `update-ca-certificates`
3. **Supprime le secret `tls-ca`** : `kubectl delete secret tls-ca -n cattle-system`
4. **Helm upgrade sans privateCA** : reinitialise Rancher a sa config originale
5. **Arrete et supprime les conteneurs** sur la VM IDP : `podman stop/rm keycloak openldap`
6. **Supprime le reseau Podman** `keycloak-net`
7. **Retire les entrees DNS** de Pi-hole (meme logique Python que l'ajout)
8. **Supprime les fichiers locaux** (`.certs/`)

```bash
cd /home/ju/workspace/rancher-poc/extra/keycloak
bash 07-cleanup.sh
```

**Pour detruire la VM :**

```bash
cd /home/ju/workspace/TERRAFORM/KEYCLOAK
terraform destroy
```

**ATTENTION :** Le cleanup remet Rancher en mode auth local uniquement. Les utilisateurs OIDC
qui etaient connectes seront deconnectes. L'admin local reste accessible.

---

## Groupes et RBAC Rancher

### Les 3 groupes LDAP

| Groupe LDAP | Utilisateur de demo | Role Rancher prevu |
|-------------|--------------------|--------------------|
| `rancher-admins` | jniedergang | Administrator (cluster + global) |
| `rancher-users` | demouser | Cluster Member / Project Owner |
| `rancher-readonly` | viewer | Read-Only / Cluster Viewer |

### Assignation des roles apres le premier login

**IMPORTANT :** Les utilisateurs OIDC n'ont **aucun role** apres leur premier login.
Ils apparaissent dans Rancher comme "users" mais ne peuvent rien voir ni faire.
L'admin local doit assigner les roles manuellement ou configurer des regles par defaut.

**Via l'UI Rancher :**

1. Se connecter en admin local (https://rancher.home.zypp.fr)
2. Aller dans **Configuration > Users & Authentication > Users**
3. L'utilisateur OIDC apparait apres son premier login (pas avant)
4. Cliquer sur l'utilisateur, puis **Edit**
5. Dans **Global Permissions**, choisir le role :
   - `Administrator` pour rancher-admins
   - `Standard User` pour rancher-users
   - `User-Base` (ou custom) pour rancher-readonly

**Via l'API Rancher :**

```bash
# Lister les utilisateurs (chercher l'ID de l'utilisateur OIDC)
curl -sk -H "Authorization: Bearer $TOKEN" \
    https://rancher.home.zypp.fr/v3/users | python3 -c "
import sys,json
for u in json.load(sys.stdin)['data']:
    print(f'{u[\"id\"]:20s} {u.get(\"username\",\"N/A\"):20s} {u.get(\"principalIds\",[])}')
"

# Assigner un role global (exemple : admin pour jniedergang)
curl -sk -X POST https://rancher.home.zypp.fr/v3/globalrolebindings \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "globalRoleId": "admin",
        "userId": "<user-id-from-above>"
    }'
```

### Automatisation future avec le claim `groups`

Le claim `groups` est present dans le token OIDC (grace au protocol mapper cree a l'etape 4).
Rancher pourrait theoriquement mapper automatiquement les groupes aux roles, mais cela
necessite de configurer `groupSearchEnabled: true` et des `GlobalRoleBindings` basees sur
les principaux de type groupe. La version actuelle utilise `accessMode: "unrestricted"`
ce qui laisse entrer tous les utilisateurs du realm sans restriction de groupe.

---

## Inspection des tokens (JWT)

### Obtenir un token OIDC

```bash
OIDC_SECRET=$(vault kv get -field=oidc_client_secret secret/services/keycloak)

# Token complet
TOKEN_RESPONSE=$(curl -sk -X POST \
    "https://keycloak.home.lo:8443/realms/rancher/protocol/openid-connect/token" \
    -d "client_id=rancher" \
    -d "client_secret=${OIDC_SECRET}" \
    -d "username=jniedergang" \
    -d "password=changeme" \
    -d "grant_type=password" \
    -d "scope=openid profile email")

# Extraire les differents tokens
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
ID_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id_token'])")
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['refresh_token'])")
```

### Decoder un JWT (sans verification de signature)

```bash
# Decoder le payload du access token
echo "$ACCESS_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool

# Decoder le ID token (contient le claim groups)
echo "$ID_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool
```

**Sortie attendue du ID token :**

```json
{
    "exp": 1741900000,
    "iat": 1741899700,
    "iss": "https://keycloak.home.lo:8443/realms/rancher",
    "sub": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "typ": "ID",
    "azp": "rancher",
    "preferred_username": "jniedergang",
    "given_name": "Julien",
    "family_name": "Niedergang",
    "email": "jniedergang@home.lo",
    "groups": [
        "rancher-admins"
    ]
}
```

**Verifier que le claim `groups` est present :**

```bash
echo "$ID_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | python3 -c "
import sys,json
d = json.load(sys.stdin)
groups = d.get('groups', [])
if groups:
    print(f'Groups claim present: {groups}')
else:
    print('WARNING: No groups claim in token!')
    print('Verifier le protocol mapper sur le client dans Keycloak')
"
```

### Introspection via Keycloak

```bash
# Introspection endpoint (verifie validite + ajoute les infos Keycloak)
curl -sk -X POST "https://keycloak.home.lo:8443/realms/rancher/protocol/openid-connect/token/introspect" \
    -d "client_id=rancher" \
    -d "client_secret=${OIDC_SECRET}" \
    -d "token=${ACCESS_TOKEN}" | python3 -m json.tool
```

### Userinfo endpoint

```bash
curl -sk -H "Authorization: Bearer $ACCESS_TOKEN" \
    "https://keycloak.home.lo:8443/realms/rancher/protocol/openid-connect/userinfo" | python3 -m json.tool
# Retourne : sub, preferred_username, groups, email, etc.
```

---

## Depannage detaille

### SLES 15 SP7 n'a pas de repos (impossible d'installer podman)

**Probleme :** L'image cloud SLES 15 SP7 minimale n'a aucun depot logiciel configure.
`zypper install podman` echoue avec "no repos defined".

**Solution :** Utiliser **openSUSE Leap 15.6** a la place. L'image cloud Leap a les repos
OSS actifs par defaut et podman est dans les repos standard. L'image doit etre importee
dans Harvester sous le nom `default/opensuse-leap-cloud`.

**Alternative (non recommandee) :** Ajouter les repos SCC ou MLM via cloud-init `runcmd`,
mais c'est plus complexe et necessite un enregistrement valide.

### Cloud-init DNS ne fonctionne pas sur openSUSE Leap

**Probleme :** Malgre la configuration `dns_nameservers: [172.16.3.6]` dans le network_data
cloud-init, la VM Leap utilise un autre serveur DNS (souvent le DHCP ou rien).

**Cause :** openSUSE/SLES utilise `netconfig` pour gerer `/etc/resolv.conf`. La configuration
reseau cloud-init passe par wicked, mais `netconfig` peut la surcharger selon la valeur de
`NETCONFIG_DNS_STATIC_SERVERS` dans `/etc/sysconfig/network/config`.

**Solution dans le cloud-init (runcmd) :**

```yaml
runcmd:
  - sed -i 's/^NETCONFIG_DNS_STATIC_SERVERS=.*/NETCONFIG_DNS_STATIC_SERVERS="172.16.3.6"/' /etc/sysconfig/network/config
  - netconfig update -f
```

Ceci force `172.16.3.6` comme DNS statique et regenere `/etc/resolv.conf`.

**Verification :**

```bash
ssh opensuse@172.16.3.12 "cat /etc/resolv.conf"
# Doit contenir : nameserver 172.16.3.6
```

### osixia/openldap utilise le port 389 en interne, 1389 en externe

**Probleme :** Confusion entre le port interne du conteneur (389) et le port mappe sur l'hote (1389).

**Detail :**
- Le conteneur `osixia/openldap:1.5.0` ecoute sur le port **389** a l'interieur du conteneur
- Le mapping Podman est `-p 127.0.0.1:1389:389` (hote:conteneur)
- Depuis l'**hote** (la VM), on utilise `ldap://127.0.0.1:1389`
- Depuis **Keycloak** (meme reseau Podman), on utilise `ldap://openldap:389` (nom DNS du conteneur, port interne)

**Erreur typique :** Configurer la federation Keycloak avec `ldap://openldap:1389` -> timeout car le conteneur n'ecoute PAS sur 1389.

### Keycloak health : port management 9000 vs port principal 8443

**Probleme :** `curl https://172.16.3.12:8443/health/ready` retourne 404 ou une page vide.

**Explication :** Keycloak 26.x separe le port **application** (8443) du port **management** (9000).
Les endpoints de health (`/health/ready`, `/health/live`, `/health/started`) ne sont servis que
sur le port management.

**Solutions :**

```bash
# Methode 1 : health sur le port management (local seulement, mappe sur 127.0.0.1:9000)
ssh opensuse@172.16.3.12 "curl -sk https://127.0.0.1:9000/health/ready"

# Methode 2 : verifier le realm master sur le port application (accessible de l'exterieur)
curl -sk https://172.16.3.12:8443/realms/master
# Si ca retourne du JSON avec "realm":"master", Keycloak est operationnel
```

Le script `06-verify.sh` essaie le port 9000 d'abord, puis fait un fallback sur le port 8443
en verifiant le realm master.

### Pi-hole v6 : format JSON non standard (Python workaround)

**Probleme :** `pihole-FTL --config dns.hosts` retourne un format qui ressemble a du JSON
mais n'en est pas : les valeurs ne sont pas quotees.

```
[ 172.16.3.6 pihole.home.lo, 172.16.0.1 gateway.home.lo ]
```

`jq` echoue sur ce format. `python3 -c "import json; json.loads(...)"` echoue aussi.

**Solution :** Le script utilise un parser Python ad-hoc qui :
1. Strip les crochets `[]`
2. Split sur les virgules
3. Traite chaque element comme `"IP hostname"`
4. Reconstruit un tableau JSON valide avec `json.dumps()`

Voir le code dans `03-configure-dns.sh` et `07-cleanup.sh`.

### API Rancher : keyCloakOIDCConfigs/keycloakoidc (pluriel avec ID)

**Probleme :** L'endpoint pour configurer Keycloak OIDC dans Rancher n'est pas intuitif.

**Detail :**

| Operation | Methode | Endpoint |
|-----------|---------|----------|
| Lire la config | GET | `/v3/authConfigs/keycloakoidc` |
| Modifier la config | PUT | `/v3/keyCloakOIDCConfigs/keycloakoidc` |
| Desactiver OIDC | POST | `/v3/keyCloakOIDCConfigs/keycloakoidc?action=disable` |

**Erreurs possibles :**
- `GET /v3/keyCloakOIDCConfig` (singulier, sans ID) -> 404
- `PUT /v3/authConfigs/keycloakoidc` -> 405 Method Not Allowed
- `PUT /v3/keyCloakOIDCConfigs` (sans l'ID `keycloakoidc`) -> 404

Le `type` dans le body JSON doit etre `"keyCloakOIDCConfig"` (singulier, CamelCase).

### Le CA doit etre dans les pods (tls-ca secret + privateCA=true)

**Probleme :** Apres avoir installe le CA sur la VM Rancher et relance les pods, le login
OIDC echoue avec `x509: certificate signed by unknown authority`.

**Explication :** Les pods Rancher utilisent leur propre trust store (celui de l'image conteneur
distroless), pas celui de la VM hote. Installer le CA dans `/etc/pki/trust/anchors/` ne suffit
**pas** pour les pods.

**Solution en 2 etapes :**

1. Creer un secret Kubernetes `tls-ca` dans `cattle-system` contenant le CA :
   ```bash
   kubectl -n cattle-system create secret generic tls-ca --from-file=cacerts.pem=keycloak-ca.crt
   ```

2. Activer `privateCA=true` dans les values Helm de Rancher :
   ```bash
   helm upgrade rancher rancher-prime/rancher -n cattle-system \
       --set privateCA=true \
       ... (tous les autres set)
   ```

Rancher monte automatiquement le secret `tls-ca` dans les pods quand `privateCA=true`.
Le fichier `cacerts.pem` est lu au demarrage et ajoute au trust store Go.

**Verification :**

```bash
# Verifier que le secret existe
kubectl -n cattle-system get secret tls-ca
# NAME     TYPE     DATA   AGE
# tls-ca   Opaque   1      Xm

# Verifier que le pod peut joindre Keycloak avec TLS
kubectl exec -n cattle-system deploy/rancher -- \
    curl -sf https://keycloak.home.lo:8443/realms/rancher/.well-known/openid-configuration
```

### Conflit Helm / kubectl patch (startupProbe.failureThreshold)

**Probleme :** Si vous avez modifie la `startupProbe.failureThreshold` du deployment Rancher
via `kubectl patch` (par exemple pour debloquer un restart loop), le prochain `helm upgrade`
echoue avec un conflit car Helm detecte que les valeurs ont change hors de son controle.

**Solution :** Toujours passer `--set startupProbe.failureThreshold=60` dans TOUS les
`helm upgrade`. Ceci evite le conflit et garantit une valeur suffisante.

```bash
helm upgrade rancher rancher-prime/rancher -n cattle-system \
    --set hostname=rancher.home.zypp.fr \
    --set tls=external \
    --set privateCA=true \
    --set replicas=1 \
    --set systemDefaultRegistry=registry.rancher.com \
    --set global.cattle.psp.enabled=false \
    --set startupProbe.failureThreshold=60
```

**Si le conflit persiste :**

```bash
# Verifier les valeurs Helm actuelles
helm get values rancher -n cattle-system

# Voir le manifest rendu
helm get manifest rancher -n cattle-system | grep -A 5 startupProbe
```

### Les utilisateurs OIDC n'ont aucun role apres le premier login

**Probleme :** Un utilisateur se connecte avec succes via Keycloak, mais ne voit aucun
cluster ni aucune ressource dans Rancher.

**Explication :** Rancher cree l'utilisateur dans sa base interne au premier login OIDC,
mais ne lui assigne aucun role global ni aucun cluster role. C'est par design : l'admin
doit explicitement attribuer les permissions.

**Solution :** Voir la section [Groupes et RBAC Rancher](#groupes-et-rbac-rancher).

### Le claim `groups` via protocol mapper, pas via scope

**Probleme :** Le token OIDC ne contient pas le claim `groups` malgre la configuration LDAP.

**Explication :** Avoir un LDAP group mapper (etape 4.4) synchronise les groupes LDAP vers
Keycloak, mais ne les injecte **pas** dans le token JWT. Il faut un **protocol mapper**
de type `oidc-group-membership-mapper` configure sur le **client** OIDC (pas dans un scope global).

**Verification :**

```bash
# Decoder le token et chercher "groups"
echo "$ID_TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('groups', 'ABSENT!'))"

# Si ABSENT, verifier le mapper dans Keycloak
TOKEN=$(... get admin token ...)
CLIENT_UUID=$(... get client UUID ...)
curl -sk -H "Authorization: Bearer $TOKEN" \
    "https://keycloak.home.lo:8443/admin/realms/rancher/clients/$CLIENT_UUID/protocol-mappers/models" | \
    python3 -c "import sys,json; [print(m['name'], m['protocolMapper']) for m in json.load(sys.stdin)]"
# Doit afficher : groups oidc-group-membership-mapper
```

### directAccessGrantsEnabled necessaire pour le password grant

**Probleme :** Le test `curl` avec `grant_type=password` echoue avec
`"error": "unauthorized_client"`.

**Explication :** Le Direct Access Grant (Resource Owner Password Credentials) doit etre
explicitement active sur le client OIDC. C'est un flow OAuth2 qui permet l'authentification
directe par username/password sans redirect navigateur.

**Solution :** Verifier que `directAccessGrantsEnabled: true` dans la config du client :

```bash
TOKEN=$(... get admin token ...)
CLIENT_UUID=$(... get client UUID ...)
curl -sk -H "Authorization: Bearer $TOKEN" \
    "https://keycloak.home.lo:8443/admin/realms/rancher/clients/$CLIENT_UUID" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('directAccessGrantsEnabled'))"
# Doit afficher : True
```

Ce flag est active par defaut dans le script `04-configure-keycloak-ldap.sh`.

### Keycloak ne demarre pas (logs)

```bash
ssh opensuse@172.16.3.12 "sudo podman logs keycloak 2>&1 | tail -50"
```

Erreurs courantes dans les logs :
- `Cannot read property 'tls.crt'` : le volume mount TLS est incorrect
- `Failed to obtain JDBC connection` : Keycloak utilise H2 en embedded, pas de DB externe requise
- `KC_HOSTNAME` must include port : utiliser `https://keycloak.home.lo:8443` (avec le port)

### Rancher ne redirige pas vers Keycloak (pas de bouton "Log in with Keycloak")

Verifier que l'OIDC est bien active :

```bash
curl -sk https://rancher.home.zypp.fr/v3/authConfigs/keycloakoidc | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(f'enabled={d[\"enabled\"]}')"
```

Si `enabled=False`, relancer le script `05-configure-rancher-oidc.sh`.

---

## Interface web

Une interface web optionnelle permet d'executer les etapes visuellement :

```bash
cd /home/ju/workspace/rancher-poc/extra/keycloak/ui
python3 app.py
# Accessible sur http://localhost:8092
```

**Pre-requis :** Flask (`pip install flask`)

**Service systemd (optionnel) :**

```bash
# Installer le service utilisateur
cp ui/keycloak-ui.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now keycloak-ui.service
```

**Fonctionnalites :**
- Cartes par etape avec statut (vert = OK, gris = pas execute, rouge = erreur)
- Details de chaque etape (description, commandes manuelles, variables)
- Execution des scripts avec console SSE (Server-Sent Events) en temps reel
- Rafraichissement automatique du statut
- Bouton nettoyage avec confirmation

**URL :** http://localhost:8092 (ou http://node1:8092 depuis le reseau)

---

## Variables

Toutes les variables sont dans `keycloak-vars.sh`. Les secrets sont dans Vault
(`secret/services/keycloak`).

| Variable | Valeur par defaut | Description |
|----------|-------------------|-------------|
| `KC_VM_HOST` | `172.16.3.12` | IP de la VM IDP |
| `KC_VM_SSH_USER` | `opensuse` | Utilisateur SSH de la VM |
| `LDAP_CONTAINER_NAME` | `openldap` | Nom du conteneur OpenLDAP (= DNS Podman) |
| `LDAP_IMAGE` | `docker.io/osixia/openldap:1.5.0` | Image OpenLDAP |
| `LDAP_PORT` | `1389` | Port LDAP cote hote (mappe sur 389 dans le conteneur) |
| `LDAP_DOMAIN` | `home.lo` | Domaine LDAP |
| `LDAP_BASE_DN` | `dc=home,dc=lo` | Base DN LDAP |
| `LDAP_ADMIN_USER` | `admin` | Utilisateur admin LDAP |
| `LDAP_ORG_NAME` | `Homelab` | Nom d'organisation LDAP |
| `KC_CONTAINER_NAME` | `keycloak` | Nom du conteneur Keycloak |
| `KC_IMAGE` | `quay.io/keycloak/keycloak:26.2` | Image Keycloak |
| `KC_HTTPS_PORT` | `8443` | Port HTTPS Keycloak (application) |
| `KC_FQDN` | `keycloak.home.lo` | FQDN Keycloak (dans le cert et l'URL) |
| `KC_REALM` | `rancher` | Nom du realm Keycloak |
| `KC_ADMIN_USER` | `admin` | Utilisateur admin Keycloak |
| `KC_PODMAN_NETWORK` | `keycloak-net` | Reseau Podman partage |
| `RANCHER_URL` | `https://rancher.home.zypp.fr` | URL Rancher Manager |
| `RANCHER_OIDC_CLIENT_ID` | `rancher` | Client ID OIDC dans Keycloak |
| `RANCHER_VM_HOST` | `172.16.3.20` | IP de la VM Rancher |
| `RANCHER_VM_SSH_USER` | `rancher` | Utilisateur SSH de la VM Rancher |
| `PIHOLE_HOST` | `172.16.3.6` | IP de rasp01 (Pi-hole) |
| `PIHOLE_SSH_USER` | `ju` | Utilisateur SSH de rasp01 |
| `PIHOLE_CONTAINER` | `b41a7dff114c_pihole` | Nom du conteneur Pi-hole |
| `VAULT_KC_SECRET_PATH` | `secret/services/keycloak` | Chemin Vault pour les secrets |

**Secrets Vault (secret/services/keycloak) :**

| Cle | Description |
|-----|-------------|
| `admin_password` | Mot de passe admin Keycloak |
| `ldap_admin_password` | Mot de passe admin OpenLDAP |
| `oidc_client_secret` | Secret du client OIDC (UUID, partage entre Keycloak et Rancher) |
