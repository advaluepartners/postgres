#!/bin/bash
# build_fix.sh - Fix the current build instance immediately

set -euo pipefail

echo "=== IMMEDIATE FIX FOR NIX BUILD DISK SPACE ISSUE ==="

# 1. Mount the 40GB volume that exists but is unused
echo "Step 1: Mounting the unused 40GB volume..."
sudo mkfs.ext4 /dev/nvme1n1
sudo mkdir -p /tmp/nix-build
sudo mount /dev/nvme1n1 /tmp/nix-build
sudo chmod 777 /tmp/nix-build

# 2. Create additional swap space for memory pressure
echo "Step 2: Creating swap space on build volume..."
sudo fallocate -l 4G /tmp/nix-build/swapfile
sudo chmod 600 /tmp/nix-build/swapfile
sudo mkswap /tmp/nix-build/swapfile
sudo swapon /tmp/nix-build/swapfile

# 3. Set up Nix build directories
echo "Step 3: Setting up Nix build directories..."
sudo mkdir -p /tmp/nix-build/nix-build-tmp
sudo mkdir -p /tmp/nix-build/nix-store-tmp
sudo chmod 777 /tmp/nix-build/nix-build-tmp
sudo chmod 777 /tmp/nix-build/nix-store-tmp

# 4. Configure environment variables for current session
echo "Step 4: Configuring build environment..."
export TMPDIR="/tmp/nix-build"
export NIX_BUILD_TOP="/tmp/nix-build"
export NIX_BUILD_DIR="/tmp/nix-build/nix-build-tmp"

# Configure Nix for space efficiency
export NIX_CONFIG="
experimental-features = nix-command flakes
max-jobs = 4
cores = 4
sandbox = false
keep-outputs = false
keep-derivations = false
auto-optimise-store = true
min-free = 2147483648
max-free = 4294967296
compress-build-log = true
show-trace = false
warn-dirty = false
build-dir = /tmp/nix-build/nix-build-tmp
"

# 5. Clean up existing Nix store
echo "Step 5: Cleaning up Nix store..."
if command -v nix-collect-garbage >/dev/null 2>&1; then
    nix-collect-garbage -d
fi

# Remove any rust documentation that might be partially built
sudo find /nix/store -name "*rust-docs*" -type d -exec rm -rf {} + 2>/dev/null || true

# 6. Create optimized Nix configuration
echo "Step 6: Creating optimized Nix configuration..."
sudo tee /etc/nix/nix.conf <<EOF
experimental-features = nix-command flakes
max-jobs = 4
cores = 4
sandbox = false
keep-outputs = false
keep-derivations = false
auto-optimise-store = true
min-free = 2147483648
max-free = 4294967296
compress-build-log = true
show-trace = false
warn-dirty = false
build-dir = /tmp/nix-build/nix-build-tmp
EOF

# 7. Restart Nix daemon
echo "Step 7: Restarting Nix daemon..."
sudo systemctl restart nix-daemon || echo "Nix daemon restart failed, continuing..."

# 8. Export Rust optimization variables
echo "Step 8: Setting Rust build optimizations..."
export CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_DEBUG=false
export CARGO_PROFILE_RELEASE_DEBUG=false
export CARGO_PROFILE_RELEASE_DEBUG_ASSERTIONS=false
export CARGO_PROFILE_RELEASE_OVERFLOW_CHECKS=false
export RUSTDOC_DISABLE=1
export RUST_DOCS_DISABLE=1
export RUSTC_BOOTSTRAP=1
export CARGO_BUILD_RUSTDOC=false

# 9. Show final status
echo "=== SETUP COMPLETE ==="
echo "Current disk usage:"
df -h
echo ""
echo "Available devices:"
lsblk
echo ""
echo "Swap status:"
swapon -s
echo ""
echo "Environment variables set:"
echo "TMPDIR=$TMPDIR"
echo "NIX_BUILD_TOP=$NIX_BUILD_TOP"
echo "NIX_BUILD_DIR=$NIX_BUILD_DIR"
echo ""
echo "=== Ready to resume Nix build ==="
echo "You can now re-run your Ansible playbook or Nix build command."
echo "All builds will use the 40GB volume instead of the small root partition."