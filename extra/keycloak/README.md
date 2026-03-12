# Keycloak + OpenLDAP — Rancher OIDC Authentication

Extra pour rancher-poc : deploie Keycloak + OpenLDAP sur une VM dediee et configure
l'authentification OIDC dans Rancher Manager.

## Architecture

```
                  +--------------------------+
                  |  VM idp (172.16.3.12)    |
                  |  SLES 15 SP7 / Podman    |
                  |                          |
                  |  +--------+  +--------+  |
                  |  |OpenLDAP|  |Keycloak|  |
                  |  |  :1389 |←-|  :8443 |  |
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

- **OpenLDAP** : annuaire LDAP avec OUs, groupes et utilisateurs de demo
- **Keycloak** : IdP OIDC avec federation LDAP, realm `rancher`, client OIDC
- **Rancher** : authentification externe via `keyCloakOIDCConfig`

## DNS (Pi-hole)

| Hostname | IP |
|----------|-----|
| idp.home.lo | 172.16.3.12 |
| keycloak.home.lo | 172.16.3.12 |
| ldap.home.lo | 172.16.3.12 |

## Pre-requis

- Harvester HCI operationnel avec image SLES 15 SP7 (`default/image-nhtf9`)
- Terraform installe avec le provider Harvester
- HashiCorp Vault accessible avec les secrets configures :
  - `secret/services/keycloak` : `admin_password`, `ldap_admin_password`, `oidc_client_secret`
- Rancher Manager fonctionnel (https://rancher.home.zypp.fr)
- Pi-hole DNS accessible (172.16.3.6)
- Acces SSH depuis node1

### Creer les secrets Vault

```bash
# Adapter les valeurs
vault kv put secret/services/keycloak \
    admin_password="<keycloak-admin-password>" \
    ldap_admin_password="<ldap-admin-password>" \
    oidc_client_secret="<generated-uuid>"
```

## Etape 0 : Provisionner la VM

```bash
cd /home/ju/workspace/TERRAFORM/KEYCLOAK
terraform init
terraform plan
terraform apply
```

Verifier :

```bash
ssh sles@172.16.3.12 hostname
# idp
ssh sles@172.16.3.12 podman --version
```

Specs VM : 2 vCPU, 4 Gi RAM, 40 Gi disque, SLES 15 SP7

## Etape 1 : Deployer OpenLDAP

```bash
cd /home/ju/workspace/rancher-poc/extra/keycloak
bash 01-deploy-openldap.sh
```

Le script :
- Genere les fichiers LDIF a partir des templates (`templates/`)
- Cree le reseau Podman `keycloak-net`
- Deploie bitnami/openldap:2.6 sur `127.0.0.1:1389`
- Injecte les OUs, groupes et utilisateurs

Verification :

```bash
ssh sles@172.16.3.12 "ldapsearch -x -H ldap://127.0.0.1:1389 \
    -D 'cn=admin,dc=home,dc=lo' -w <vault> -b 'dc=home,dc=lo' '(uid=*)'"
```

### Personnaliser les utilisateurs

Editer `keycloak-vars.sh` :

```bash
LDAP_GROUPS=("rancher-admins" "rancher-users" "rancher-readonly")
LDAP_DEMO_USERS=(
    "jniedergang:Julien:Niedergang:rancher-admins"
    "demouser:Demo:User:rancher-users"
    "viewer:Read:Only:rancher-readonly"
)
```

Format : `uid:prenom:nom:groupe`

## Etape 2 : Deployer Keycloak

```bash
bash 02-deploy-keycloak.sh
```

Le script :
- Genere un certificat self-signed pour `keycloak.home.lo`
- Deploie Keycloak 26.2 en HTTPS sur le port 8443
- Sauvegarde le certificat dans `.certs/keycloak-ca.crt` (utilise plus tard)
- Attend le health check `/health/ready`

Verification :

```bash
curl -sk https://172.16.3.12:8443/health/ready
# {"status":"UP",...}
```

## Etape 3 : Configurer le DNS

```bash
bash 03-configure-dns.sh
```

Ajoute 3 entrees dans Pi-hole (idp, keycloak, ldap.home.lo) pointant vers 172.16.3.12.

Verification :

```bash
dig keycloak.home.lo @172.16.3.6
# 172.16.3.12
```

## Etape 4 : Configurer Keycloak

```bash
bash 04-configure-keycloak-ldap.sh
```

Via l'API Admin REST de Keycloak :
1. Cree le realm `rancher`
2. Configure la federation LDAP (ldap://openldap:1389 via le reseau Podman)
3. Ajoute un group mapper LDAP -> Keycloak
4. Declenche la synchro LDAP
5. Cree le client OIDC `rancher` (confidential)
6. Ajoute un protocol mapper `groups` dans le token ID

Verification :

```bash
curl -sk https://keycloak.home.lo:8443/realms/rancher/.well-known/openid-configuration
```

## Etape 5 : Integrer Rancher OIDC

```bash
bash 05-configure-rancher-oidc.sh
```

Le script :
1. Copie le CA self-signed sur la VM Rancher (`/etc/pki/trust/anchors/`)
2. Execute `update-ca-certificates` et redémarre les pods Rancher
3. Configure `keyCloakOIDCConfig` via l'API Rancher v3

**Important** : Rancher doit pouvoir joindre `keycloak.home.lo:8443` et truster
le certificat self-signed. Le script gere les deux.

## Verification end-to-end

```bash
bash 06-verify.sh
```

Ou manuellement :

```bash
# 1. VM et conteneurs
ssh sles@172.16.3.12 "sudo podman ps"

# 2. LDAP
ssh sles@172.16.3.12 "ldapsearch -x -H ldap://127.0.0.1:1389 \
    -D 'cn=admin,dc=home,dc=lo' -w <vault> -b 'dc=home,dc=lo' '(uid=*)'"

# 3. OIDC discovery
curl -sk https://keycloak.home.lo:8443/realms/rancher/.well-known/openid-configuration

# 4. Rancher OIDC
curl -sk -H "Authorization: Bearer $TOKEN" \
    https://rancher.home.zypp.fr/v3/keyCloakOIDCConfig | grep '"enabled":true'

# 5. Test login : ouvrir https://rancher.home.zypp.fr -> "Log in with Keycloak"
#    Credentials : jniedergang / changeme (groupe rancher-admins)
```

## Nettoyage

```bash
bash 07-cleanup.sh
```

Desactive OIDC dans Rancher, supprime les conteneurs, retire les entrees DNS.
Pour detruire la VM :

```bash
cd /home/ju/workspace/TERRAFORM/KEYCLOAK
terraform destroy
```

## Depannage

### Rancher ne peut pas joindre Keycloak

Verifier que le CA est installe et que les pods ont ete redeployes :

```bash
ssh rancher@172.16.3.20 "ls /etc/pki/trust/anchors/keycloak-ca.crt"
ssh rancher@172.16.3.20 "curl -sk https://keycloak.home.lo:8443/health/ready"
```

Si le curl echoue depuis la VM Rancher, verifier le DNS :

```bash
ssh rancher@172.16.3.20 "dig keycloak.home.lo"
```

### Token admin Keycloak expire

Les tokens expirent apres 60 secondes. Le script 04 rafraichit le token entre chaque operation.

### LDAP sync ne remonte pas les utilisateurs

Verifier la connectivite LDAP depuis le conteneur Keycloak :

```bash
ssh sles@172.16.3.12 "sudo podman exec keycloak curl -s ldap://openldap:1389"
```

Le nom `openldap` est resolu via le reseau Podman `keycloak-net`.

### Erreur "no endpoints available for service" au Helm install

Sans rapport avec ce extra — voir la doc principale de rancher-poc.

## Interface web

Une interface web optionnelle permet d'executer les etapes visuellement :

```bash
cd extra/keycloak/ui
python3 app.py
# Accessible sur http://localhost:8092
```

Fonctionnalites :
- Cartes par etape avec statut (vert/gris/rouge)
- Details de chaque etape (description, commandes manuelles, variables)
- Execution des scripts avec console SSE en temps reel
- Rafraichissement automatique du statut

## Variables

Toutes les variables sont dans `keycloak-vars.sh`. Les secrets sont dans Vault
(`secret/services/keycloak`).

| Variable | Valeur par defaut | Description |
|----------|-------------------|-------------|
| KC_VM_HOST | 172.16.3.12 | IP de la VM IDP |
| LDAP_PORT | 1389 | Port LDAP (localhost) |
| LDAP_BASE_DN | dc=home,dc=lo | Base DN LDAP |
| KC_HTTPS_PORT | 8443 | Port HTTPS Keycloak |
| KC_FQDN | keycloak.home.lo | FQDN Keycloak |
| KC_REALM | rancher | Nom du realm |
| RANCHER_URL | https://rancher.home.zypp.fr | URL Rancher |
