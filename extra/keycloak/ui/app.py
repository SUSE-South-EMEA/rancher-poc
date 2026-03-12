#!/usr/bin/env python3
"""Keycloak + OpenLDAP Deployment UI — step-by-step installer for Rancher OIDC."""

from pathlib import Path
from flask import Flask, send_from_directory, jsonify
from modules.deploy import deploy_bp, STEPS

app = Flask(__name__, static_folder='.')
app.register_blueprint(deploy_bp)

README_PATH = Path(__file__).resolve().parent.parent / 'README.md'


@app.route('/')
def index():
    return send_from_directory('.', 'index.html')


@app.route('/api/doc')
def get_doc():
    """Return the full README.md content."""
    if README_PATH.exists():
        content = README_PATH.read_text(encoding='utf-8')
    else:
        content = '# Documentation\n\nREADME.md not found.'
    return jsonify({"content": content})


@app.route('/api/steps/<step_id>/doc')
def get_step_doc(step_id):
    """Return the rich HTML doc for a specific step."""
    for step in STEPS:
        if step["id"] == step_id:
            return jsonify({
                "id": step["id"],
                "title": step["title"],
                "doc": step.get("doc", "<p>Pas de documentation detaillee pour cette etape.</p>"),
            })
    return jsonify({"error": "Step not found"}), 404


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8092, debug=False)
