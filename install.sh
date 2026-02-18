#!/bin/bash
set -euo pipefail

## ============================================================================
## install.sh — Main entry point for Rancher PoC deployment
##
## Usage:
##   ./install.sh                              # Interactive wizard
##   ./install.sh --auto --config lab.sh       # Full auto mode
##   ./install.sh --resume                     # Resume after failure
##   ./install.sh --dry-run                    # Preview without executing
##   ./install.sh --steps "5,6"               # Run specific steps only
##   ./install.sh --help                       # Show this help
## ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
AUTO_MODE="${AUTO_MODE:-0}"
DRY_RUN="${DRY_RUN:-0}"
RESUME="${RESUME:-0}"
CONFIG_FILE=""
SELECTED_STEPS=""
LOG_FILE="${LOG_FILE:-./install-$(date '+%Y%m%d-%H%M%S').log}"
STATE_FILE="${STATE_FILE:-.rancher-poc.state}"
AUTO_FAIL_FAST="${AUTO_FAIL_FAST:-1}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

export AUTO_MODE DRY_RUN LOG_FILE STATE_FILE AUTO_FAIL_FAST LOG_LEVEL

# ---------------------------------------------------------------------------
# Step definitions
# ---------------------------------------------------------------------------
declare -A STEP_SCRIPTS STEP_NAMES
STEP_SCRIPTS=(
    [2]="02-ssh-keys_create_exchange_check.sh"
    [3]="03-os_preparation_PACKAGES.sh"
    [4]="04-os_preparation_NETWORKING.sh"
    [5]="05-rke2_deploy.sh"
    [6]="06-rancher_install.sh"
)
STEP_NAMES=(
    [2]="SSH Keys"
    [3]="OS Packages"
    [4]="Network Configuration"
    [5]="RKE2 Deployment"
    [6]="Rancher Installation"
)
STEP_ORDER=(2 3 4 5 6)

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<'EOF'
Rancher PoC Installer

Usage: ./install.sh [OPTIONS]

Options:
  --auto                 Run in automatic mode (no prompts)
  --config FILE          Load configuration from FILE (used with --auto)
  --resume               Resume from last successful step
  --dry-run              Show what would be executed without doing it
  --steps "2,3,5"        Run only specified steps
  --help                 Show this help message

Steps:
  2  SSH Keys — create and deploy SSH key pairs
  3  OS Packages — install required packages on all nodes
  4  Network — configure networking, firewall, IP forwarding
  5  RKE2 — deploy RKE2 Kubernetes cluster
  6  Rancher — install Rancher Management Server

Interactive mode (default):
  Runs a guided wizard to configure 01-vars.sh, then executes
  each step with confirmation prompts.

Auto mode (--auto --config FILE):
  Loads all variables from FILE, runs all steps without prompts,
  logs everything to a file. Returns exit code 0 on success.

Examples:
  ./install.sh                                   # Guided wizard
  ./install.sh --auto --config configs/lab.sh    # Automated deployment
  ./install.sh --steps "5,6"                     # Only RKE2 + Rancher
  ./install.sh --resume                          # Continue after failure
  ./install.sh --dry-run --config configs/lab.sh # Preview auto run
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Parse CLI arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)     AUTO_MODE=1; shift ;;
        --config)   CONFIG_FILE="$2"; shift 2 ;;
        --resume)   RESUME=1; shift ;;
        --dry-run)  DRY_RUN=1; AUTO_MODE=1; shift ;;
        --steps)    SELECTED_STEPS="$2"; shift 2 ;;
        --help|-h)  usage ;;
        *)          echo "Unknown option: $1"; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Progress bar
# ---------------------------------------------------------------------------
show_progress() {
    local current="$1"
    local total="$2"
    local step_name="$3"
    local width=40
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))
    local bar=""

    for ((i=0; i<filled; i++)); do bar+="#"; done
    for ((i=0; i<empty; i++)); do bar+="-"; done

    printf "\r[%s] Step %d/%d: %s" "$bar" "$current" "$total" "$step_name"
    echo
}

# ---------------------------------------------------------------------------
# Wizard: interactive configuration
# ---------------------------------------------------------------------------
run_wizard() {
    echo
    echo "=========================================="
    echo "  Rancher PoC - Installation Wizard"
    echo "=========================================="
    echo

    # 1. Language
    echo "Step 1: Language / Langue"
    echo "  1) fr - Francais"
    echo "  2) en - English"
    echo "  3) it - Italiano"
    local lang_choice
    read -p "  Choose [1]: " lang_choice
    case "${lang_choice:-1}" in
        1|fr) LANGUAGE="fr" ;;
        2|en) LANGUAGE="en" ;;
        3|it) LANGUAGE="it" ;;
        *)    LANGUAGE="fr" ;;
    esac
    echo "  -> $LANGUAGE"
    echo

    # 2. Target hosts
    echo "Step 2: Target hosts (comma-separated FQDNs)"
    echo "  Example: node1.example.com,node2.example.com"
    local hosts_input
    read -p "  Hosts: " hosts_input
    if [[ -z "$hosts_input" ]]; then
        echo "  Error: at least one host is required"
        exit 1
    fi
    HOST_LIST="$hosts_input"
    echo "  -> $HOST_LIST"
    echo

    # 3. SSH user
    echo "Step 3: SSH user for remote connections"
    echo "  Leave empty to use current user or SSH config"
    local ssh_input
    read -p "  SSH user [$(whoami)]: " ssh_input
    SSH_USER="${ssh_input:-}"
    echo "  -> ${SSH_USER:-<current user>}"
    echo

    # 4. Deployment mode
    echo "Step 4: Deployment mode"
    echo "  1) internet - Direct Internet access (default)"
    echo "  2) proxy    - Through HTTP proxy"
    echo "  3) airgap   - Air-gapped environment"
    local deploy_choice
    read -p "  Choose [1]: " deploy_choice
    case "${deploy_choice:-1}" in
        1|internet)
            AIRGAP_DEPLOY="0"
            PROXY_DEPLOY="0"
            ;;
        2|proxy)
            AIRGAP_DEPLOY="0"
            PROXY_DEPLOY="1"
            echo
            read -p "  HTTP proxy (host:port): " _HTTP_PROXY
            read -p "  HTTPS proxy (host:port) [${_HTTP_PROXY}]: " _HTTPS_PROXY
            _HTTPS_PROXY="${_HTTPS_PROXY:-$_HTTP_PROXY}"
            read -p "  No proxy [127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16]: " _NO_PROXY
            _NO_PROXY="${_NO_PROXY:-127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,cattle-system.svc,.svc,.cluster.local}"
            ;;
        3|airgap)
            AIRGAP_DEPLOY="1"
            PROXY_DEPLOY="0"
            echo
            read -p "  Registry URL: " AIRGAP_REGISTRY_URL
            read -p "  Insecure registry? (1=yes, 0=no) [1]: " AIRGAP_REGISTRY_INSECURE
            AIRGAP_REGISTRY_INSECURE="${AIRGAP_REGISTRY_INSECURE:-1}"
            read -p "  Registry user (empty for none): " AIRGAP_REGISTRY_USER
            if [[ -n "$AIRGAP_REGISTRY_USER" ]]; then
                read -s -p "  Registry password: " AIRGAP_REGISTRY_PASSWD
                echo
            fi
            ;;
    esac
    echo

    # 5. Software versions
    echo "Step 5: Software versions"
    local rke2_v helm_v certmgr_v rancher_v
    read -p "  RKE2 version [v1.33.7+rke2r1]: " rke2_v
    RKE2_VERSION="${rke2_v:-v1.33.7+rke2r1}"
    read -p "  Helm version [4.0.1]: " helm_v
    HELM_VERSION="${helm_v:-4.0.1}"
    read -p "  Cert-manager version [v1.19.1]: " certmgr_v
    CERTMGR_VERSION="${certmgr_v:-v1.19.1}"
    read -p "  Rancher version [2.13.1]: " rancher_v
    RANCHER_VERSION="${rancher_v:-2.13.1}"
    echo "  -> RKE2=$RKE2_VERSION Helm=$HELM_VERSION CertMgr=$CERTMGR_VERSION Rancher=$RANCHER_VERSION"
    echo

    # 6. TLS
    echo "Step 6: TLS configuration"
    echo "  1) rancher  - Self-signed (cert-manager generates certs)"
    echo "  2) secret   - User-provided (tls.crt + tls.key in working dir)"
    echo "  3) external - External TLS termination (e.g. reverse proxy)"
    local tls_choice
    read -p "  Choose [1]: " tls_choice
    case "${tls_choice:-1}" in
        1|rancher)  TLS_SOURCE="rancher" ;;
        2|secret)   TLS_SOURCE="secret" ;;
        3|external) TLS_SOURCE="external" ;;
        *)          TLS_SOURCE="rancher" ;;
    esac
    PRIVATE_CA="0"
    if [[ "$TLS_SOURCE" != "rancher" ]]; then
        read -p "  Use private CA? (0=no, 1=yes) [0]: " PRIVATE_CA
        PRIVATE_CA="${PRIVATE_CA:-0}"
    fi
    echo "  -> TLS=$TLS_SOURCE, Private CA=$PRIVATE_CA"
    echo

    # 7. Kube-VIP
    echo "Step 7: Kube-VIP (optional, for HA with virtual IP)"
    local use_kubevip
    read -p "  Use kube-vip? (y/N): " use_kubevip
    if [[ "$use_kubevip" =~ ^[Yy]$ ]]; then
        read -p "  VIP IP address: " RKE2_VIP_IP
        read -p "  VIP FQDN: " RKE2_VIP_FQDN
        read -p "  VIP interface [eth0]: " RKE2_VIP_INTERFACE
        RKE2_VIP_INTERFACE="${RKE2_VIP_INTERFACE:-eth0}"
    else
        RKE2_VIP_IP=""
        RKE2_VIP_FQDN=""
        RKE2_VIP_INTERFACE=""
    fi
    echo

    # 8. Rancher FQDN
    echo "Step 8: Rancher Management Server FQDN"
    local rancher_fqdn
    read -p "  FQDN [rancher.example.com]: " rancher_fqdn
    LB_RANCHER_FQDN="${rancher_fqdn:-rancher.example.com}"
    read -p "  Secondary FQDN (optional): " LB2_RANCHER_FQDN
    LB2_RANCHER_FQDN="${LB2_RANCHER_FQDN:-}"
    echo "  -> $LB_RANCHER_FQDN"
    echo

    # Repos
    RKE2_REPO="${RKE2_REPO:-https://prime.ribs.rancher.io/rke2}"
    HELM_ARCHIVE="https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz"
    HELM_REPO_RANCHER="${HELM_REPO_RANCHER:-https://charts.rancher.com/server-charts/prime}"
    HELM_REPO_CERTMANAGER="${HELM_REPO_CERTMANAGER:-https://charts.jetstack.io}"
    DOCKER_VERSION="${DOCKER_VERSION:-20.10}"
    AIRGAP_REGISTRY_CACERT="${AIRGAP_REGISTRY_CACERT:-}"

    # Summary
    echo "=========================================="
    echo "  Configuration Summary"
    echo "=========================================="
    echo "  Language:        $LANGUAGE"
    echo "  Hosts:           $HOST_LIST"
    echo "  SSH user:        ${SSH_USER:-<current>}"
    echo "  Deploy mode:     $(if [[ $AIRGAP_DEPLOY == 1 ]]; then echo airgap; elif [[ $PROXY_DEPLOY == 1 ]]; then echo proxy; else echo internet; fi)"
    echo "  RKE2:            $RKE2_VERSION"
    echo "  Helm:            $HELM_VERSION"
    echo "  Cert-Manager:    $CERTMGR_VERSION"
    echo "  Rancher:         $RANCHER_VERSION"
    echo "  TLS:             $TLS_SOURCE (Private CA: $PRIVATE_CA)"
    if [[ -n "$RKE2_VIP_IP" ]]; then
        echo "  Kube-VIP:        $RKE2_VIP_IP ($RKE2_VIP_FQDN)"
    else
        echo "  Kube-VIP:        disabled"
    fi
    echo "  Rancher FQDN:    $LB_RANCHER_FQDN"
    echo "=========================================="
    echo

    local confirm
    read -p "Save configuration and start deployment? (Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    # Generate 01-vars.sh
    generate_vars_file
    echo
    echo "Configuration saved to 01-vars.sh"
    echo
}

# ---------------------------------------------------------------------------
# Generate 01-vars.sh from wizard values
# ---------------------------------------------------------------------------
generate_vars_file() {
    cat > 01-vars.sh <<VARSEOF
######################## LANGUAGE ################################
LANGUAGE="${LANGUAGE}"

######################## HOSTS LIST ##############################
## Nodes to be handled by the script / FQDN
## Used by RKE2 when generating TLS certs
HOST_LIST="${HOST_LIST}"

######################## SSH CONFIGURATION #######################
## SSH user to use for remote commands
## Leave empty to use current user or user from SSH config
SSH_USER="${SSH_USER}"

######################## IF AIRGAP SETUP #########################
## Airgap deployment
AIRGAP_DEPLOY="${AIRGAP_DEPLOY}"	# 1=airgap enabled / 0=airgap disabled
AIRGAP_REGISTRY_URL="${AIRGAP_REGISTRY_URL:-registry.domain:5000}"
AIRGAP_REGISTRY_CACERT="${AIRGAP_REGISTRY_CACERT:-}"
# Use insecure registry
AIRGAP_REGISTRY_INSECURE="${AIRGAP_REGISTRY_INSECURE:-1}" # 1=insecure / 0=secured
# Optional user/password
AIRGAP_REGISTRY_USER="${AIRGAP_REGISTRY_USER:-}"
AIRGAP_REGISTRY_PASSWD="${AIRGAP_REGISTRY_PASSWD:-}"
## Docker version to use for Airgap image synchronization (RHEL/CentOS)
DOCKER_VERSION="${DOCKER_VERSION}"  # options [20.10|23.0|24.0]

######################## IF PROXY SETUP ##########################
## Proxy settings
PROXY_DEPLOY="${PROXY_DEPLOY}"	# 1=proxy enabled / 0=proxy disabled
_HTTP_PROXY="${_HTTP_PROXY:-admin:3128}"
_HTTPS_PROXY="${_HTTPS_PROXY:-admin:3128}"
_NO_PROXY="${_NO_PROXY:-127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,cattle-system.svc,.svc,.cluster.local}"

######################## SELECT VERSIONS & SOURCES################
## RKE2, Rancher and Helm versions to deploy
HELM_VERSION="${HELM_VERSION}"
RKE2_VERSION="${RKE2_VERSION}"
CERTMGR_VERSION="${CERTMGR_VERSION}"
RANCHER_VERSION="${RANCHER_VERSION}"
## RKE2 Community or Prime
RKE2_REPO="${RKE2_REPO}"
## HELM Install
HELM_ARCHIVE="${HELM_ARCHIVE}"
## HELM REPOSITORIES
HELM_REPO_RANCHER="${HELM_REPO_RANCHER}"
HELM_REPO_CERTMANAGER="${HELM_REPO_CERTMANAGER}"

######### RANCHER MGMT SERVER CERTIFICATE AND PRIVATE CA #########
## Rancher TLS configuration. Available options are [rancher,secret,external]
TLS_SOURCE="${TLS_SOURCE}"
## Private CA (cacerts.pem must be placed in working directory)
PRIVATE_CA="${PRIVATE_CA}"

######################## RKE2 KUBE-VIP ###########################
## RKE2 KUBE-VIP configuration (leave empty if you do not want to use kube-vip)
RKE2_VIP_IP=${RKE2_VIP_IP:-}
RKE2_VIP_FQDN="${RKE2_VIP_FQDN:-}"
RKE2_VIP_INTERFACE="${RKE2_VIP_INTERFACE:-eth0}"

######################## FQDNs & DOMAINs #########################
## Rancher Management Load balancer FQDN
LB_RANCHER_FQDN="${LB_RANCHER_FQDN}"
LB2_RANCHER_FQDN="${LB2_RANCHER_FQDN:-}"
VARSEOF
}

# ---------------------------------------------------------------------------
# Run a deployment step
# ---------------------------------------------------------------------------
run_step() {
    local step_num="$1"
    local script="${STEP_SCRIPTS[$step_num]}"
    local name="${STEP_NAMES[$step_num]}"

    # Check resume: skip if already successful
    if [[ "$RESUME" == "1" ]]; then
        local prev_status
        prev_status=$(check_state_step "script_${step_num}")
        if [[ "$prev_status" == "success" ]]; then
            echo "  [SKIP] Step $step_num ($name) — already completed"
            return 0
        fi
    fi

    if [[ ! -f "$script" ]]; then
        echo "  [ERROR] Script not found: $script"
        return 1
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        echo "  [DRY-RUN] Would execute: bash $script"
        return 0
    fi

    echo "  [RUN] Step $step_num: $name ($script)"
    update_state_step "script_${step_num}" "running"

    if bash "$script"; then
        update_state_step "script_${step_num}" "success"
        echo "  [OK] Step $step_num completed"
        return 0
    else
        local rc=$?
        update_state_step "script_${step_num}" "failed"
        echo "  [FAIL] Step $step_num failed (exit code: $rc)"
        return $rc
    fi
}

# ---------------------------------------------------------------------------
# Source state functions from 00-common.sh (for resume/state tracking)
# ---------------------------------------------------------------------------
# We only source the functions, not init_common (each script does its own init)
source ./00-common.sh 2>/dev/null || true

# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------
main() {
    echo "=========================================="
    echo "  Rancher PoC Installer"
    echo "=========================================="
    echo

    # Load config file if specified
    if [[ -n "$CONFIG_FILE" ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            echo "Error: Config file not found: $CONFIG_FILE"
            exit 1
        fi
        echo "Loading configuration from: $CONFIG_FILE"
        source "$CONFIG_FILE"
        # Export key variables
        export AUTO_MODE DRY_RUN LOG_FILE STATE_FILE AUTO_FAIL_FAST LOG_LEVEL
        # Generate 01-vars.sh from config so step scripts get the right values
        generate_vars_file
        echo "Generated 01-vars.sh from config"
    fi

    # Determine which steps to run
    local steps_to_run=()
    if [[ -n "$SELECTED_STEPS" ]]; then
        IFS=',' read -ra steps_to_run <<< "$SELECTED_STEPS"
    else
        steps_to_run=("${STEP_ORDER[@]}")
    fi

    # Interactive wizard (when not in auto mode and no config file)
    if [[ "$AUTO_MODE" != "1" ]] && [[ -z "$CONFIG_FILE" ]]; then
        run_wizard
    fi

    # Pre-flight checks
    # Set bold/normal before sourcing lang files (they use ${bold})
    bold=$(tput bold 2>/dev/null || echo '')
    normal=$(tput sgr0 2>/dev/null || echo '')
    export bold normal

    if [[ -f "01-vars.sh" ]]; then
        source ./01-vars.sh
        if [[ -d "lang" ]] && [[ -f "lang/${LANGUAGE:-fr}.sh" ]]; then
            source "./lang/${LANGUAGE:-fr}.sh"
        fi
    else
        echo "Error: 01-vars.sh not found. Run the wizard or provide a --config file."
        exit 1
    fi

    # Setup logging for auto mode
    if [[ "$AUTO_MODE" == "1" ]]; then
        echo "Mode: auto | Log: $LOG_FILE | State: $STATE_FILE"
        echo "---"
        log_info "Starting automated deployment"
        log_info "Steps to run: ${steps_to_run[*]}"
    fi

    # Run pre-flight checks
    if [[ "$AUTO_MODE" == "1" ]] && [[ "$DRY_RUN" != "1" ]]; then
        # Initialize HOSTS for preflight
        echo "$HOST_LIST" | tr ',' '\n' > hosts.list
        mapfile -t HOSTS < hosts.list
        if ! preflight_check_config; then
            echo "Pre-flight checks failed. Aborting."
            exit 1
        fi
    fi

    echo
    echo "Deployment steps:"
    local total=${#steps_to_run[@]}
    local current=0
    local failed=0

    for step in "${steps_to_run[@]}"; do
        current=$((current + 1))
        show_progress "$current" "$total" "${STEP_NAMES[$step]:-Step $step}"

        if ! run_step "$step"; then
            failed=$((failed + 1))
            if [[ "$AUTO_FAIL_FAST" == "1" ]] && [[ "$AUTO_MODE" == "1" ]]; then
                echo
                echo "Deployment stopped at step $step (AUTO_FAIL_FAST=1)"
                echo "Resume later with: ./install.sh --resume"
                exit 1
            fi
        fi
    done

    echo
    echo "=========================================="
    if [[ $failed -eq 0 ]]; then
        echo "  Deployment completed successfully!"
        if [[ "$DRY_RUN" == "1" ]]; then
            echo "  (dry-run mode — nothing was executed)"
        fi
    else
        echo "  Deployment completed with $failed error(s)"
        echo "  Check log: $LOG_FILE"
        echo "  Resume: ./install.sh --resume"
    fi
    echo "=========================================="

    [[ $failed -eq 0 ]] && exit 0 || exit 1
}

main
