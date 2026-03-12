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
        "check": "ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 sles@172.16.3.12 hostname",
        "description": "Cree la VM 'idp' (172.16.3.12) sur Harvester via Terraform. "
                       "2 vCPU, 4 Gi RAM, 40 Gi disque, SLES 15 SP7.",
        "manual_commands": [
            "cd /home/ju/workspace/TERRAFORM/KEYCLOAK",
            "terraform init",
            "terraform plan",
            "terraform apply",
            "ssh sles@172.16.3.12 hostname",
        ],
        "variables": ["VM IP: 172.16.3.12", "Image: SLES 15 SP7 (image-nhtf9)", "Reseau: default/production"],
    },
    {
        "id": "openldap",
        "title": "Deployer OpenLDAP",
        "script": "01-deploy-openldap.sh",
        "check": "ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 sles@172.16.3.12 'sudo podman ps --format {{.Names}} | grep openldap'",
        "description": "Deploie le conteneur OpenLDAP (bitnami/openldap:2.6) sur la VM. "
                       "Cree les OUs, groupes et utilisateurs de demo via LDIF.",
        "manual_commands": [
            "# Sur la VM (ssh sles@172.16.3.12) :",
            "sudo podman network create keycloak-net",
            "sudo podman run -d --name openldap --network keycloak-net "
            "-p 127.0.0.1:1389:1389 -e LDAP_ROOT='dc=home,dc=lo' "
            "-e LDAP_ADMIN_USERNAME=admin -e LDAP_ADMIN_PASSWORD=<vault> "
            "-v /tmp/ldap-init:/ldifs:Z docker.io/bitnami/openldap:2.6",
            "ldapsearch -x -H ldap://127.0.0.1:1389 -D 'cn=admin,dc=home,dc=lo' -w <vault> -b 'dc=home,dc=lo' '(uid=*)'",
        ],
        "variables": ["Base DN: dc=home,dc=lo", "Port: 1389 (localhost only)", "Groupes: rancher-admins, rancher-users, rancher-readonly"],
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
        "variables": ["Realm: rancher", "Client ID: rancher", "LDAP: ldap://openldap:1389"],
    },
    {
        "id": "rancher-oidc",
        "title": "Integrer Rancher OIDC",
        "script": "05-configure-rancher-oidc.sh",
        "check": "curl -sk https://rancher.home.zypp.fr/v3/keyCloakOIDCConfig 2>/dev/null | python3 -c 'import sys,json; exit(0 if json.load(sys.stdin).get(\"enabled\") else 1)' 2>/dev/null",
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
    },
    {
        "id": "verify",
        "title": "Verification",
        "script": "06-verify.sh",
        "check": None,
        "description": "Execute tous les checks de verification : VM, conteneurs, LDAP, "
                       "Keycloak health, OIDC discovery, DNS, Rancher OIDC status.",
        "manual_commands": [
            "ssh sles@172.16.3.12 'sudo podman ps'",
            "curl -sk https://keycloak.home.lo:8443/realms/rancher/.well-known/openid-configuration",
            "curl -sk https://rancher.home.zypp.fr/v3/keyCloakOIDCConfig | grep enabled",
        ],
        "variables": [],
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
