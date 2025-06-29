variable "profile" {
  type    = string
  default = "${env("AWS_PROFILE")}"
}

variable "ami_regions" {
  type    = list(string)
  default = ["ap-southeast-2"]
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "region" {
  type    = string
}

variable "ami_name" {
  type    = string
  default = "capitala-postgres"
}

variable "postgres-version" {
  type    = string
  default = ""
}

variable "git-head-version" {
  type    = string
  default = "unknown"
}

variable "postgres_major_version" {
  type    = string
  default = "15"
}

variable "git_commit_sha" {
  type    = string
  default = "local"  # Indicates local flake use
}

variable "packer-execution-id" {
  type    = string
  default = "unknown"
}

variable "force-deregister" {
  type    = bool
  default = false
}

variable "git_sha" {
  type    = string
  default = env("GIT_SHA")
}

packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "ubuntu" {
  ami_name      = "${var.ami_name}-${var.postgres-version}"
  instance_type = "c6g.xlarge"
  region        = "${var.region}"
  source_ami_filter {
    filters = {
      name                = "${var.ami_name}-${var.postgres-version}-stage-1"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon", "self"]
  }
  
  communicator = "ssh"
  ssh_pty = true
  ssh_username = "ubuntu"
  ssh_timeout = "15m"
  
  associate_public_ip_address = true

  ena_support = true

  # FIXED: Increased root volume size and added dedicated build volume
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_type           = "gp3"
    volume_size           = 20  # Increased root from 10GB to 20GB
    delete_on_termination = true
  }
  
  # ADDED: Dedicated 60GB build volume for Nix builds
  launch_block_device_mappings {
    device_name           = "/dev/sdf"
    volume_type           = "gp3"
    volume_size           = 60  # Dedicated build space
    delete_on_termination = true
  }
  
  run_tags = {
    creator           = "packer"
    appType           = "postgres"
    packerExecutionId = "${var.packer-execution-id}"
  }
  run_volume_tags = {
    creator = "packer"
    appType = "postgres"
  }
  snapshot_tags = {
    creator = "packer"
    appType = "postgres"
  }
  tags = {
    creator = "packer"
    appType = "postgres"
    postgresVersion = "${var.postgres-version}"
    sourceSha = "${var.git-head-version}"
  }
}

build {
  name = "nix-packer-ubuntu"
  sources = [
    "source.amazon-ebs.ubuntu"
  ]

  provisioner "shell" {
  inline = [
    "echo '=== Diagnostic: All block devices ==='",
    "lsblk -b -o NAME,SIZE,TYPE,MOUNTPOINT",
    "echo '=== Diagnostic: NVMe devices ==='",
    "ls -la /dev/nvme*",
    "echo '=== Diagnostic: Current mounts ==='",
    "mount | grep -E '(ext4|xfs|btrfs)'",
    "echo '=== Diagnostic: Disk usage ==='",
    "df -h",
    "echo '=== Diagnostic: Find large volumes ==='",
    "for dev in /dev/nvme*n1; do",
    "  if [ -b \"$dev\" ]; then",
    "    size_gb=$(lsblk -b -n -o SIZE \"$dev\" 2>/dev/null | awk '{print int($1/1024/1024/1024)}')",
    "    echo \"Device $dev is $${size_gb}GB\"",
    "  fi",
    "done"
  ]
}

  provisioner "shell" {
    inline = [
      "mkdir -p /tmp/ansible-playbook",
      "mkdir -p /tmp/ansible-playbook/nix",
      <<-EOT
      echo "=== Setting up 60GB build volume for Nix ==="
      
      # The 60GB volume is nvme2n1
      DEVICE="/dev/nvme2n1"
      
      if [ -b "$DEVICE" ]; then
        echo "Found 60GB build volume at $DEVICE"
        
        # Check if already mounted
        if mount | grep -q "$DEVICE"; then
          echo "Device $DEVICE is already mounted"
        else
          echo "Formatting and mounting $DEVICE"
          sudo mkfs.ext4 -F "$DEVICE" || { echo "Failed to format"; exit 1; }
          
          # Create mount point
          sudo mkdir -p /nix/var/nix/tmp
          sudo mount "$DEVICE" /nix/var/nix/tmp
          sudo chmod 1777 /nix/var/nix/tmp
          
          # Create subdirectory for builds
          sudo mkdir -p /nix/var/nix/tmp/build
          sudo chmod 1777 /nix/var/nix/tmp/build
          
          # Set up environment variables
          echo 'export TMPDIR=/nix/var/nix/tmp/build' | sudo tee -a /etc/environment
          echo 'export NIX_BUILD_TOP=/nix/var/nix/tmp/build' | sudo tee -a /etc/environment
          
          echo "Successfully mounted 60GB volume to /nix/var/nix/tmp"
        fi
      else
        echo "ERROR: 60GB volume not found at $DEVICE!"
        exit 1
      fi
      
      echo "=== Final disk usage ==="
      df -h
      echo "=== Mount details ==="
      mount | grep nvme
      EOT
    ]
  }

  provisioner "shell" {
  inline = [
    "echo '=== DISK USAGE BEFORE NIX INSTALL ==='",
    "df -h",
    "echo '=== NIX CONFIGURATION ON EC2 ==='", 
    "cat /etc/nix/nix.conf 2>/dev/null || echo 'No nix.conf'",
    "echo '=== NIX DAEMON ENVIRONMENT ==='",
    "sudo -u postgres bash -c '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && env | grep -E \"(TMPDIR|NIX_|BUILD)\"'",
    "echo '=== NIX SHOW CONFIG ON EC2 ==='",
    "sudo -u postgres bash -c '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && nix show-config | grep -E \"(build-dir|max-jobs|cores|store)\"'",
    "echo '=== MOUNT POINTS ==='",
    "mount | grep nvme",
    "echo '=== NIX DIRECTORIES ==='",
    "ls -la /nix/ || echo 'No /nix'",
    "du -sh /nix/* 2>/dev/null || echo 'No nix subdirs'"
  ]
 }

  provisioner "file" {
    source = "ansible"
    destination = "/tmp/ansible-playbook"
  }

  provisioner "file" {
    source = "migrations"
    destination = "/tmp"
  }

  provisioner "file" {
    source = "ebssurrogate/files/unit-tests"
    destination = "/tmp/unit-tests"
  }

  provisioner "file" {
    source = "scripts"
    destination = "/tmp/ansible-playbook"
  }

  provisioner "file" {
    source = "flake.nix"
    destination = "/tmp/ansible-playbook/flake.nix"
  }

  provisioner "file" {
    source = "flake.lock"
    destination = "/tmp/ansible-playbook/flake.lock"
  }

  provisioner "file" {
    source = "nix/"
    destination = "/tmp/ansible-playbook/nix/"
  }
  
  provisioner "shell" {
    environment_vars = [
      "GIT_SHA=${var.git_commit_sha}",
      "POSTGRES_MAJOR_VERSION=${var.postgres_major_version}",
      # Optimized Nix configuration for disk space management
      "NIX_BUILD_CORES=4",
      "_NIX_FORCE_HTTP_BINARY_CACHE_UPDATE=1" 
    ]
    script           = "scripts/nix-provision.sh"
    expect_disconnect = true    # Allow SSH disconnection
    valid_exit_codes  = [0, 2, 2300218]  # Tolerate this specific exit code
  }
}
  
