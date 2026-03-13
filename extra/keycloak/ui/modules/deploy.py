"""Deploy blueprint — Keycloak + OpenLDAP deployment steps."""

import json
import subprocess
from pathlib import Path
from flask import Blueprint, jsonify, Response, stream_with_context

deploy_bp = Blueprint('deploy', __name__)

SCRIPT_DIR = Path(__file__).resolve().parent.parent.parent
STATE_FILE = Path(__file__).resolve().parent.parent / 'state.json'

STEPS = [
    {
        "id": "terraform",
        "title": "Provisionner la VM",
        "script": None,
        "check": "ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 opensuse@172.16.3.12 hostname",
        "description": "Cree la VM 'idp' (172.16.3.12) sur Harvester via Terraform. "
                       "2 vCPU, 4 Gi RAM, 40 Gi disque, SLES 15 SP7.",
        "manual_commands": [
            "cd /home/ju/workspace/TERRAFORM/KEYCLOAK",
            "terraform init",
            "terraform plan",
            "terraform apply",
            "ssh opensuse@172.16.3.12 hostname",
        ],
        "variables": ["VM IP: 172.16.3.12", "Image: SLES 15 SP7 (image-nhtf9)", "Reseau: default/production"],
        "doc": """
<h4>Description</h4>
<p>Cette etape provisionne la VM <strong>idp</strong> sur le cluster Harvester via Terraform.
La VM utilise l'image SLES 15 SP7 minimale cloud et est configuree avec cloud-init
pour l'utilisateur <code>opensuse</code>, l'injection de cles SSH et la configuration reseau statique.</p>
<p>Le provider Terraform Harvester cree la VM via l'API KubeVirt, avec un volume racine
de 40 Gi base sur l'image cloud SLES 15 SP7 (image-nhtf9). Le cloud-init configure le hostname,
le reseau statique (172.16.3.12/16), et les cles SSH autorisees.</p>

<h4>Variables utilisees</h4>
<ul>
<li><strong>VM IP</strong> : 172.16.3.12 (statique, defini dans le plan Terraform)</li>
<li><strong>Image</strong> : SLES 15 SP7 (image-nhtf9) — image cloud minimale pre-chargee dans Harvester</li>
<li><strong>Reseau</strong> : default/production (bridge network sur mgmt cluster network)</li>
<li><strong>CPU</strong> : 2 vCPU</li>
<li><strong>RAM</strong> : 4 Gi</li>
<li><strong>Disque</strong> : 40 Gi</li>
<li><strong>SSH user</strong> : opensuse</li>
</ul>

<h4>Commandes manuelles equivalentes</h4>
<code>cd /home/ju/workspace/TERRAFORM/KEYCLOAK
terraform init
terraform plan
terraform apply -auto-approve</code>

<h4>Verification</h4>
<code># Verifier que la VM repond au SSH
ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 opensuse@172.16.3.12 hostname
# Sortie attendue : idp

# Verifier l'etat de la VM sur Harvester
ssh rancher@172.16.3.11 "sudo /var/lib/rancher/rke2/bin/kubectl \\
  --kubeconfig /etc/rancher/rke2/rke2.yaml get vm idp -n default"
# Sortie attendue : idp   Running   ...

# Verifier l'IP assignee
ssh opensuse@172.16.3.12 "ip addr show eth0 | grep 'inet '"
# Sortie attendue : inet 172.16.3.12/16 ...</code>

<h4>Erreurs courantes et solutions</h4>
<ul>
<li><strong>Terraform provider introuvable</strong> : Verifier que le provider harvester est installe dans
<code>~/.terraform.d/plugins/</code>. Utiliser le provider custom compile depuis
<code>/home/ju/workspace/terraform-provider-harvester/</code>.</li>
<li><strong>Image non trouvee</strong> : Verifier que <code>image-nhtf9</code> existe sur Harvester :
<code>kubectl get virtualmachineimages -n default</code>.</li>
<li><strong>Cloud-init trop grand</strong> : KubeVirt limite le cloud-init inline a 2048 bytes.
Utiliser <code>harvester_cloudinit_secret</code> + <code>user_data_secret_name</code> si necessaire.</li>
<li><strong>VM ne boot pas</strong> : Verifier les PVC (<code>kubectl get pvc -n default</code>) et les events
(<code>kubectl describe vm idp -n default</code>).</li>
<li><strong>SSH refuse la connexion</strong> : Attendre 1-2 minutes apres le boot. Si le probleme persiste,
supprimer l'ancien host key avec <code>ssh-keygen -R 172.16.3.12</code>.</li>
</ul>

<h4>Tips de debug</h4>
<ul>
<li>Utiliser <code>terraform plan</code> avant <code>apply</code> pour verifier les changements.</li>
<li>Les logs de cloud-init sont dans <code>/var/log/cloud-init-output.log</code> sur la VM.</li>
<li>Si la VM est bloquee, inspecter la console via la VNC Harvester UI (https://172.16.3.100).</li>
<li>Pour recreer la VM, supprimer l'ancien PVC orphelin : <code>kubectl delete pvc &lt;pvc-name&gt; -n default</code>.</li>
</ul>
""",
    },
    {
        "id": "openldap",
        "title": "Deployer OpenLDAP",
        "script": "01-deploy-openldap.sh",
        "check": "ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 opensuse@172.16.3.12 'sudo podman ps --format {{.Names}} | grep openldap'",
        "description": "Deploie le conteneur OpenLDAP (bitnami/openldap:2.6) sur la VM. "
                       "Cree les OUs, groupes et utilisateurs de demo via LDIF.",
        "manual_commands": [
            "# Sur la VM (ssh opensuse@172.16.3.12) :",
            "sudo podman network create keycloak-net",
            "sudo podman run -d --name openldap --network keycloak-net "
            "-p 127.0.0.1:1389:1389 -e LDAP_ROOT='dc=home,dc=lo' "
            "-e LDAP_ADMIN_USERNAME=admin -e LDAP_ADMIN_PASSWORD=<vault> "
            "-v /tmp/ldap-init:/ldifs:Z docker.io/bitnami/openldap:2.6",
            "ldapsearch -x -H ldap://127.0.0.1:1389 -D 'cn=admin,dc=home,dc=lo' -w <vault> -b 'dc=home,dc=lo' '(uid=*)'",
        ],
        "variables": ["Base DN: dc=home,dc=lo", "Port: 1389 (localhost only)", "Groupes: rancher-admins, rancher-users, rancher-readonly"],
        "doc": """
<h4>Description</h4>
<p>Deploie un conteneur <strong>OpenLDAP</strong> (bitnami/openldap:2.6) sur la VM idp via Podman.
Le script cree un reseau Podman dedie (<code>keycloak-net</code>), lance le conteneur OpenLDAP avec la
configuration du domaine <code>dc=home,dc=lo</code>, puis injecte les donnees initiales via des fichiers LDIF :</p>
<ul>
<li><strong>OUs</strong> : People, Groups</li>
<li><strong>Groupes</strong> : rancher-admins, rancher-users, rancher-readonly</li>
<li><strong>Utilisateurs de demo</strong> : admin-user, dev-user, readonly-user (avec mots de passe depuis Vault)</li>
</ul>
<p>Le port LDAP (1389) est expose uniquement sur localhost — seul Keycloak (via le reseau Podman interne)
y accede. Les mots de passe sont recuperes depuis HashiCorp Vault (<code>secret/services/keycloak</code>).</p>

<h4>Variables utilisees</h4>
<ul>
<li><strong>LDAP_ROOT</strong> : dc=home,dc=lo</li>
<li><strong>LDAP_ADMIN_USERNAME</strong> : admin</li>
<li><strong>LDAP_ADMIN_PASSWORD</strong> : depuis Vault <code>secret/services/keycloak ldap_admin_password</code></li>
<li><strong>Port</strong> : 1389 (bind 127.0.0.1 uniquement)</li>
<li><strong>Reseau Podman</strong> : keycloak-net</li>
<li><strong>Image</strong> : docker.io/bitnami/openldap:2.6</li>
<li><strong>Volume LDIF</strong> : /tmp/ldap-init (fichiers .ldif copies sur la VM)</li>
</ul>

<h4>Commandes manuelles equivalentes</h4>
<code># Connexion SSH a la VM
ssh opensuse@172.16.3.12

# Creer le reseau Podman
sudo podman network create keycloak-net

# Lancer OpenLDAP
sudo podman run -d --name openldap --network keycloak-net \\
  -p 127.0.0.1:1389:1389 \\
  -e LDAP_ROOT='dc=home,dc=lo' \\
  -e LDAP_ADMIN_USERNAME=admin \\
  -e LDAP_ADMIN_PASSWORD='***' \\
  -v /tmp/ldap-init:/ldifs:Z \\
  docker.io/bitnami/openldap:2.6

# Importer les LDIF manuellement (si pas auto-charge)
ldapadd -x -H ldap://127.0.0.1:1389 \\
  -D 'cn=admin,dc=home,dc=lo' -w '***' \\
  -f /tmp/ldap-init/01-ous.ldif</code>

<h4>Verification</h4>
<code># Verifier que le conteneur tourne
ssh opensuse@172.16.3.12 'sudo podman ps --format "{{.Names}} {{.Status}}" | grep openldap'
# Sortie attendue : openldap Up X minutes

# Lister les utilisateurs LDAP
ssh opensuse@172.16.3.12 'ldapsearch -x -H ldap://127.0.0.1:1389 \\
  -D "cn=admin,dc=home,dc=lo" -w "***" \\
  -b "ou=People,dc=home,dc=lo" "(uid=*)" uid cn'
# Sortie attendue : 3 entries (admin-user, dev-user, readonly-user)

# Lister les groupes
ssh opensuse@172.16.3.12 'ldapsearch -x -H ldap://127.0.0.1:1389 \\
  -D "cn=admin,dc=home,dc=lo" -w "***" \\
  -b "ou=Groups,dc=home,dc=lo" "(cn=*)" cn member'
# Sortie attendue : 3 entries (rancher-admins, rancher-users, rancher-readonly)</code>

<h4>Erreurs courantes et solutions</h4>
<ul>
<li><strong>Port 1389 deja utilise</strong> : Un ancien conteneur tourne encore.
<code>sudo podman rm -f openldap</code> puis relancer.</li>
<li><strong>LDIF import echoue</strong> : Verifier la syntaxe des fichiers LDIF. Les lignes vides
separent les entries, pas de trailing spaces.</li>
<li><strong>Reseau keycloak-net existe deja</strong> : Normal si relance.
<code>sudo podman network rm keycloak-net</code> si besoin de recreer.</li>
<li><strong>"already exists" sur podman run</strong> : <code>sudo podman rm -f openldap</code> avant de relancer.</li>
</ul>

<h4>Tips de debug</h4>
<ul>
<li>Logs du conteneur : <code>sudo podman logs openldap</code></li>
<li>Tester la connexion LDAP en local : <code>ldapsearch -x -H ldap://127.0.0.1:1389 -D "cn=admin,dc=home,dc=lo" -w '***' -b "" -s base</code></li>
<li>Pour reinitialiser completement : <code>sudo podman rm -f openldap && sudo podman volume prune</code></li>
<li>Les LDIF sont idempotents — si un entry existe deja, utiliser <code>ldapmodify</code> au lieu de <code>ldapadd</code>.</li>
</ul>
""",
    },
    {
        "id": "keycloak",
        "title": "Deployer Keycloak",
        "script": "02-deploy-keycloak.sh",
        "check": "curl -sk https://172.16.3.12:8443/health/ready 2>/dev/null | grep -q UP",
        "description": "Deploie Keycloak 26.2 en HTTPS (cert self-signed) sur le port 8443. "
                       "Le certificat est genere automatiquement pour keycloak.home.lo.",
        "manual_commands": [
            "# Sur la VM :",
            "openssl req -x509 -newkey rsa:2048 -nodes -keyout tls.key -out tls.crt "
            "-days 365 -subj '/CN=keycloak.home.lo' -addext 'subjectAltName=DNS:keycloak.home.lo,IP:172.16.3.12'",
            "sudo podman run -d --name keycloak --network keycloak-net "
            "-p 0.0.0.0:8443:8443 "
            "-e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=<vault> "
            "-e KC_HOSTNAME='https://keycloak.home.lo:8443' -e KC_HEALTH_ENABLED=true "
            "-v ./tls.crt:/opt/keycloak/conf/tls.crt:Z -v ./tls.key:/opt/keycloak/conf/tls.key:Z "
            "quay.io/keycloak/keycloak:26.2 start",
        ],
        "variables": ["FQDN: keycloak.home.lo", "Port HTTPS: 8443", "Image: keycloak:26.2"],
        "doc": """
<h4>Description</h4>
<p>Deploie <strong>Keycloak 26.2</strong> en mode production HTTPS sur le port 8443. Le script :</p>
<ol>
<li>Genere un certificat TLS self-signed (RSA 2048) avec SAN pour <code>keycloak.home.lo</code> et l'IP <code>172.16.3.12</code></li>
<li>Copie le certificat et la cle sur la VM</li>
<li>Lance le conteneur Keycloak sur le reseau Podman <code>keycloak-net</code> (partage avec OpenLDAP)</li>
<li>Configure le hostname Keycloak, active le health check, et cree le compte admin bootstrap</li>
</ol>
<p>Le certificat genere est aussi sauvegarde localement dans <code>.certs/</code> pour etre installe
ulterieurement sur la VM Rancher (etape 5).</p>

<h4>Variables utilisees</h4>
<ul>
<li><strong>KC_HOSTNAME</strong> : https://keycloak.home.lo:8443</li>
<li><strong>KC_BOOTSTRAP_ADMIN_USERNAME</strong> : admin</li>
<li><strong>KC_BOOTSTRAP_ADMIN_PASSWORD</strong> : depuis Vault <code>secret/services/keycloak admin_password</code></li>
<li><strong>KC_HEALTH_ENABLED</strong> : true</li>
<li><strong>Port</strong> : 8443 (HTTPS, bind 0.0.0.0)</li>
<li><strong>Reseau Podman</strong> : keycloak-net</li>
<li><strong>Image</strong> : quay.io/keycloak/keycloak:26.2</li>
<li><strong>Cert CN</strong> : keycloak.home.lo</li>
<li><strong>Cert SAN</strong> : DNS:keycloak.home.lo, IP:172.16.3.12</li>
</ul>

<h4>Commandes manuelles equivalentes</h4>
<code># Generer le certificat TLS self-signed
openssl req -x509 -newkey rsa:2048 -nodes \\
  -keyout tls.key -out tls.crt -days 365 \\
  -subj '/CN=keycloak.home.lo' \\
  -addext 'subjectAltName=DNS:keycloak.home.lo,IP:172.16.3.12'

# Copier les certs sur la VM
scp tls.crt tls.key opensuse@172.16.3.12:/tmp/

# Sur la VM :
ssh opensuse@172.16.3.12

sudo podman run -d --name keycloak --network keycloak-net \\
  -p 0.0.0.0:8443:8443 \\
  -e KC_BOOTSTRAP_ADMIN_USERNAME=admin \\
  -e KC_BOOTSTRAP_ADMIN_PASSWORD='***' \\
  -e KC_HOSTNAME='https://keycloak.home.lo:8443' \\
  -e KC_HEALTH_ENABLED=true \\
  -e KC_HTTPS_CERTIFICATE_FILE=/opt/keycloak/conf/tls.crt \\
  -e KC_HTTPS_CERTIFICATE_KEY_FILE=/opt/keycloak/conf/tls.key \\
  -v /tmp/tls.crt:/opt/keycloak/conf/tls.crt:Z \\
  -v /tmp/tls.key:/opt/keycloak/conf/tls.key:Z \\
  quay.io/keycloak/keycloak:26.2 start</code>

<h4>Verification</h4>
<code># Health check (depuis n'importe ou)
curl -sk https://172.16.3.12:8443/health/ready
# Sortie attendue : {"status":"UP","checks":[...]}

# Verifier que le conteneur tourne
ssh opensuse@172.16.3.12 'sudo podman ps | grep keycloak'
# Sortie attendue : keycloak   Up X minutes

# Tester la page de login
curl -sk -o /dev/null -w "%{http_code}" https://keycloak.home.lo:8443/
# Sortie attendue : 200

# Verifier le certificat
openssl s_client -connect 172.16.3.12:8443 -servername keycloak.home.lo </dev/null 2>/dev/null | openssl x509 -noout -subject -dates
# Sortie attendue : subject=CN = keycloak.home.lo</code>

<h4>Erreurs courantes et solutions</h4>
<ul>
<li><strong>Port 8443 deja utilise</strong> : <code>sudo podman rm -f keycloak</code> puis relancer.</li>
<li><strong>Keycloak ne demarre pas (health DOWN)</strong> : Verifier les logs avec
<code>sudo podman logs keycloak</code>. Souvent un probleme de certificat (fichier introuvable, permissions).</li>
<li><strong>Certificat invalide / SAN manquant</strong> : Regenerer avec l'option <code>-addext</code>.
Les anciens OpenSSL (&lt;1.1.1) ne supportent pas <code>-addext</code>, utiliser un fichier de config.</li>
<li><strong>"Failed to obtain JDBC connection"</strong> : Keycloak utilise H2 en embedded par defaut,
pas de base externe requise pour ce setup.</li>
</ul>

<h4>Tips de debug</h4>
<ul>
<li>Logs verbeux : <code>sudo podman logs -f keycloak</code></li>
<li>Keycloak met ~30-60s a demarrer. Le health check peut retourner DOWN pendant ce temps.</li>
<li>L'admin UI est accessible a <code>https://keycloak.home.lo:8443/admin/</code></li>
<li>Pour reinitialiser Keycloak : <code>sudo podman rm -f keycloak</code> (les donnees sont dans le conteneur, pas de volume persistant).</li>
</ul>
""",
    },
    {
        "id": "dns",
        "title": "Configurer DNS",
        "script": "03-configure-dns.sh",
        "check": "dig +short idp.home.lo @172.16.3.6 2>/dev/null | grep -q 172.16.3.12",
        "description": "Ajoute 3 entrees DNS dans Pi-hole : "
                       "idp.home.lo, keycloak.home.lo, ldap.home.lo -> 172.16.3.12",
        "manual_commands": [
            "ssh ju@172.16.3.6 \"docker exec b41a7dff114c_pihole pihole-FTL --config dns.hosts\"",
            "# Ajouter les entrees a la liste JSON existante",
            "ssh ju@172.16.3.6 \"docker exec b41a7dff114c_pihole pihole-FTL --config dns.hosts '<new_json>'\"",
            "dig idp.home.lo @172.16.3.6",
        ],
        "variables": ["Pi-hole: 172.16.3.6", "DNS entries: idp/keycloak/ldap.home.lo -> 172.16.3.12"],
        "doc": """
<h4>Description</h4>
<p>Configure les entrees DNS dans <strong>Pi-hole v6</strong> (rasp01, 172.16.3.6) pour que les noms
<code>idp.home.lo</code>, <code>keycloak.home.lo</code> et <code>ldap.home.lo</code> pointent vers la VM
172.16.3.12. Le script :</p>
<ol>
<li>Recupere la liste actuelle des entrees DNS custom depuis Pi-hole</li>
<li>Ajoute les 3 nouvelles entrees (sans doublons)</li>
<li>Met a jour la configuration Pi-hole via <code>pihole-FTL --config</code></li>
</ol>
<p>Pi-hole v6 utilise <code>pihole-FTL --config dns.hosts</code> avec un tableau JSON.
Les fichiers <code>custom.list</code> sont auto-generes — ne pas les editer directement.</p>

<h4>Variables utilisees</h4>
<ul>
<li><strong>Pi-hole host</strong> : 172.16.3.6 (rasp01)</li>
<li><strong>Container</strong> : b41a7dff114c_pihole</li>
<li><strong>DNS entries</strong> :
  <ul>
  <li>idp.home.lo -> 172.16.3.12</li>
  <li>keycloak.home.lo -> 172.16.3.12</li>
  <li>ldap.home.lo -> 172.16.3.12</li>
  </ul>
</li>
</ul>

<h4>Commandes manuelles equivalentes</h4>
<code># Lire la config DNS actuelle
ssh ju@172.16.3.6 "docker exec b41a7dff114c_pihole pihole-FTL --config dns.hosts"

# Mettre a jour (ajouter les entrees au tableau JSON existant)
ssh ju@172.16.3.6 'docker exec b41a7dff114c_pihole pihole-FTL --config dns.hosts \\
  "[... entrees existantes ..., \\"172.16.3.12 idp.home.lo\\", \\"172.16.3.12 keycloak.home.lo\\", \\"172.16.3.12 ldap.home.lo\\"]"'</code>

<h4>Verification</h4>
<code># Tester la resolution DNS
dig +short idp.home.lo @172.16.3.6
# Sortie attendue : 172.16.3.12

dig +short keycloak.home.lo @172.16.3.6
# Sortie attendue : 172.16.3.12

dig +short ldap.home.lo @172.16.3.6
# Sortie attendue : 172.16.3.12

# Verifier la config Pi-hole
ssh ju@172.16.3.6 "docker exec b41a7dff114c_pihole pihole-FTL --config dns.hosts" | grep -c "home.lo"</code>

<h4>Erreurs courantes et solutions</h4>
<ul>
<li><strong>DNS ne repond pas</strong> : Verifier que Pi-hole tourne : <code>ssh ju@172.16.3.6 "docker ps | grep pihole"</code></li>
<li><strong>Ancien DNS cache</strong> : Vider le cache DNS local : <code>sudo systemd-resolve --flush-caches</code></li>
<li><strong>Entrees dupliquees</strong> : Le script doit etre idempotent. Verifier avec
<code>pihole-FTL --config dns.hosts</code> que chaque entree n'apparait qu'une fois.</li>
<li><strong>dig ne trouve pas l'entree</strong> : S'assurer que le poste utilise 172.16.3.6 comme DNS.
Forcer avec <code>dig @172.16.3.6</code>.</li>
</ul>

<h4>Tips de debug</h4>
<ul>
<li>Pi-hole v6 n'utilise PAS <code>pihole -a</code> pour les custom DNS. Utiliser <code>pihole-FTL --config</code>.</li>
<li>Le format est un tableau JSON de strings : <code>["IP hostname", ...]</code></li>
<li>Les changements sont appliques immediatement, pas de restart necessaire.</li>
<li>Pour supprimer une entree : retirer du tableau JSON et re-appliquer.</li>
</ul>
""",
    },
    {
        "id": "kc-config",
        "title": "Configurer Keycloak",
        "script": "04-configure-keycloak-ldap.sh",
        "check": "curl -sk https://keycloak.home.lo:8443/realms/rancher/.well-known/openid-configuration 2>/dev/null | grep -q authorization_endpoint",
        "description": "Via l'API Admin REST de Keycloak : cree le realm 'rancher', "
                       "configure la federation LDAP, cree le client OIDC 'rancher' avec "
                       "le mapper de groupes.",
        "manual_commands": [
            "# 1. Token admin",
            "curl -sk -X POST https://keycloak.home.lo:8443/realms/master/protocol/openid-connect/token "
            "-d 'client_id=admin-cli&username=admin&password=<vault>&grant_type=password'",
            "# 2. Creer realm",
            "curl -sk -X POST https://keycloak.home.lo:8443/admin/realms "
            "-H 'Authorization: Bearer <token>' -H 'Content-Type: application/json' "
            "-d '{\"realm\":\"rancher\",\"enabled\":true}'",
            "# 3. LDAP federation, group mapper, OIDC client...",
        ],
        "variables": ["Realm: rancher", "Client ID: rancher", "LDAP: ldap://openldap:389", "Group filter: (cn=rancher-*)"],
        "doc": """
<h4>Description</h4>
<p>Configure Keycloak via l'<strong>API Admin REST</strong> pour integrer l'annuaire LDAP et preparer
l'authentification OIDC pour Rancher. Les operations effectuees :</p>
<ol>
<li><strong>Realm "rancher"</strong> : cree un realm dedie (separe du realm master)</li>
<li><strong>Federation LDAP</strong> : connecte Keycloak a OpenLDAP via le reseau Podman interne
(<code>ldap://openldap:389</code>), configure le bind DN, le user DN et le search filter</li>
<li><strong>Group mapper</strong> : mappe les groupes LDAP vers des groupes Keycloak avec un
<strong>filtre LDAP <code>(cn=rancher-*)</code></strong> pour ne synchroniser que les groupes pertinents.
Les groupes non-rancher dans LDAP sont ignores.</li>
<li><strong>Client OIDC "rancher"</strong> : cree le client avec les redirect URIs vers Rancher,
active le client authentication (confidential), et configure le mapper de groupes dans le token</li>
<li><strong>Sync LDAP</strong> : declenche une synchronisation complete des utilisateurs et groupes</li>
</ol>

<h4>Variables utilisees</h4>
<ul>
<li><strong>Realm</strong> : rancher</li>
<li><strong>Client ID</strong> : rancher</li>
<li><strong>Client Secret</strong> : genere automatiquement par Keycloak, recupere via l'API</li>
<li><strong>LDAP Connection URL</strong> : ldap://openldap:389 (port interne container, pas 1389 host)</li>
<li><strong>Group LDAP Filter</strong> : <code>(cn=rancher-*)</code> — ne synchronise que les groupes rancher-*</li>
<li><strong>LDAP Bind DN</strong> : cn=admin,dc=home,dc=lo</li>
<li><strong>LDAP Users DN</strong> : ou=People,dc=home,dc=lo</li>
<li><strong>LDAP Groups DN</strong> : ou=Groups,dc=home,dc=lo</li>
<li><strong>Redirect URIs</strong> : https://rancher.home.zypp.fr/verify-auth</li>
</ul>

<h4>Commandes manuelles equivalentes</h4>
<code># 1. Obtenir un token admin
TOKEN=$(curl -sk -X POST \\
  'https://keycloak.home.lo:8443/realms/master/protocol/openid-connect/token' \\
  -d 'client_id=admin-cli&amp;username=admin&amp;password=***&amp;grant_type=password' \\
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# 2. Creer le realm
curl -sk -X POST 'https://keycloak.home.lo:8443/admin/realms' \\
  -H "Authorization: Bearer $TOKEN" \\
  -H 'Content-Type: application/json' \\
  -d '{"realm":"rancher","enabled":true}'

# 3. Creer la federation LDAP
curl -sk -X POST 'https://keycloak.home.lo:8443/admin/realms/rancher/components' \\
  -H "Authorization: Bearer $TOKEN" \\
  -H 'Content-Type: application/json' \\
  -d '{
    "name": "openldap",
    "providerId": "ldap",
    "providerType": "org.keycloak.storage.UserStorageProvider",
    "config": {
      "connectionUrl": ["ldap://openldap:1389"],
      "bindDn": ["cn=admin,dc=home,dc=lo"],
      "usersDn": ["ou=People,dc=home,dc=lo"],
      "vendor": ["other"],
      "editMode": ["READ_ONLY"]
    }
  }'

# 4. Creer le client OIDC
curl -sk -X POST 'https://keycloak.home.lo:8443/admin/realms/rancher/clients' \\
  -H "Authorization: Bearer $TOKEN" \\
  -H 'Content-Type: application/json' \\
  -d '{
    "clientId": "rancher",
    "enabled": true,
    "clientAuthenticatorType": "client-secret",
    "redirectUris": ["https://rancher.home.zypp.fr/verify-auth"],
    "protocol": "openid-connect"
  }'</code>

<h4>Verification</h4>
<code># OIDC Discovery
curl -sk https://keycloak.home.lo:8443/realms/rancher/.well-known/openid-configuration | python3 -m json.tool
# Sortie attendue : JSON avec authorization_endpoint, token_endpoint, etc.

# Lister les utilisateurs du realm
curl -sk 'https://keycloak.home.lo:8443/admin/realms/rancher/users' \\
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
# Sortie attendue : liste des utilisateurs synchronises depuis LDAP

# Verifier le client
curl -sk 'https://keycloak.home.lo:8443/admin/realms/rancher/clients?clientId=rancher' \\
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
# Sortie attendue : client "rancher" avec enabled=true</code>

<h4>Erreurs courantes et solutions</h4>
<ul>
<li><strong>401 Unauthorized</strong> : Le token admin a expire (duree de vie 60s par defaut).
Regenerer le token avant chaque appel API.</li>
<li><strong>409 Conflict (realm exists)</strong> : Le realm existe deja. Ignorer ou supprimer avec
<code>DELETE /admin/realms/rancher</code>.</li>
<li><strong>LDAP sync echoue</strong> : Verifier que OpenLDAP est accessible depuis le conteneur Keycloak :
<code>sudo podman exec keycloak bash -c "cat &lt; /dev/tcp/openldap/1389"</code>.</li>
<li><strong>Client secret perdu</strong> : Recuperer via l'API :
<code>GET /admin/realms/rancher/clients/{id}/client-secret</code>.</li>
</ul>

<h4>Tips de debug</h4>
<ul>
<li>L'API Admin de Keycloak est documentee : <code>https://keycloak.home.lo:8443/admin/master/console/</code></li>
<li>Les tokens admin expirent vite. Utiliser un script qui re-genere le token a chaque etape.</li>
<li>Pour tester un login OIDC : <code>curl -sk -X POST .../token -d 'grant_type=password&amp;client_id=rancher&amp;client_secret=...&amp;username=dev-user&amp;password=...'</code></li>
<li>Keycloak UI : https://keycloak.home.lo:8443/admin/ (realm master, puis switch vers "rancher").</li>
</ul>
""",
    },
    {
        "id": "rancher-oidc",
        "title": "Integrer Rancher OIDC",
        "script": "05-configure-rancher-oidc.sh",
        "check": "curl -sk https://rancher.home.zypp.fr/v3/authConfigs/keycloakoidc 2>/dev/null | python3 -c 'import sys,json; exit(0 if json.load(sys.stdin).get(\"enabled\") else 1)' 2>/dev/null",
        "description": "Installe le CA self-signed sur la VM Rancher, redémarre les pods, "
                       "puis configure l'authentification OIDC via l'API Rancher v3.",
        "manual_commands": [
            "# 1. Copier le CA sur Rancher",
            "scp .certs/keycloak-ca.crt rancher@172.16.3.20:/tmp/",
            "ssh rancher@172.16.3.20 'sudo cp /tmp/keycloak-ca.crt /etc/pki/trust/anchors/ && sudo update-ca-certificates'",
            "# 2. Restart pods",
            "ssh rancher@172.16.3.20 'kubectl rollout restart deploy/rancher -n cattle-system'",
            "# 3. PUT /v3/keyCloakOIDCConfig avec issuer, clientId, clientSecret...",
        ],
        "variables": ["Rancher: https://rancher.home.zypp.fr", "Issuer: https://keycloak.home.lo:8443/realms/rancher"],
        "doc": """
<h4>Description</h4>
<p>Configure l'authentification <strong>OIDC Keycloak</strong> dans Rancher. Cette etape est critique
car elle modifie le systeme d'authentification de production. Le script :</p>
<ol>
<li><strong>Installe le CA</strong> : copie le certificat self-signed de Keycloak sur la VM Rancher
et l'ajoute au trust store systeme (<code>/etc/pki/trust/anchors/</code>)</li>
<li><strong>Redemarrage</strong> : effectue un rollout restart du deployment Rancher pour qu'il prenne
en compte le nouveau CA</li>
<li><strong>Attend la disponibilite</strong> : attend que Rancher soit de nouveau UP (health check)</li>
<li><strong>Configure OIDC</strong> : envoie la configuration keycloakoidc via <code>PUT /v3/keyCloakOIDCConfigs/keycloakoidc</code>
avec l'issuer, le client ID, le client secret, et les endpoints</li>
<li><strong>Mode restricted</strong> : active le mode <code>accessMode: restricted</code> avec une liste de
groupes autorises (<code>allowedPrincipalIds</code>) pour ne pas exposer tous les groupes Keycloak</li>
<li><strong>GlobalRoleBindings</strong> : cree les bindings groupe &rarr; role global
(rancher-admins &rarr; admin, rancher-users &rarr; user, rancher-readonly &rarr; user-base)</li>
<li><strong>ClusterRoleTemplateBindings</strong> : cree les bindings groupe &rarr; role cluster local
(rancher-admins &rarr; cluster-owner, rancher-users/readonly &rarr; cluster-member)</li>
</ol>

<h4>Filtrage des groupes</h4>
<p>Le script configure Rancher en mode <strong>restricted</strong> : seuls les groupes explicitement listes
dans <code>allowedPrincipalIds</code> peuvent se connecter. Les utilisateurs Keycloak qui ne sont dans
aucun de ces groupes seront refuses par Rancher.</p>
<p><strong>Limitation OIDC</strong> : le provider Keycloak OIDC dans Rancher ne supporte pas la recherche
de groupes/utilisateurs. L'ajout de membres dans l'UI affiche "Unable to fetch principal info".
C'est cosmétique — les bindings fonctionnent. Voir la section "Filtrage des groupes" dans la
documentation complete.</p>

<h4>Variables utilisees</h4>
<ul>
<li><strong>Rancher URL</strong> : https://rancher.home.zypp.fr</li>
<li><strong>Rancher API token</strong> : obtenu via login <code>/v3-public/localProviders/local?action=login</code></li>
<li><strong>OIDC Issuer</strong> : https://keycloak.home.lo:8443/realms/rancher</li>
<li><strong>Client ID</strong> : rancher (depuis l'etape 4)</li>
<li><strong>Client Secret</strong> : recupere automatiquement depuis l'API Keycloak</li>
<li><strong>Auth endpoint</strong> : https://keycloak.home.lo:8443/realms/rancher/protocol/openid-connect/auth</li>
<li><strong>CA cert</strong> : .certs/keycloak-ca.crt (genere a l'etape 2)</li>
</ul>

<h4>Commandes manuelles equivalentes</h4>
<code># 1. Copier le CA sur la VM Rancher
scp .certs/keycloak-ca.crt rancher@172.16.3.20:/tmp/

# 2. Installer le CA dans le trust store
ssh rancher@172.16.3.20 'sudo cp /tmp/keycloak-ca.crt /etc/pki/trust/anchors/ &amp;&amp; sudo update-ca-certificates'

# 3. Redemarrer Rancher
ssh rancher@172.16.3.20 'sudo /var/lib/rancher/rke2/bin/kubectl \\
  --kubeconfig /etc/rancher/rke2/rke2.yaml \\
  rollout restart deploy/rancher -n cattle-system'

# 4. Attendre la disponibilite (~2 min)
until curl -sk https://rancher.home.zypp.fr/healthz | grep -q ok; do sleep 5; done

# 5. Obtenir un token Rancher
TOKEN=$(curl -sk -X POST 'https://rancher.home.zypp.fr/v3-public/localProviders/local?action=login' \\
  -H 'Content-Type: application/json' \\
  -d '{"username":"admin","password":"***"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# 6. Configurer OIDC
curl -sk -X PUT 'https://rancher.home.zypp.fr/v3/authConfigs/keycloakoidc' \\
  -H "Authorization: Bearer $TOKEN" \\
  -H 'Content-Type: application/json' \\
  -d '{
    "enabled": true,
    "issuer": "https://keycloak.home.lo:8443/realms/rancher",
    "clientId": "rancher",
    "clientSecret": "***",
    "rancherUrl": "https://rancher.home.zypp.fr/verify-auth",
    "accessMode": "restricted",
    "allowedPrincipalIds": [
      "local://user-kk67j",
      "keycloakoidc_group://rancher-admins",
      "keycloakoidc_group://rancher-users",
      "keycloakoidc_group://rancher-readonly"
    ]
  }'

# 7. GlobalRoleBinding (groupe -> role global)
curl -sk -X POST 'https://rancher.home.zypp.fr/v3/globalRoleBindings' \\
  -H "Authorization: Bearer $TOKEN" \\
  -H 'Content-Type: application/json' \\
  -d '{"globalRoleId":"admin","groupPrincipalId":"keycloakoidc_group://rancher-admins"}'

# 8. ClusterRoleTemplateBinding (groupe -> role cluster)
curl -sk -X POST 'https://rancher.home.zypp.fr/v3/clusterRoleTemplateBindings' \\
  -H "Authorization: Bearer $TOKEN" \\
  -H 'Content-Type: application/json' \\
  -d '{"clusterId":"local","groupPrincipalId":"keycloakoidc_group://rancher-admins","roleTemplateId":"cluster-owner"}'</code>

<h4>Verification</h4>
<code># Verifier que OIDC est active
curl -sk https://rancher.home.zypp.fr/v3/authConfigs/keycloakoidc | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'Enabled: {d.get(\"enabled\")}')
print(f'Issuer: {d.get(\"issuer\")}')
print(f'ClientId: {d.get(\"clientId\")}')
"
# Sortie attendue :
# Enabled: True
# Issuer: https://keycloak.home.lo:8443/realms/rancher
# ClientId: rancher

# Tester le login OIDC (ouvrir dans le navigateur)
# https://rancher.home.zypp.fr/ -> bouton "Log in with Keycloak"</code>

<h4>Erreurs courantes et solutions</h4>
<ul>
<li><strong>Rancher ne fait pas confiance au CA Keycloak</strong> : Verifier que le cert est dans
<code>/etc/pki/trust/anchors/</code> ET que <code>update-ca-certificates</code> a ete execute.
Le rollout restart est necessaire pour que les pods Rancher chargent le nouveau bundle CA.</li>
<li><strong>OIDC redirect echoue</strong> : Verifier que le redirect URI dans le client Keycloak
correspond exactement a <code>https://rancher.home.zypp.fr/verify-auth</code>.</li>
<li><strong>Login bloque en boucle</strong> : Le client secret est probablement incorrect.
Le recuperer depuis Keycloak : <code>GET /admin/realms/rancher/clients/{id}/client-secret</code>.</li>
<li><strong>OIDC active mais login local impossible</strong> : Utiliser l'URL directe :
<code>https://rancher.home.zypp.fr/login?local</code> pour le login admin local.</li>
</ul>

<h4>Tips de debug</h4>
<ul>
<li>Toujours garder un onglet avec <code>?local</code> au cas ou l'OIDC bloque l'acces.</li>
<li>Les logs Rancher montrent les erreurs OIDC : <code>kubectl logs -f deploy/rancher -n cattle-system</code></li>
<li>Pour desactiver OIDC en urgence : <code>PUT /v3/authConfigs/keycloakoidc</code> avec <code>"enabled": false</code></li>
<li>Le CA bundle utilise par Rancher est dans <code>/etc/ssl/certs/ca-certificates.crt</code> sur les pods.</li>
</ul>
""",
    },
    {
        "id": "verify",
        "title": "Verification",
        "script": "06-verify.sh",
        "check": None,
        "description": "Execute tous les checks de verification : VM, conteneurs, LDAP, "
                       "Keycloak health, OIDC discovery, DNS, Rancher OIDC status.",
        "manual_commands": [
            "ssh opensuse@172.16.3.12 'sudo podman ps'",
            "curl -sk https://keycloak.home.lo:8443/realms/rancher/.well-known/openid-configuration",
            "curl -sk https://rancher.home.zypp.fr/v3/authConfigs/keycloakoidc | grep enabled",
        ],
        "variables": [],
        "doc": """
<h4>Description</h4>
<p>Execute une <strong>suite complete de verifications</strong> pour valider que tout le deploiement
fonctionne de bout en bout. Le script teste chaque composant dans l'ordre :</p>
<ol>
<li><strong>VM</strong> : connectivite SSH, hostname, espace disque</li>
<li><strong>Conteneurs</strong> : OpenLDAP et Keycloak en cours d'execution</li>
<li><strong>LDAP</strong> : recherche d'utilisateurs, presence des groupes</li>
<li><strong>Keycloak health</strong> : endpoint /health/ready</li>
<li><strong>OIDC Discovery</strong> : endpoint .well-known/openid-configuration</li>
<li><strong>DNS</strong> : resolution de idp.home.lo, keycloak.home.lo, ldap.home.lo</li>
<li><strong>Rancher OIDC</strong> : configuration active dans l'API Rancher</li>
</ol>
<p>Chaque verification affiche [PASS] ou [FAIL] avec des details en cas d'echec.</p>

<h4>Variables utilisees</h4>
<ul>
<li><strong>VM IP</strong> : 172.16.3.12</li>
<li><strong>SSH user</strong> : opensuse</li>
<li><strong>Keycloak URL</strong> : https://keycloak.home.lo:8443</li>
<li><strong>Rancher URL</strong> : https://rancher.home.zypp.fr</li>
<li><strong>DNS server</strong> : 172.16.3.6 (Pi-hole)</li>
</ul>

<h4>Commandes manuelles equivalentes</h4>
<code># 1. VM accessible
ssh -o ConnectTimeout=5 opensuse@172.16.3.12 hostname

# 2. Conteneurs en cours
ssh opensuse@172.16.3.12 'sudo podman ps --format "{{.Names}} {{.Status}}"'
# Sortie attendue :
# openldap Up X hours
# keycloak Up X hours

# 3. LDAP fonctionne
ssh opensuse@172.16.3.12 'ldapsearch -x -H ldap://127.0.0.1:1389 \\
  -D "cn=admin,dc=home,dc=lo" -w "***" \\
  -b "dc=home,dc=lo" "(uid=*)" uid | grep "uid:"'

# 4. Keycloak health
curl -sk https://keycloak.home.lo:8443/health/ready
# Sortie attendue : {"status":"UP",...}

# 5. OIDC Discovery
curl -sk https://keycloak.home.lo:8443/realms/rancher/.well-known/openid-configuration \\
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK' if 'authorization_endpoint' in d else 'FAIL')"

# 6. DNS
for h in idp keycloak ldap; do
  echo -n "$h.home.lo -> "
  dig +short $h.home.lo @172.16.3.6
done

# 7. Rancher OIDC
curl -sk https://rancher.home.zypp.fr/v3/authConfigs/keycloakoidc \\
  | python3 -c "import sys,json; print('Enabled:', json.load(sys.stdin).get('enabled'))"</code>

<h4>Verification</h4>
<code># Le script de verification est lui-meme le check.
# Executer et verifier que tous les tests passent :
bash 06-verify.sh
# Sortie attendue : tous [PASS], aucun [FAIL]

# Pour un check rapide en une commande :
curl -sk https://keycloak.home.lo:8443/health/ready | grep -q UP &amp;&amp; echo "Keycloak OK" || echo "Keycloak FAIL"</code>

<h4>Erreurs courantes et solutions</h4>
<ul>
<li><strong>[FAIL] VM inaccessible</strong> : La VM est peut-etre eteinte. Verifier sur Harvester :
<code>kubectl get vm idp -n default</code>.</li>
<li><strong>[FAIL] Conteneur arrete</strong> : Un conteneur a crash. Verifier les logs :
<code>sudo podman logs openldap</code> ou <code>sudo podman logs keycloak</code>.
Redemarrer avec <code>sudo podman start &lt;name&gt;</code>.</li>
<li><strong>[FAIL] DNS</strong> : Pi-hole ne repond pas ou les entrees ont ete supprimees.
Relancer l'etape 3 (DNS).</li>
<li><strong>[FAIL] Rancher OIDC</strong> : La config a pu etre ecrasee par un upgrade Rancher.
Relancer l'etape 5.</li>
</ul>

<h4>Tips de debug</h4>
<ul>
<li>Executer les checks un par un pour isoler le composant defaillant.</li>
<li>Les conteneurs Podman redemarrent automatiquement si configures avec <code>--restart=always</code>.
Sinon, les relancer apres un reboot VM.</li>
<li>Pour un diagnostic complet du reseau : <code>ping -c1 172.16.3.12 &amp;&amp; ping -c1 keycloak.home.lo</code>.</li>
<li>Historique des checks : les resultats sont sauvegardes dans <code>state.json</code> par l'UI.</li>
</ul>
""",
    },
]


def _load_state():
    if STATE_FILE.exists():
        with open(STATE_FILE) as f:
            return json.load(f)
    return {}


def _save_state(state):
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)


def _check_step(step):
    """Run the step's check command and return True/False/None."""
    cmd = step.get('check')
    if cmd is None:
        return None
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, timeout=15)
        return result.returncode == 0
    except (subprocess.TimeoutExpired, Exception):
        return False


@deploy_bp.route('/api/status')
def status():
    results = []
    for step in STEPS:
        ok = _check_step(step)
        results.append({
            "id": step["id"],
            "title": step["title"],
            "status": "ok" if ok is True else ("unknown" if ok is None else "not_ready"),
        })
    return jsonify(results)


@deploy_bp.route('/api/steps/<step_id>/details')
def step_details(step_id):
    for step in STEPS:
        if step["id"] == step_id:
            return jsonify({
                "id": step["id"],
                "title": step["title"],
                "description": step["description"],
                "manual_commands": step.get("manual_commands", []),
                "variables": step.get("variables", []),
                "script": step.get("script"),
            })
    return jsonify({"error": "Step not found"}), 404


@deploy_bp.route('/api/steps/<step_id>/run', methods=['POST'])
def run_step(step_id):
    step = None
    for s in STEPS:
        if s["id"] == step_id:
            step = s
            break

    if step is None:
        return jsonify({"error": "Step not found"}), 404

    script = step.get("script")
    if script is None:
        return jsonify({"error": "This step has no automated script (use Terraform manually)"}), 400

    script_path = SCRIPT_DIR / script
    if not script_path.exists():
        return jsonify({"error": f"Script not found: {script}"}), 404

    def generate():
        proc = subprocess.Popen(
            ['bash', str(script_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            cwd=str(SCRIPT_DIR),
            text=True,
        )

        for line in proc.stdout:
            yield f"data: {line.rstrip()}\n\n"

        proc.wait()

        if proc.returncode == 0:
            yield "data: __DONE_OK__\n\n"
        else:
            yield f"data: __DONE_FAIL__ (exit code {proc.returncode})\n\n"

    return Response(
        stream_with_context(generate()),
        mimetype='text/event-stream',
    )
