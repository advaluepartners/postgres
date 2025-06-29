#!/usr/bin/env bash
# shellcheck shell=bash

set -o errexit
set -o pipefail
set -o xtrace

function install_packages {
    # Setup Ansible on host VM
    sudo apt-get update && sudo apt-get install -y software-properties-common

    # Manually add GPG key with explicit keyserver
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 93C4A3FD7BB9C367

    # Add repository and install
    sudo add-apt-repository --yes ppa:ansible/ansible
    sudo apt-get update
    sudo apt-get install -y ansible

    ansible-galaxy collection install community.general
}

function setup_build_directories() {
    echo "=== Setting up build directories for Nix ==="
    
    # Create build directories on the root filesystem
    # We have 20GB on root which should be sufficient with proper cleanup
    sudo mkdir -p /var/tmp/nix-build
    sudo chmod 1777 /var/tmp/nix-build
    
    # Show current disk usage
    echo "=== Current disk usage ==="
    df -h
}

function install_nix() {
    # Setup build directories first
    setup_build_directories
    
    # Configure Nix to use our build directory and enable garbage collection
    export TMPDIR=/var/tmp/nix-build
    export NIX_BUILD_TOP=/var/tmp/nix-build
    
    sudo su -c "curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm \
    --extra-conf \"substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com\" \
    --extra-conf \"trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=\" \
    --extra-conf \"max-jobs = 4\" \
    --extra-conf \"cores = 4\" \
    --extra-conf \"keep-outputs = false\" \
    --extra-conf \"keep-derivations = false\" \
    --extra-conf \"auto-optimise-store = true\"" -s /bin/bash root
    
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
}

function execute_stage2_playbook {
    echo "POSTGRES_MAJOR_VERSION: ${POSTGRES_MAJOR_VERSION}"
    echo "GIT_SHA: ${GIT_SHA}"
    
    # Ensure build directories are still available
    export TMPDIR=/var/tmp/nix-build
    export NIX_BUILD_TOP=/var/tmp/nix-build
    
    sudo tee /etc/ansible/ansible.cfg <<EOF
[defaults]
callbacks_enabled = timer, profile_tasks, profile_roles
EOF
    sed -i 's/- hosts: all/- hosts: localhost/' /tmp/ansible-playbook/ansible/playbook.yml

    # Run Ansible playbook
    export ANSIBLE_LOG_PATH=/tmp/ansible.log && export ANSIBLE_REMOTE_TEMP=/tmp
    ansible-playbook /tmp/ansible-playbook/ansible/playbook.yml \
        --extra-vars '{"nixpkg_mode": false, "stage2_nix": true, "debpkg_mode": false}' \
        --extra-vars "git_commit_sha=${GIT_SHA}" \
        --extra-vars "psql_version=psql_${POSTGRES_MAJOR_VERSION}" \
        --extra-vars "postgresql_version=postgresql_${POSTGRES_MAJOR_VERSION}" \
        --extra-vars "nix_secret_key=${NIX_SECRET_KEY}" \
        --extra-vars "postgresql_major_version=${POSTGRES_MAJOR_VERSION}" \
        $ARGS
}

function cleanup_packages {
    # Clean up Nix build artifacts before removing ansible
    echo "=== Cleaning up Nix build artifacts ==="
    nix-collect-garbage -d || true
    rm -rf /var/tmp/nix-build/* || true
    
    # Show final disk usage
    echo "=== Final disk usage ==="
    df -h
    
    sudo apt-get -y remove --purge ansible
    sudo add-apt-repository --yes --remove ppa:ansible/ansible
}

install_packages
install_nix
execute_stage2_playbook
cleanup_packages

