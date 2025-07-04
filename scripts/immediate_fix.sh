#!/bin/bash
set -euo pipefail

echo "=== PostgreSQL AMI Fix Script ==="
echo "This script fixes the missing Nix volume mount issue"

# Function to print colored output
print_status() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

print_status "Step 1: Checking 60GB Nix volume..."
if ! lsblk | grep -q "nvme2n1.*60G"; then
    print_error "60GB volume (nvme2n1) not found!"
    exit 1
fi

print_status "Step 2: Getting volume UUID..."
NIX_UUID=$(sudo blkid -s UUID -o value /dev/nvme2n1)
if [ -z "$NIX_UUID" ]; then
    print_error "Could not get UUID for /dev/nvme2n1"
    exit 1
fi
print_status "Volume UUID: $NIX_UUID"

print_status "Step 3: Mounting Nix volume..."
sudo mount /dev/nvme2n1 /nix
if [ $? -eq 0 ]; then
    print_status "Nix volume mounted successfully"
else
    print_error "Failed to mount Nix volume"
    exit 1
fi

print_status "Step 4: Adding persistent fstab entry..."
if ! grep -q "$NIX_UUID" /etc/fstab; then
    echo "UUID=$NIX_UUID /nix ext4 defaults,discard 0 2" | sudo tee -a /etc/fstab
    print_status "Fstab entry added"
else
    print_status "Fstab entry already exists"
fi

print_status "Step 5: Verifying Nix store accessibility..."
if [ -d "/nix/store" ] && [ "$(ls -A /nix/store)" ]; then
    print_status "Nix store is accessible with $(ls /nix/store | wc -l) packages"
else
    print_error "Nix store is empty or inaccessible"
    exit 1
fi

print_status "Step 6: Verifying PostgreSQL binaries..."
if [ -f "/var/lib/postgresql/.nix-profile/bin/postgres" ]; then
    print_status "PostgreSQL binary found: $(/var/lib/postgresql/.nix-profile/bin/postgres --version)"
else
    print_error "PostgreSQL binary not found in Nix profile"
    exit 1
fi

print_status "Step 7: Creating Nix daemon service..."
sudo tee /etc/systemd/system/nix-daemon.service > /dev/null << 'EOF'
[Unit]
Description=Nix daemon service
After=local-fs.target

[Service]
Type=forking
ExecStart=/nix/var/nix/daemon-package/bin/nix-daemon --daemon
KillMode=process
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

print_status "Step 8: Creating Nix socket service..."
sudo tee /etc/systemd/system/nix-daemon.socket > /dev/null << 'EOF'
[Unit]
Description=Nix daemon socket

[Socket]
ListenStream=/nix/var/nix/daemon-socket/socket

[Install]
WantedBy=sockets.target
EOF

print_status "Step 9: Enabling Nix daemon services..."
sudo systemctl daemon-reload
sudo systemctl enable nix-daemon.service
sudo systemctl enable nix-daemon.socket
sudo systemctl start nix-daemon.socket
sudo systemctl start nix-daemon.service

print_status "Step 10: Updating PostgreSQL service dependencies..."
sudo sed -i 's/After=database-optimizations.service/After=database-optimizations.service nix-daemon.service/' /etc/systemd/system/postgresql.service
sudo sed -i 's/Requires=database-optimizations.service/Requires=database-optimizations.service nix-daemon.service/' /etc/systemd/system/postgresql.service

print_status "Step 11: Adding Nix environment to PostgreSQL service..."
sudo sed -i '/Environment="LC_ALL=C"/a Environment="NIX_REMOTE=daemon"\nEnvironment="PATH=/nix/var/nix/profiles/default/bin:/var/lib/postgresql/.nix-profile/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' /etc/systemd/system/postgresql.service

print_status "Step 12: Reloading systemd and starting PostgreSQL..."
sudo systemctl daemon-reload
sudo systemctl enable postgresql.service
sudo systemctl start postgresql.service

print_status "Step 13: Verifying PostgreSQL status..."
sleep 5
if sudo systemctl is-active --quiet postgresql; then
    print_status "✅ PostgreSQL is running successfully!"
    sudo systemctl status postgresql --no-pager -l
else
    print_error "❌ PostgreSQL failed to start. Checking logs..."
    sudo journalctl -u postgresql.service --no-pager -l -n 20
    exit 1
fi

print_status "Step 14: Testing PostgreSQL connection..."
if sudo -u postgres /var/lib/postgresql/.nix-profile/bin/psql -c "SELECT version();" > /dev/null 2>&1; then
    print_status "✅ PostgreSQL connection test successful!"
    sudo -u postgres /var/lib/postgresql/.nix-profile/bin/psql -c "SELECT version();"
else
    print_error "❌ PostgreSQL connection test failed"
    exit 1
fi

print_status "🎉 AMI Fix Complete! PostgreSQL is now fully operational."
print_status "You can now use: sudo systemctl start/stop/restart postgresql"
print_status "Connect with: sudo -u postgres psql"