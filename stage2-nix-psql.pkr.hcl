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
  default = "local"
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

  # Root volume - keep existing size
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
  }
  
  # CRITICAL: 60GB volume for Nix store
  launch_block_device_mappings {
    device_name           = "/dev/sdf"
    volume_type           = "gp3"
    volume_size           = 60
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
      "echo '=== DEFINITIVE FIX: Mount 60GB volume at /nix instead of /nix/store ==='",
      "sudo mkdir -p /nix",
      "sudo mkfs.ext4 -F /dev/nvme2n1",
      "sudo mount /dev/nvme2n1 /nix", 
      "sudo chmod 1775 /nix",
      "sudo mkdir -p /nix/store",
      "sudo chmod 1775 /nix/store",
      "echo '60GB volume mounted at /nix (includes store)'",
      "df -h | grep nvme",
      # Test filesystem operations
      "echo 'test' | sudo tee /tmp/test-file",
      "sudo mkdir -p /nix/test-temp-dir",
      "sudo mv /tmp/test-file /nix/test-temp-dir/",
      "sudo mkdir -p /nix/store/test-final",
      "sudo mv /nix/test-temp-dir/test-file /nix/store/test-final/",
      "sudo rm -rf /nix/test-temp-dir /nix/store/test-final",
      "echo 'Filesystem move test passed'",
      # Prepare directories
      "mkdir -p /tmp/ansible-playbook",
      "rm -rf /tmp/ansible-playbook/nix",
      "mkdir -p /tmp/nix-build"
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

  provisioner "shell" {
  inline = [
    "mkdir -p /tmp/ansible-playbook/nix"
  ]
  }

  provisioner "file" {
    source = "nix/"
    destination = "/tmp/ansible-playbook/nix/"
  }
  
  # FIXED: Enhanced script provisioner with proper exit code handling
  provisioner "shell" {
    environment_vars = [
      "GIT_SHA=${var.git_commit_sha}",
      "POSTGRES_MAJOR_VERSION=${var.postgres_major_version}",
      "NIX_BUILD_CORES=2",
      "_NIX_FORCE_HTTP_BINARY_CACHE_UPDATE=1" 
    ]
    script           = "scripts/nix-provision.sh"
    expect_disconnect = true
    # CRITICAL FIX: Added exit code 141 (SIGPIPE) to valid exit codes
    valid_exit_codes  = [0, 2, 141, 2300218]
    # Additional safeguards
    pause_before      = "5s"
    timeout          = "20m"
  }
}
  
