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

# function install_nix() {
#     # The 60GB volume should already be mounted at /nix/var/nix/tmp by Packer
#     if [ -d "/nix/var/nix/tmp/build" ]; then
#         export TMPDIR=/nix/var/nix/tmp/build
#         export NIX_BUILD_TOP=/nix/var/nix/tmp/build
#         echo "Using 60GB build volume at $TMPDIR"
#         df -h /nix/var/nix/tmp
#     else
#         echo "ERROR: Build volume not found at /nix/var/nix/tmp"
#         exit 1
#     fi
    
#     sudo su -c "curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm \
#     --extra-conf \"substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com\" \
#     --extra-conf \"trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=\" \
#     --extra-conf \"max-jobs = 4\" \
#     --extra-conf \"cores = 4\" \
#     --extra-conf \"keep-outputs = false\" \
#     --extra-conf \"keep-derivations = false\" \
#     --extra-conf \"auto-optimise-store = true\" \
#     --extra-conf \"build-dir = /nix/var/nix/tmp/build\"" -s /bin/bash root
    
#     . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
# }

function install_nix() {
    # The 60GB volume should already be mounted at /nix/var/nix/tmp by Packer
    if [ -d "/nix/var/nix/tmp/build" ]; then
        export TMPDIR=/nix/var/nix/tmp/build
        export NIX_BUILD_TOP=/nix/var/nix/tmp/build
        echo "Using 60GB build volume at $TMPDIR"
        df -h /nix/var/nix/tmp
    else
        echo "ERROR: Build volume not found at /nix/var/nix/tmp"
        exit 1
    fi
    
    # CRITICAL FIX: Mount the 60GB volume as the Nix store location
    sudo mkdir -p /nix/store
    sudo umount /nix/store 2>/dev/null || true
    sudo mount --bind /nix/var/nix/tmp /nix/store
    echo "Mounted 60GB volume as Nix store at /nix/store"
    
    sudo su -c "curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm \
    --extra-conf \"substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com\" \
    --extra-conf \"trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=\" \
    --extra-conf \"max-jobs = 4\" \
    --extra-conf \"cores = 4\" \
    --extra-conf \"keep-outputs = false\" \
    --extra-conf \"keep-derivations = false\" \
    --extra-conf \"auto-optimise-store = true\" \
    --extra-conf \"build-dir = /nix/var/nix/tmp/build\"" -s /bin/bash root
    
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    
    # DEBUG: Check Nix configuration after installation
    echo "=== POST-INSTALL NIX DEBUG ==="
    echo "Nix configuration:"
    cat /etc/nix/nix.conf 2>/dev/null || echo "No nix.conf found"
    echo "Nix store directory:"
    nix eval --expr 'builtins.storeDir' 2>/dev/null || echo "Cannot evaluate store dir"
    echo "Build directory setting:"
    nix show-config | grep build-dir || echo "No build-dir setting"
    echo "Disk usage after Nix install:"
    df -h
    echo "Nix store contents:"
    ls -la /nix/store | head -10 || echo "Cannot list store"
    echo "=== END DEBUG ==="
}


function execute_stage2_playbook {
    echo "POSTGRES_MAJOR_VERSION: ${POSTGRES_MAJOR_VERSION}"
    echo "GIT_SHA: ${GIT_SHA}"
    
    # Ensure build volume environment variables are set
    export TMPDIR=/nix/var/nix/tmp/build
    export NIX_BUILD_TOP=/nix/var/nix/tmp/build
    
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
    rm -rf /nix/var/nix/tmp/build/* || true
    
    # Show final disk usage
    echo "=== Final disk usage ==="
    df -h
    
    sudo apt-get -y remove --purge ansible
    sudo add-apt-repository --yes --remove ppa:ansible/ansible
}

# Add disk usage monitoring function
function monitor_disk_usage {
    echo "=== Disk usage check ==="
    df -h /nix/var/nix/tmp || echo "Build volume not mounted"
    df -h /
    echo "=== Nix store size ==="
    du -sh /nix/store 2>/dev/null || echo "Nix store not accessible"
}

install_packages
install_nix
monitor_disk_usage
execute_stage2_playbook
monitor_disk_usage
cleanup_packages

