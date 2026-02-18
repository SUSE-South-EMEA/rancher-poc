#!/bin/bash

### Source variables
source ./01-vars.sh
source ./lang/$LANGUAGE.sh
source ./00-common.sh
init_common

# Detect package manager (replaces manual while/read loop)
detect_pkg_manager

## SSH KEYS CREATION
## Creates SSH key pair if it doesn't exist
## Supports ED25519 (preferred) and RSA fallback
COMMAND_SSH_KEYS() {
    local key_type="${SSH_KEY_TYPE:-ed25519}"
    local key_size="${SSH_KEY_SIZE:-}"
    local key_file="${SSH_KEY_FILE:-$HOME/.ssh/id_${key_type}}"
    local comment="${SSH_KEY_COMMENT:-$(whoami)@$(hostname)}"

    # Check if key already exists
    if [[ -f "$key_file" ]]; then
        echo "${bold}SSH key already exists: $key_file${normal}"
        if [[ "${AUTO_MODE:-0}" == "1" ]]; then
            echo "Keeping existing key (auto mode)."
            return 0
        fi
        read -p "Do you want to overwrite it? (y/N): " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            echo "Keeping existing key."
            return 0
        fi
        rm -f "$key_file" "${key_file}.pub"
    fi

    # Create .ssh directory if it doesn't exist
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # Generate key based on type
    echo "${bold}Generating SSH key pair...${normal}"
    if [[ "$key_type" == "ed25519" ]]; then
        ssh-keygen -t ed25519 -C "$comment" -f "$key_file" -N "" -q
        echo "ED25519 key generated (recommended, more secure)"
    elif [[ "$key_type" == "rsa" ]]; then
        local size="${key_size:-4096}"
        ssh-keygen -t rsa -b "$size" -C "$comment" -f "$key_file" -N "" -q
        echo "RSA key generated (${size} bits)"
    else
        echo "Error: Unsupported key type: $key_type"
        return 1
    fi

    # Set proper permissions
    chmod 600 "$key_file"
    chmod 644 "${key_file}.pub"

    echo "SSH key pair created: $key_file"
    echo "  Public key: ${key_file}.pub"

    # Display public key for manual copy if needed
    echo
    echo "${bold}Public key content:${normal}"
    cat "${key_file}.pub"
    echo
}

## SSH KEYS DEPLOY - Robust method without expect
## Copies public key to remote hosts using multiple fallback methods
COMMAND_SSH_DEPLOY() {
    local key_file="${SSH_KEY_FILE:-$HOME/.ssh/id_${SSH_KEY_TYPE:-ed25519}}"
    local pub_key_file="${key_file}.pub"

    # Check if public key exists
    if [[ ! -f "$pub_key_file" ]]; then
        echo "${bold}Error: Public key not found: $pub_key_file${normal}"
        echo "Please run key creation first."
        return 1
    fi

    local pub_key_content
    pub_key_content=$(cat "$pub_key_file")

    # Check if sshpass is available (optional, for automation)
    local use_sshpass=false
    if command -v sshpass >/dev/null 2>&1; then
        if [[ "${AUTO_MODE:-0}" == "1" ]]; then
            use_sshpass=true
        else
            read -p "sshpass is available. Use it for automated password entry? (y/N): " use_sshpass_confirm
            if [[ "$use_sshpass_confirm" =~ ^[Yy]$ ]]; then
                use_sshpass=true
            fi
        fi
    fi

    # Get password once
    local password=""
    if [[ "$use_sshpass" == false ]]; then
        echo
        echo "${bold}You will be prompted for the password for each host.${normal}"
        echo "Password will be used to copy the public key to authorized_keys."
    else
        if [[ -n "${SSH_PASSWORD:-}" ]]; then
            password="$SSH_PASSWORD"
        else
            read -s -p "${TXT_ENTER_CLIENT_PWD:=Please enter target hosts SSH password}: " password
            echo
        fi
    fi

    # Process each host
    local success_count=0
    local fail_count=0
    local failed_hosts=()

    for h in "${HOSTS[@]}"; do
        echo
        echo "${bold}Processing host: $h${normal}"

        # Determine SSH target
        local ssh_target
        if [[ -n "${SSH_USER:-}" ]]; then
            ssh_target="${SSH_USER}@${h}"
        else
            ssh_target="$h"
        fi

        # Check if key is already installed
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o PasswordAuthentication=no \
           "$ssh_target" "test -f ~/.ssh/authorized_keys && grep -qF '${pub_key_content}' ~/.ssh/authorized_keys" 2>/dev/null; then
            echo "  Public key already installed on $h"
            ((success_count++))
            continue
        fi

        # Method 1: Try ssh-copy-id with password (if sshpass available)
        local key_installed=false

        if [[ "$use_sshpass" == true ]]; then
            echo "  Attempting automated key copy with sshpass..."
            if sshpass -p "$password" ssh-copy-id \
                -o StrictHostKeyChecking=no \
                -o PasswordAuthentication=yes \
                -o PreferredAuthentications=password \
                -f \
                "$ssh_target" 2>/dev/null; then
                echo "  Key successfully copied to $h (automated)"
                key_installed=true
                ((success_count++))
            fi
        fi

        # Method 2: Manual copy using ssh (fallback or if sshpass not used)
        if [[ "$key_installed" == false ]]; then
            echo "  Attempting manual key copy..."

            # Create .ssh directory and authorized_keys if needed
            # Then append public key
            local ssh_command="mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
                (test -f ~/.ssh/authorized_keys || touch ~/.ssh/authorized_keys) && \
                chmod 600 ~/.ssh/authorized_keys && \
                echo '${pub_key_content}' >> ~/.ssh/authorized_keys && \
                chmod 600 ~/.ssh/authorized_keys && \
                echo 'Key installed successfully'"

            if [[ "$use_sshpass" == true ]]; then
                if sshpass -p "$password" ssh \
                    -o StrictHostKeyChecking=no \
                    -o PasswordAuthentication=yes \
                    -o PreferredAuthentications=password \
                    "$ssh_target" "$ssh_command" 2>/dev/null; then
                    echo "  Key successfully copied to $h (manual method)"
                    key_installed=true
                    ((success_count++))
                fi
            else
                # Interactive password prompt
                echo "  Please enter password for $ssh_target when prompted:"
                if ssh -o StrictHostKeyChecking=no \
                    -o PasswordAuthentication=yes \
                    "$ssh_target" "$ssh_command" 2>/dev/null; then
                    echo "  Key successfully copied to $h"
                    key_installed=true
                    ((success_count++))
                fi
            fi
        fi

        # If still not installed, mark as failed
        if [[ "$key_installed" == false ]]; then
            echo "  Failed to copy key to $h"
            ((fail_count++))
            failed_hosts+=("$h")
        fi
    done

    # Clear password from memory
    unset password

    # Summary
    echo
    echo "${bold}=== Deployment Summary ===${normal}"
    echo "  Successful: $success_count"
    echo "  Failed: $fail_count"

    if [[ $fail_count -gt 0 ]]; then
        echo
        echo "${bold}Failed hosts:${normal}"
        printf '  - %s\n' "${failed_hosts[@]}"
        echo
        echo "You can manually copy your public key to these hosts:"
        echo "  cat $pub_key_file | ssh $ssh_target 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'"
        return 1
    fi

    return 0
}

##################### BEGIN PRE-CHECK LOCAL PACKAGES ##################################
# Check for required packages
if [[ $pkg_mgr_type == 'apt' ]]; then
    question_yn "${DESC_CHECK_PACKAGE:=Local deployment system : check if required packages are installed?}" "COMMAND_CHECK_PACKAGE_DPKG_LOCAL curl sudo"
else
    question_yn "${DESC_CHECK_PACKAGE_RPM_LOCAL:=Local deployment system : check if required packages are installed?}" "COMMAND_CHECK_PACKAGE_RPM_LOCAL curl sudo"
fi

# Check and optionally install sshpass
if ! command -v sshpass >/dev/null 2>&1; then
    if [[ "${AUTO_MODE:-0}" != "1" ]]; then
        echo
        echo "${bold}Note:${normal} sshpass is not installed (optional but recommended)."
        echo "  The script will work without it, but you'll need to enter passwords interactively for each host."
        echo "  With sshpass, you can automate the password entry."
        echo
        read -p "Do you want to install sshpass now? (Y/n): " install_sshpass
        if [[ ! "$install_sshpass" =~ ^[Nn]$ ]]; then
            echo "${bold}Installing sshpass...${normal}"
            case $pkg_mgr_type in
                zypper)
                    if sudo zypper install -y sshpass 2>/dev/null; then
                        echo "sshpass installed successfully"
                    else
                        echo "Failed to install sshpass. You can install it manually later with: sudo zypper install sshpass"
                    fi
                    ;;
                yum)
                    if sudo yum install -y sshpass 2>/dev/null; then
                        echo "sshpass installed successfully"
                    else
                        echo "Failed to install sshpass. You can install it manually later with: sudo yum install sshpass"
                    fi
                    ;;
                apt)
                    if sudo apt-get install -y sshpass 2>/dev/null; then
                        echo "sshpass installed successfully"
                    else
                        echo "Failed to install sshpass. You can install it manually later with: sudo apt-get install sshpass"
                    fi
                    ;;
                *)
                    echo "Unknown package manager. Please install sshpass manually."
                    ;;
            esac
            echo
        else
            echo "Skipping sshpass installation. You can install it later if needed."
            echo
        fi
    else
        log_info "sshpass not installed, skipping interactive install (auto mode)"
    fi
else
    echo "${bold}sshpass is already installed.${normal}"
    echo
fi
##################################################################################

##################### BEGIN SSH KEYS EXCHANGE ###################################
question_yn "${DESC_SSH_KEYS:=Create a local SSH key pair?}" COMMAND_SSH_KEYS
question_yn "${DESC_SSH_DEPLOY:=Push public key to nodes?}" COMMAND_SSH_DEPLOY
question_yn "${DESC_SSH_CONNECT_TEST:=Test SSH connection to nodes?}" COMMAND_SSH_CONNECT_TEST
##################################################################################

propose_next_script "03-os_preparation_PACKAGES.sh" "OS preparation and packages installation"
