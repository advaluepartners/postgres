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

function setup_nix_store_on_build_volume() {
    echo "=== Setting up Nix store on build volume ==="
    
    # Detect and mount build volume
    for device in /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/xvdf /dev/sdf; do
        if [ -b "$device" ]; then
            echo "Found build device: $device"
            
            # Format the device
            sudo mkfs.ext4 -F "$device"
            
            # Mount for Nix builds
            sudo mkdir -p /tmp/nix-build
            sudo mount "$device" /tmp/nix-build
            sudo chmod 777 /tmp/nix-build
            
            echo "Build volume mounted at /tmp/nix-build"
            break
        fi
    done
    
    df -h
}

function install_nix() {
    # Setup build volume BEFORE installing Nix
    setup_nix_store_on_build_volume
    
    # Configure Nix to use the build volume for temp files
    export TMPDIR=/tmp/nix-build
    export NIX_BUILD_TOP=/tmp/nix-build
    
    sudo su -c "curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm \
    --extra-conf \"substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com\" \
    --extra-conf \"trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=\" \
    --extra-conf \"build-dir = /tmp/nix-build\"" -s /bin/bash root
    
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
}

function execute_stage2_playbook {
    echo "POSTGRES_MAJOR_VERSION: ${POSTGRES_MAJOR_VERSION}"
    echo "GIT_SHA: ${GIT_SHA}"
    
    # Ensure build volume is available for the playbook
    export TMPDIR=/tmp/nix-build
    export NIX_BUILD_TOP=/tmp/nix-build
    
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
    sudo apt-get -y remove --purge ansible
    sudo add-apt-repository --yes --remove ppa:ansible/ansible
}

install_packages
install_nix
execute_stage2_playbook
cleanup_packages

