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
        "mkdir -p /tmp/ansible-playbook/nix"
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
      "NIX_BUILD_TOP=/tmp/nix-build",
      "_NIX_FORCE_HTTP_BINARY_CACHE_UPDATE=1" 
    ]
    script           = "scripts/nix-provision.sh"
    expect_disconnect = true    # Allow SSH disconnection
    valid_exit_codes  = [0, 2, 2300218]  # Tolerate this specific exit code
  }
}
  
