## ============================================================================
## 00-common.sh — Shared library for rancher-poc scripts
## Source this file, then call init_common to initialize.
## ============================================================================

# ---------------------------------------------------------------------------
# Logging functions
# ---------------------------------------------------------------------------
# Log levels: DEBUG=0, INFO=1, WARN=2, ERROR=3
declare -A _LOG_LEVELS
_LOG_LEVELS[DEBUG]=0
_LOG_LEVELS[INFO]=1
_LOG_LEVELS[WARN]=2
_LOG_LEVELS[ERROR]=3

_log() {
    local level="$1"; shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local current_level="${_LOG_LEVELS[${LOG_LEVEL:-INFO}]:-1}"
    local msg_level="${_LOG_LEVELS[$level]:-1}"
    [[ "$msg_level" -lt "$current_level" ]] && return 0

    local line="[$timestamp] [$level] $msg"

    # Console output (only if stdout is a terminal or AUTO_MODE)
    case "$level" in
        ERROR) echo -e "\033[31m${line}\033[0m" >&2 ;;
        WARN)  echo -e "\033[33m${line}\033[0m" >&2 ;;
        DEBUG) echo -e "\033[90m${line}\033[0m" ;;
        *)     echo "$line" ;;
    esac

    # File output
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "$line" >> "$LOG_FILE"
    fi
}

log_debug() { _log DEBUG "$@"; }
log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }
log_error() { _log ERROR "$@"; }

# ---------------------------------------------------------------------------
# State tracking (pipe-delimited file)
# ---------------------------------------------------------------------------
STATE_FILE="${STATE_FILE:-.rancher-poc.state}"

update_state_step() {
    local step="$1" status="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
    # Remove existing entry for this step, then append
    if [[ -f "$STATE_FILE" ]]; then
        local tmp
        tmp=$(grep -v "^${step}|" "$STATE_FILE" 2>/dev/null || true)
        echo "$tmp" > "$STATE_FILE"
    fi
    echo "${step}|${status}|${timestamp}" >> "$STATE_FILE"
}

check_state_step() {
    local step="$1"
    if [[ -f "$STATE_FILE" ]]; then
        grep "^${step}|" "$STATE_FILE" 2>/dev/null | tail -1 | cut -d'|' -f2
    fi
}

reset_state() {
    rm -f "$STATE_FILE"
    log_info "State file reset"
}

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------
validate_ip() {
    local ip="$1"
    local IFS='.'
    local -a octets=($ip)
    [[ ${#octets[@]} -ne 4 ]] && return 1
    for o in "${octets[@]}"; do
        [[ "$o" =~ ^[0-9]+$ ]] || return 1
        (( o < 0 || o > 255 )) && return 1
    done
    return 0
}

validate_fqdn() {
    local fqdn="$1"
    [[ "$fqdn" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*$ ]] && return 0
    return 1
}

validate_version() {
    local version="$1"
    # Accept formats like: v1.33.7+rke2r1, 2.13.1, v1.19.1, 4.0.1
    [[ "$version" =~ ^v?[0-9]+\.[0-9]+(\.[0-9]+)?([+\-][a-zA-Z0-9.+\-]*)?$ ]] && return 0
    return 1
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
preflight_check_config() {
    local errors=0

    log_info "Running pre-flight configuration checks..."

    # Required variables
    for var in HOST_LIST LANGUAGE; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var is not set"
            errors=$((errors + 1))
        fi
    done

    # Validate IPs if set
    if [[ -n "${RKE2_VIP_IP:-}" ]] && ! validate_ip "$RKE2_VIP_IP"; then
        log_error "RKE2_VIP_IP '$RKE2_VIP_IP' is not a valid IPv4 address"
        errors=$((errors + 1))
    fi

    # Validate FQDNs if set
    for var in LB_RANCHER_FQDN RKE2_VIP_FQDN; do
        if [[ -n "${!var:-}" ]] && ! validate_fqdn "${!var}"; then
            log_error "$var '${!var}' is not a valid FQDN"
            errors=$((errors + 1))
        fi
    done

    # Validate versions if set
    for var in RKE2_VERSION CERTMGR_VERSION RANCHER_VERSION HELM_VERSION; do
        if [[ -n "${!var:-}" ]] && ! validate_version "${!var}"; then
            log_warn "$var '${!var}' does not match expected version format"
        fi
    done

    # SSH connectivity check (optional)
    if [[ "${PREFLIGHT_SSH:-0}" == "1" ]] && [[ ${#HOSTS[@]} -gt 0 ]]; then
        log_info "Testing SSH connectivity to hosts..."
        for h in "${HOSTS[@]}"; do
            if ! ssh_host "$h" "true" >/dev/null 2>&1; then
                log_error "Cannot reach host $h via SSH"
                errors=$((errors + 1))
            else
                log_debug "SSH to $h: OK"
            fi
        done
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Pre-flight checks failed with $errors error(s)"
        return 1
    fi

    log_info "Pre-flight checks passed"
    return 0
}

# ---------------------------------------------------------------------------
# Package manager detection
# ---------------------------------------------------------------------------
detect_pkg_manager() {
    # If already set (e.g. from config file), keep it
    if [[ -n "${pkg_mgr_type:-}" ]]; then
        log_debug "Package manager already set: $pkg_mgr_type"
        return 0
    fi

    # Auto-detect
    local detected=""
    if command -v zypper >/dev/null 2>&1; then
        detected="zypper"
    elif command -v yum >/dev/null 2>&1; then
        detected="yum"
    elif command -v apt-get >/dev/null 2>&1; then
        detected="apt"
    fi

    if [[ "${AUTO_MODE:-0}" == "1" ]]; then
        # In auto mode, use detected value or fail
        if [[ -n "$detected" ]]; then
            pkg_mgr_type="$detected"
            log_info "Auto-detected package manager: $pkg_mgr_type"
        else
            log_error "Could not auto-detect package manager"
            return 1
        fi
    else
        # Interactive mode: suggest detected, allow override
        if [[ -n "$detected" ]]; then
            echo "${bold:-}Detected package manager: $detected${normal:-}"
        fi
        while true; do
            read -p "${bold:-}Package manager type? (zypper/yum/apt)${normal:-} [${detected:-}] " pkg_mgr_type
            pkg_mgr_type="${pkg_mgr_type:-$detected}"
            case "$pkg_mgr_type" in
                zypper|yum|apt)
                    echo "$pkg_mgr_type selected."
                    echo
                    break ;;
                *) echo "Please answer: zypper or yum or apt." ;;
            esac
        done
    fi
    export pkg_mgr_type
}

# ---------------------------------------------------------------------------
# Wait for pods (replacement for interactive watch)
# ---------------------------------------------------------------------------
wait_for_pods() {
    local namespace="${1:-kube-system}"
    local timeout="${2:-300}"
    local interval="${3:-10}"
    local elapsed=0

    log_info "Waiting for pods in namespace '$namespace' to be ready (timeout: ${timeout}s)..."

    while (( elapsed < timeout )); do
        local not_ready
        not_ready=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null \
            | grep -v -E '(Running|Completed|Succeeded)' \
            | grep -v -E '([0-9]+)/\1' \
            | wc -l)

        if [[ "$not_ready" -eq 0 ]] && kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep -q .; then
            log_info "All pods in namespace '$namespace' are ready"
            return 0
        fi

        log_debug "Pods not ready in '$namespace': $not_ready (elapsed: ${elapsed}s)"
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    log_error "Timeout waiting for pods in namespace '$namespace' after ${timeout}s"
    kubectl get pods -n "$namespace" 2>/dev/null || true
    return 1
}

# ---------------------------------------------------------------------------
# SSH connect test (centralized — was duplicated in scripts 02, 03, 04)
# ---------------------------------------------------------------------------
COMMAND_SSH_CONNECT_TEST() {
    local success_count=0
    local fail_count=0
    local failed_hosts=()

    echo "${bold:-}Testing SSH connections...${normal:-}"
    echo

    for h in "${HOSTS[@]}"; do
        echo -n "Testing $h... "

        if ssh_host "$h" "hostname" >/dev/null 2>&1; then
            local remote_hostname
            remote_hostname=$(ssh_host "$h" "hostname" 2>/dev/null)
            echo "OK (hostname: $remote_hostname)"
            success_count=$((success_count + 1))
        else
            echo "FAILED"
            fail_count=$((fail_count + 1))
            failed_hosts+=("$h")
        fi
    done

    echo
    echo "${bold:-}=== Connection Test Summary ===${normal:-}"
    echo "  Successful: $success_count"
    echo "  Failed: $fail_count"

    if [[ $fail_count -gt 0 ]]; then
        echo
        echo "${bold:-}Failed hosts:${normal:-}"
        printf '  - %s\n' "${failed_hosts[@]}"
        return 1
    fi

    echo
    echo "Note: Domain in use must not be using *.local"
    return 0
}

# ---------------------------------------------------------------------------
# init_common() — must be called after sourcing this file
# ---------------------------------------------------------------------------
init_common() {
    # Terminal formatting (safe for non-interactive / piped usage)
    if [[ -t 1 ]]; then
        bold=$(tput bold 2>/dev/null || echo '')
        normal=$(tput sgr0 2>/dev/null || echo '')
        # Only clear in interactive non-auto mode
        if [[ "${AUTO_MODE:-0}" != "1" ]]; then
            clear
        fi
    else
        bold=""
        normal=""
    fi
    export bold normal

    # Setup logging
    if [[ -n "${LOG_FILE:-}" ]]; then
        # Ensure log directory exists
        local log_dir
        log_dir=$(dirname "$LOG_FILE")
        [[ -d "$log_dir" ]] || mkdir -p "$log_dir"
    fi

    # Parse HOST_LIST into HOSTS array
    echo "${TXT_READ_HOST_FILE:=Reading hosts list from variable} $HOST_LIST"
    echo "$HOST_LIST" | tr ',' '\n' > hosts.list
    mapfile -t HOSTS < hosts.list
    echo "${TXT_LIST_HOSTS:=List of remote target hosts}:"
    echo
    printf '%s\n' "${HOSTS[@]}"
    echo

    log_debug "init_common completed — ${#HOSTS[@]} host(s) loaded"
}

# ---------------------------------------------------------------------------
# SSH helpers
# ---------------------------------------------------------------------------
ssh_host() {
    local host="$1"
    local command="$2"
    if [[ -n "${SSH_USER:-}" ]]; then
        ssh "${SSH_USER}@${host}" "$command"
    else
        ssh "$host" "$command"
    fi
}

scp_host() {
    local source="$1"
    local destination="$2"
    if [[ -n "${SSH_USER:-}" ]]; then
        if [[ "$destination" =~ ^([^:]+):(.*)$ ]]; then
            local host="${BASH_REMATCH[1]}"
            local path="${BASH_REMATCH[2]}"
            if [[ -n "$path" ]]; then
                scp "$source" "${SSH_USER}@${host}:${path}"
            else
                scp "$source" "${SSH_USER}@${host}:"
            fi
        else
            scp "$source" "$destination"
        fi
    else
        scp "$source" "$destination"
    fi
}

# ---------------------------------------------------------------------------
# question_yn() — auto-mode aware
# ---------------------------------------------------------------------------
question_yn() {
    local description="$1"
    local command="$2"

    if [[ "${AUTO_MODE:-0}" == "1" ]]; then
        log_info "AUTO: Executing — $description"
        if [[ "${DRY_RUN:-0}" == "1" ]]; then
            log_info "DRY-RUN: Would execute: $command"
            return 0
        fi
        if $command; then
            log_info "AUTO: Success — $command"
        else
            local rc=$?
            log_error "AUTO: Failed (rc=$rc) — $command"
            if [[ "${AUTO_FAIL_FAST:-0}" == "1" ]]; then
                log_error "AUTO_FAIL_FAST is set, aborting"
                exit $rc
            fi
        fi
        return 0
    fi

    # Interactive mode (original behavior)
    while true; do
        echo -e "${bold}---\n $description ${normal}"
        echo
        read -p " ${bold}${TXT_QUESTION_OPTIONS:=Choose an option:} ${normal}${TXT_QUESTION_EXECUTE:=[E]xecute} / ${TXT_QUESTION_SKIP:=[P]asser} / ${TXT_QUESTION_SHOW_CODE:=[C]ode} ${normal}" choice
        echo
        case $choice in
            [Ee]* )
                echo -e "${bold}${TXT_EXECUTING:=Executing...}${normal}"
                $command
                echo
                read -rsp "${TXT_PRESS_KEY_CONTINUE:=Press a key to continue...}" -n1 key
                echo
                break;;
            [PpSs]* )
                echo "${TXT_STEP_SKIPPED:=Step skipped.}"
                echo
                break;;
            [Cc]* )
                echo -e "${bold}${TXT_COMMAND_CODE:=Command code:}${normal}"
                declare -f $command
                echo
                continue;;
            * )
                echo "${TXT_INVALID_CHOICE:=Invalid choice. Please answer E (Execute), P (Skip) or C (Code).}"
                echo;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Package check functions
# ---------------------------------------------------------------------------
COMMAND_CHECK_PACKAGE_RPM_LOCAL() {
for i in $@;do echo "${TXT_CHECK_PACKAGE_PRESENT:=Checking if package is installed}: ${bold}$i${normal}"
if sudo rpm -q $i
then
  echo "${bold}$i${normal} ${TXT_IS_PRESENT:=is present}. OK!";echo
else
  echo "${bold}$i${normal} ${TXT_NOT_PRESENT:=is absent}. MISSING! Trying to remediate..."
  echo "sudo rpm -q ${bold}$i${normal}: 'not installed'"
    if [[ $pkg_mgr_type == 'zypper' ]] ; then
      sudo zypper in -y $i
    elif [[ $pkg_mgr_type == 'yum' ]] ; then
      sudo yum install -y $i
    else
      echo "Package manager should be zypper or yum"
    fi
fi
done
}

COMMAND_CHECK_PACKAGE_RPM() {
for h in "${HOSTS[@]}"; do
  echo -e "\n${bold}$h${normal}"
  for i in $@;do echo "${TXT_CHECK_PACKAGE_PRESENT:=Checking if package is installed}: ${bold}$i${normal}"
  if ssh_host "$h" "sudo rpm -q $i"
  then
    echo "${bold}$i${normal} ${TXT_IS_PRESENT:=is present}. OK!";echo
  else
    echo "${bold}$i${normal} ${TXT_NOT_PRESENT:=is absent}. MISSING! Trying to remediate..."
    echo "sudo rpm -q ${bold}$i${normal}: 'not installed'"
    if [[ $pkg_mgr_type == 'zypper' ]] ; then
      ssh_host "$h" "sudo zypper in -y $i"
    elif [[ $pkg_mgr_type == 'yum' ]] ; then
      ssh_host "$h" "sudo yum install -y $i"
    else
      echo "Package manager should be zypper or yum"
    fi
  fi
  done
done
}

COMMAND_CHECK_PACKAGE_DPKG_LOCAL() {
for i in $@;do echo "${TXT_CHECK_PACKAGE_PRESENT:=Checking if package is installed}: ${bold}$i${normal}"
if sudo dpkg-query --show $i
then
  echo "${bold}$i${normal} ${TXT_IS_PRESENT:=is present}. OK!";echo
else
  echo "${bold}$i${normal} ${TXT_NOT_PRESENT:=is absent}. MISSING! Trying to remediate..."
  echo "sudo dpkg-query --show ${bold}$i${normal}: 'not installed'"
    if [[ $pkg_mgr_type == 'apt' ]] ; then
      sudo apt-get install -y $i
    else
      echo "Package manager should be apt"
    fi
fi
done
}

COMMAND_CHECK_PACKAGE_DPKG() {
for h in "${HOSTS[@]}"; do
  echo -e "\n${bold}$h${normal}"
  for i in $@;do echo "${TXT_CHECK_PACKAGE_PRESENT:=Checking if package is installed}: ${bold}$i${normal}"
  if ssh_host "$h" "sudo dpkg-query --show $i"
  then
    echo "${bold}$i${normal} ${TXT_IS_PRESENT:=is present}. OK!";echo
  else
    echo "${bold}$i${normal} ${TXT_NOT_PRESENT:=is absent}. MISSING! Trying to remediate..."
    echo "sudo dpkg-query --show ${bold}$i${normal}: 'not installed'"
    if [[ $pkg_mgr_type == 'apt' ]] ; then
      ssh_host "$h" "sudo apt-get install -y $i"
    else
      echo "Package manager should be apt"
    fi
  fi
  done
done
}

# ---------------------------------------------------------------------------
# propose_next_script() — auto-mode aware
# ---------------------------------------------------------------------------
propose_next_script() {
    local next_script="$1"
    local description="${2:-}"

    echo
    echo "-- ${TXT_END:=END} --"

    if [[ "${AUTO_MODE:-0}" == "1" ]]; then
        log_info "Completed. Next step: $next_script"
        return 0
    fi

    if [[ -f "$next_script" ]]; then
        if [[ -n "$description" ]]; then
            echo "${TXT_NEXT_STEP:=Next step}: $next_script"
            echo "  ${description}"
        else
            echo "${TXT_NEXT_STEP:=Next step}: $next_script"
        fi
        echo
        read -p "Do you want to execute $next_script now? (Y/n): " execute_next
        if [[ ! "$execute_next" =~ ^[Nn]$ ]]; then
            echo
            echo "${bold}Executing $next_script...${normal}"
            echo
            bash "$next_script"
        else
            echo
            echo "You can execute it later with: bash $next_script"
        fi
    else
        echo "${TXT_NEXT_STEP:=Next step}: $next_script"
        echo "  (Script not found in current directory)"
        echo
        echo "You can execute it manually when ready."
    fi
}
