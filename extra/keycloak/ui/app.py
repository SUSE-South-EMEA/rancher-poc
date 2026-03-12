#!/usr/bin/env python3
"""Keycloak + OpenLDAP Deployment UI — step-by-step installer for Rancher OIDC."""

from flask import Flask, send_from_directory
from modules.deploy import deploy_bp

app = Flask(__name__, static_folder='.')
app.register_blueprint(deploy_bp)


@app.route('/')
def index():
    return send_from_directory('.', 'index.html')


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8092, debug=False)
