#!/usr/bin/env bash
# shellcheck shell=bash

set -o errexit
set -o pipefail
set -o xtrace

function install_packages {
	# Setup Ansible on host VM
	sudo apt-get update && sudo apt-get install software-properties-common -y
	sudo add-apt-repository --yes --update ppa:ansible/ansible && sudo apt-get install ansible -y
	ansible-galaxy collection install community.general
}

function install_nix() {
    sudo su -c "curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm \
    --extra-conf \"substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com\" \
    --extra-conf \"trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=\" " -s /bin/bash root
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
}

function execute_stage2_playbook {
    echo "POSTGRES_MAJOR_VERSION: ${POSTGRES_MAJOR_VERSION}"
    echo "GIT_SHA: ${GIT_SHA} (using local flake)"
    
    # Configure Nix for optimized builds with limited disk space
    export NIX_CONFIG="
      max-jobs = 2
      cores = 2
      sandbox = false
      keep-outputs = false
      keep-derivations = false
      auto-optimise-store = true
      min-free = 1073741824
      max-free = 2147483648
    "
    
    # Set temporary directory to use additional volume if available
    if [ -d "/tmp/nix-build" ]; then
        export TMPDIR="/tmp/nix-build"
        export NIX_BUILD_TOP="/tmp/nix-build"
    fi
    
    # Optimize Rust builds - disable documentation
    export CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_DEBUG=false
    export RUSTDOC_DISABLE=1
    export RUST_DOCS_DISABLE=1
    
    sudo tee /etc/ansible/ansible.cfg <<EOF
[defaults]
callbacks_enabled = timer, profile_tasks, profile_roles
EOF
    sed -i 's/- hosts: all/- hosts: localhost/' /tmp/ansible-playbook/ansible/playbook.yml

    # Run Ansible playbook with optimized settings
    export ANSIBLE_LOG_PATH=/tmp/ansible.log && export ANSIBLE_REMOTE_TEMP=/tmp
    ansible-playbook /tmp/ansible-playbook/ansible/playbook.yml \
        --extra-vars '{"nixpkg_mode": false, "stage2_nix": true, "debpkg_mode": false}' \
        --extra-vars "git_commit_sha=${GIT_SHA}" \
        --extra-vars "psql_version=psql_${POSTGRES_MAJOR_VERSION}" \
        --extra-vars "postgresql_version=postgresql_${POSTGRES_MAJOR_VERSION}" \
        --extra-vars "nix_secret_key=${NIX_SECRET_KEY}" \
        --extra-vars "postgresql_major_version=${POSTGRES_MAJOR_VERSION}" \
        $ARGS
        
    # Clean up build artifacts to save space
    if command -v nix-collect-garbage >/dev/null 2>&1; then
        echo "Cleaning up Nix store to free disk space..."
        nix-collect-garbage -d
    fi
    
    # Clean up temporary build directory
    if [ -d "/tmp/nix-build" ] && [ "$TMPDIR" = "/tmp/nix-build" ]; then
        echo "Cleaning up temporary build directory..."
        rm -rf /tmp/nix-build/* || true
    fi
}

function cleanup_packages {
    sudo apt-get -y remove --purge ansible
    sudo add-apt-repository --yes --remove ppa:ansible/ansible
    
    # Final cleanup
    sudo apt-get autoremove -y
    sudo apt-get autoclean
}

install_packages
install_nix
execute_stage2_playbook
cleanup_packages
