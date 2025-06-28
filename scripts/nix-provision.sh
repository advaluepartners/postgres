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

function setup_nix_store_on_build_volume() {
    echo "=== Setting up Nix store on build volume ==="
    
    # Detect and mount build volume
    for device in /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/xvdf /dev/sdf; do
        if [ -b "$device" ]; then
            echo "Found build device: $device"
            
            # Aggressive unmounting with retries
            echo "Unmounting $device..."
            for i in {1..5}; do
                sudo umount "$device" 2>/dev/null || true
                sudo umount /tmp/nix-build 2>/dev/null || true
                sleep 1
                if ! mount | grep -q "$device"; then
                    echo "Device unmounted successfully"
                    break
                fi
                echo "Retry $i: Still mounted, trying again..."
            done
            
            # Force kill any processes using the mount point
            sudo fuser -km /tmp/nix-build 2>/dev/null || true
            sudo fuser -km "$device" 2>/dev/null || true
            
            # Final unmount attempt
            sudo umount -l "$device" 2>/dev/null || true  # lazy unmount
            sudo umount -f "$device" 2>/dev/null || true  # force unmount
            
            # Clear filesystem signatures to ensure clean format
            sudo wipefs -a "$device" 2>/dev/null || true
            
            # Wait a moment for kernel to update
            sleep 2
            
            # Format with force flag and no interaction
            echo "Formatting $device..."
            sudo mkfs.ext4 -F -q "$device"
            
            # Mount and setup
            sudo mkdir -p /tmp/nix-build
            sudo mount "$device" /tmp/nix-build
            sudo chmod 777 /tmp/nix-build
            
            # CRITICAL: Move Nix store to build volume
            sudo mkdir -p /tmp/nix-build/nix
            sudo mkdir -p /tmp/nix-build/nix/store
            sudo mkdir -p /tmp/nix-build/nix/var
            
            # Create symlink so Nix uses build volume
            if [ -d "/nix" ]; then
                sudo rm -rf /nix.backup || true
                sudo mv /nix /nix.backup || true
            fi
            sudo ln -sf /tmp/nix-build/nix /nix
            
            echo "Nix store configured to use build volume at $device"
            break
        fi
    done
    
    df -h
}

function install_nix() {
    setup_nix_store_on_build_volume
    
    sudo su -c "curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm \
    --extra-conf \"substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com\" \
    --extra-conf \"trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=\" \
    --extra-conf \"experimental-features = nix-command flakes\" " -s /bin/bash root
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
}

function execute_stage2_playbook {
    echo "POSTGRES_MAJOR_VERSION: ${POSTGRES_MAJOR_VERSION}"
    echo "GIT_SHA: ${GIT_SHA} (using local flake)"
    
    # Configure Nix for space efficiency
    sudo tee /etc/nix/nix.conf <<EOF
experimental-features = nix-command flakes
max-jobs = 4
cores = 4
sandbox = false
keep-outputs = false
keep-derivations = false
auto-optimise-store = true
compress-build-log = true
show-trace = false
warn-dirty = false
EOF
    
    # Restart Nix daemon
    sudo systemctl restart nix-daemon || echo "Nix daemon restart failed, continuing..."
    
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
        --extra-vars "postgresql_major_version=${POSTGRES_MAJOR_VERSION}" \
        $ARGS
        
    echo "=== Final disk usage ==="
    df -h
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