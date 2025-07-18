#!/usr/bin/env bash
# shellcheck shell=bash

# Enhanced error handling and logging
set -o errexit
set -o pipefail
set -o xtrace

# Set up logging to capture all output
exec 1> >(tee -a /tmp/nix-provision.log)
exec 2>&1

# Trap handler for cleanup and proper exit
cleanup() {
    local exit_code=$?
    echo "=== Script cleanup, exit code: $exit_code ==="
    
    # Ensure proper permissions
    if [ -d "/nix" ]; then
        sudo chown -R ubuntu:ubuntu /nix 2>/dev/null || true
    fi
    
    # Log final state
    echo "=== Final disk usage ==="
    df -h 2>/dev/null || true
    
    exit $exit_code
}
trap cleanup EXIT INT TERM

function install_packages {
    echo "=== Installing required packages ==="
    # Setup Ansible on host VM with better error handling
    sudo apt-get update && sudo apt-get install -y software-properties-common

    # Manually add GPG key with explicit keyserver and retry logic
    for i in {1..3}; do
        if sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 93C4A3FD7BB9C367; then
            break
        fi
        echo "GPG key retrieval attempt $i failed, retrying..."
        sleep 5
    done

    # Add repository and install with verification
    sudo add-apt-repository --yes ppa:ansible/ansible
    sudo apt-get update
    sudo apt-get install -y ansible

    # Verify ansible installation
    ansible --version || {
        echo "ERROR: Ansible installation failed"
        exit 1
    }

    ansible-galaxy collection install community.general
    echo "=== Package installation completed ==="
}

function install_nix() {
    echo "=== Installing Nix with enhanced error handling ==="
    
    # DEFINITIVE FIX: Verify 60GB volume is mounted at /nix (not /nix/store)
    if ! mountpoint -q /nix; then
        echo "ERROR: /nix not mounted properly"
        exit 1
    fi
    
    echo "Installing Nix with 60GB volume mounted at /nix"
    df -h /nix
    
    # Verify /nix/store exists on the mounted filesystem
    if [ ! -d "/nix/store" ]; then
        echo "WARNING: /nix/store directory not found, creating it"
        sudo mkdir -p /nix/store
        sudo chmod 1775 /nix/store
    fi
    
    # Install Nix with enhanced configuration and error handling
    echo "=== Starting Nix installation ==="
    if ! sudo su -c "curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm \
    --extra-conf \"substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com\" \
    --extra-conf \"trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=\" \
    --extra-conf \"max-jobs = 2\" \
    --extra-conf \"cores = 2\" \
    --extra-conf \"keep-outputs = false\" \
    --extra-conf \"keep-derivations = false\" \
    --extra-conf \"auto-optimise-store = true\"" -s /bin/bash root; then
        echo "ERROR: Nix installation failed"
        exit 1
    fi
    
    # ENHANCED: Source Nix environment with proper error handling and SIGPIPE prevention
    echo "=== Sourcing Nix environment ==="
    if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
        # Use a more robust method to source the environment
        set +o pipefail  # Temporarily disable pipefail to prevent SIGPIPE issues
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || {
            echo "WARNING: Nix environment sourcing had minor issues, but continuing..."
            # Try alternative sourcing method
            . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh || true
        }
        set -o pipefail  # Re-enable pipefail
    else
        echo "ERROR: Nix environment script not found"
        exit 1
    fi
    
    # Verify Nix installation with timeout
    echo "=== Nix Installation Verification ==="
    timeout 30 nix-store --version || {
        echo "ERROR: Nix verification failed"
        exit 1
    }
    
    # Check store accessibility (avoid SIGPIPE from head command)
    if ! ls -la /nix/store >/dev/null 2>&1; then
        echo "ERROR: Nix store not accessible"
        exit 1
    fi

    # Show store contents for verification (separate command to avoid pipeline issues)
    echo "=== Nix store contents (first 5 entries) ==="
    ls -la /nix/store 2>/dev/null | head -5 || echo "Could not list store contents"
        
        echo "=== Nix installation verification completed ==="
    }

function execute_stage2_playbook {
    echo "=== Executing Stage 2 Ansible Playbook ==="
    echo "POSTGRES_MAJOR_VERSION: ${POSTGRES_MAJOR_VERSION}"
    echo "GIT_SHA: ${GIT_SHA}"
    
    # Configure Ansible with better settings
    sudo tee /etc/ansible/ansible.cfg <<EOF
[defaults]
callbacks_enabled = timer, profile_tasks, profile_roles
timeout = 30
retry_files_enabled = False
host_key_checking = False
EOF

    # Modify playbook for localhost execution
    sed -i 's/- hosts: all/- hosts: localhost/' /tmp/ansible-playbook/ansible/playbook.yml

    # Set up environment for Ansible execution
    export ANSIBLE_LOG_PATH=/tmp/ansible.log
    export ANSIBLE_REMOTE_TEMP=/tmp
    export ANSIBLE_LOCAL_TEMP=/tmp
    
    # Execute playbook with enhanced error handling
    echo "=== Running Ansible playbook ==="
    if ! ansible-playbook /tmp/ansible-playbook/ansible/playbook.yml \
        --extra-vars '{"nixpkg_mode": false, "stage2_nix": true, "debpkg_mode": false}' \
        --extra-vars "git_commit_sha=${GIT_SHA}" \
        --extra-vars "psql_version=psql_${POSTGRES_MAJOR_VERSION}" \
        --extra-vars "postgresql_version=postgresql_${POSTGRES_MAJOR_VERSION}" \
        --extra-vars "nix_secret_key=${NIX_SECRET_KEY:-}" \
        --extra-vars "postgresql_major_version=${POSTGRES_MAJOR_VERSION}" \
        $ARGS; then
        echo "ERROR: Ansible playbook execution failed"
        echo "=== Ansible log tail ==="
        tail -50 /tmp/ansible.log 2>/dev/null || echo "No ansible log available"
        exit 1
    fi
    
    echo "=== Ansible playbook execution completed ==="
}

function cleanup_packages {
    echo "=== Cleaning up packages and artifacts ==="
    
    # Clean up Nix build artifacts with error handling
    echo "=== Cleaning up Nix build artifacts ==="
    set +o errexit  # Allow nix commands to fail gracefully
    
    if command -v nix-collect-garbage >/dev/null 2>&1; then
        nix-collect-garbage -d || {
            echo "WARNING: Nix garbage collection failed, continuing..."
        }
    fi
    
    set -o errexit  # Re-enable errexit
    
    # Show final disk usage
    echo "=== Final disk usage ==="
    df -h 2>/dev/null || true
    
    # Clean up Ansible
    sudo apt-get -y remove --purge ansible || {
        echo "WARNING: Ansible removal failed, continuing..."
    }
    sudo add-apt-repository --yes --remove ppa:ansible/ansible || {
        echo "WARNING: PPA removal failed, continuing..."
    }
    
    echo "=== Package cleanup completed ==="
}

function monitor_disk_usage {
    echo "=== Disk usage monitoring ==="
    df -h /nix 2>/dev/null || echo "Nix mount not accessible"
    df -h / 2>/dev/null || echo "Root filesystem not accessible"
    echo "=== Nix total size ==="
    du -sh /nix 2>/dev/null || echo "Nix mount not accessible"
}

# Main execution flow with comprehensive error handling
main() {
    echo "=== Starting Nix provisioning script ==="
    echo "=== Environment Variables ==="
    env | grep -E "(POSTGRES|GIT|NIX)" || echo "No relevant environment variables found"
    
    install_packages
    install_nix
    monitor_disk_usage
    execute_stage2_playbook
    monitor_disk_usage
    cleanup_packages
    
    echo "=== Nix provisioning script completed successfully ==="
}

# Execute main function
main "$@"

