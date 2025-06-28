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
      "mkdir -p /tmp/ansible-playbook",
      "mkdir -p /tmp/ansible-playbook/nix",
      # FIXED: Proper NVMe device detection and mounting with multiple fallbacks
      <<-EOT
      echo "=== Setting up build volume ==="
      
      # Function to detect and mount build volume
      setup_build_volume() {
        local mounted=false
        
        # Try different device patterns for build volume
        for device in /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/xvdf /dev/sdf; do
          if [ -b "$device" ]; then
            echo "Found build device: $device"
            sudo mkfs.ext4 -F "$device"
            sudo mkdir -p /tmp/nix-build
            sudo mount "$device" /tmp/nix-build
            sudo chmod 777 /tmp/nix-build
            
            # Create swap file on build volume for extra memory
            sudo fallocate -l 4G /tmp/nix-build/swapfile
            sudo chmod 600 /tmp/nix-build/swapfile
            sudo mkswap /tmp/nix-build/swapfile
            sudo swapon /tmp/nix-build/swapfile
            
            echo "Successfully mounted $device to /tmp/nix-build"
            mounted=true
            break
          fi
        done
        
        if [ "$mounted" = false ]; then
          echo "No additional build volume found, using root filesystem"
          sudo mkdir -p /tmp/nix-build
          sudo chmod 777 /tmp/nix-build
        fi
        
        # Show final disk usage
        echo "=== Disk usage after setup ==="
        df -h
        echo "=== Available devices ==="
        lsblk
      }
      
      setup_build_volume
      EOT
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
      # FIXED: Optimized Nix configuration for disk space management
      "NIX_BUILD_CORES=4",
      "TMPDIR=/tmp/nix-build",
      "NIX_BUILD_TOP=/tmp/nix-build"
    ]
    script           = "scripts/nix-provision.sh"
    expect_disconnect = true    # Allow SSH disconnection
    valid_exit_codes  = [0, 2, 2300218]  # Tolerate this specific exit code
  }
}
  
