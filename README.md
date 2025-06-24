```markdown
# ProjectRef PostgreSQL AMI & Tooling

This repository contains the infrastructure-as-code and tooling to build customized Amazon Machine Images (AMIs) for PostgreSQL, along with local development utilities. It leverages HashiCorp Packer for AMI creation and Nix for managing dependencies and building PostgreSQL with a specific set of extensions.

## Purpose

The primary goal is to produce pre-configured, optimized PostgreSQL AMIs tailored for our needs. This includes:

*   **Specific PostgreSQL Versions:** Easily build AMIs for different major PostgreSQL versions (e.g., 15, 17, including variants like OrioleDB).
*   **Curated Extensions:** Bake in a predefined list of common and custom PostgreSQL extensions directly into the image.
*   **Standardized Configuration:** Apply consistent base configurations for PostgreSQL.
*   **Reproducibility:** Use Nix to ensure that the PostgreSQL binaries and their dependencies are built reproducibly.
*   **Automation:** Streamline the AMI creation process using Packer.

This approach simplifies deployment, ensures consistency across environments, and reduces setup time for new PostgreSQL instances.

## Key Components

*   **`flake.nix`:** The heart of the Nix configuration. It defines:
    *   PostgreSQL package derivations for different versions.
    *   The exact set of extensions to be included.
    *   Development shells (`nix develop`) providing all necessary tools.
    *   Nix Apps (`nix run .#appName`) for common tasks like starting a local server or building AMIs.
*   **Packer Configuration Files (`*.pkr.hcl`):**
    *   **Stage 1 (e.g., `amazon-arm64-nix.pkr.hcl`):** Builds a base AMI with Nix installed and essential system configurations. This stage often includes bootstrapping the system and running initial Ansible playbooks.
    *   **Stage 2 (e.g., `stage2-nix-psql.pkr.hcl`):** Takes the Stage 1 AMI as a base, then uses Nix to install the specific PostgreSQL version and extensions, and applies final PostgreSQL configurations.
*   **Ansible Playbooks (`ansible/`):** Used during the Packer build process to configure the instance, install software, and set up PostgreSQL.
*   **Scripts (`scripts/`, `ebssurrogate/scripts/`):** Helper scripts used by Packer provisioners, often for bootstrapping Nix or running Ansible.
*   **Migrations (`migrations/`):** SQL migration scripts for database schema setup.
*   **Nix Overlays and Packages (`nix/`):** Custom Nix expressions for PostgreSQL itself or specific extensions.

## How to Build AMIs

The primary way to build AMIs is using the Nix app defined in `flake.nix`.

**Prerequisites:**

*   [Nix installed](https://nixos.org/download.html) (with Flakes enabled).
*   [Packer installed](https://developer.hashicorp.com/packer/downloads).
*   [AWS CLI installed and configured](https://aws.amazon.com/cli/) with necessary permissions to create EC2 instances, AMIs, etc.
*   `aws-vault` (if you use it for managing AWS credentials).
*   `yq` (for parsing YAML, used by some helper scripts).
*   A `development-arm.vars.pkr.hcl` file in the root directory containing your AWS VPC, subnet, and security group information for Packer to launch builder instances. Example:
    ```hcl
    // development-arm.vars.pkr.hcl
    vpc_id     = "vpc-yourvpcid"
    subnet_id  = "subnet-yoursubnetid"
    security_group_ids = ["sg-yoursecuritygroupid"]
    ```
*   (If cloning private Git repositories during the build) A GitHub Personal Access Token.

**Building (using the provided Nix app):**

The `flake.nix` provides a `build-test-ami` app that orchestrates the two-stage build.

1.  Navigate to the root of this repository.
2.  Execute the build (replace `<profile-name>` and `<pg_major_version>`):
    ```bash
    # If using aws-vault
    aws-vault exec <profile-name> -- nix run .#build-test-ami -- <pg_major_version>

    # If AWS credentials are set via environment variables or default profile
    # nix run .#build-test-ami -- <pg_major_version>
    ```
    For example, to build for PostgreSQL 15:
    ```bash
    aws-vault exec my-dev-profile -- nix run .#build-test-ami -- 15
    ```
    This script will:
    *   Generate a `common-nix.vars.pkr.hcl` file.
    *   Run Packer for Stage 1.
    *   Run Packer for Stage 2, using the AMI from Stage 1.
    *   Optionally run tests.

**Building Manually (Stage by Stage):**

You can also run Packer directly for each stage if you need more control.

**Stage 1:**
(Refer to the Stage 1 Packer HCL file, e.g., `amazon-arm64-nix.pkr.hcl`, and the `build-test-ami` script in `flake.nix` for required variables).
```bash
# Example (variables will need to be set or passed):
export AWS_PROFILE="your-profile"
export TARGET_REGION="us-east-1"
# ... other necessary variables ...

packer init amazon-arm64-nix.pkr.hcl # Or your Stage 1 file
packer build \
  -var "profile=${AWS_PROFILE}" \
  -var "region=${TARGET_REGION}" \
  -var "ami_name=your-base-ami-name" \
  -var "postgres-version=unique-build-id" \
  # ... other -var flags ...
  amazon-arm64-nix.pkr.hcl
```

**Stage 2:**
(Refer to `stage2-nix-psql.pkr.hcl` and the `build-test-ami` script for variables). Stage 2 depends on a successful Stage 1 AMI.
```bash
# Example (variables will need to be set or passed):
export AWS_PROFILE="your-profile"
export TARGET_REGION="us-east-1"
export STAGE1_BUILD_IDENTIFIER="unique-build-id" # Must match 'postgres-version' from Stage 1
export POSTGRES_MAJOR_TO_BUILD="15"
# ... other necessary variables ...

# Ensure common-nix.vars.pkr.hcl and development-arm.vars.pkr.hcl are present

packer init stage2-nix-psql.pkr.hcl
packer build \
  -var "profile=${AWS_PROFILE}" \
  -var "region=${TARGET_REGION}" \
  -var "ami_name=your-final-ami-base-name" \
  -var "postgres-version=${STAGE1_BUILD_IDENTIFIER}" \
  -var "postgres_major_version=${POSTGRES_MAJOR_TO_BUILD}" \
  -var-file="development-arm.vars.pkr.hcl" \
  -var-file="common-nix.vars.pkr.hcl" \
  # ... other -var flags ...
  stage2-nix-psql.pkr.hcl
```
The Stage 2 AMI will be named like `your-final-ami-base-name-unique-build-id`.

## Local Development

Nix Flakes provide a consistent development environment.

1.  **Enter the development shell:**
    ```bash
    nix develop
    ```
    This makes tools like `psql` (from the Nix store), `packer`, `ansible`, `dbmate`, etc., available in your PATH.

2.  **Using Nix Apps for local tasks:**
    *   Start a local PostgreSQL server (PostgreSQL 15 by default):
        ```bash
        nix run .#start-server -- 15
        # For PostgreSQL 17
        # nix run .#start-server -- 17
        ```
    *   Connect to the local server:
        ```bash
        nix run .#start-client -- --version 15
        ```
    *   Run database migrations using `dbmate`:
        ```bash
        nix run .#dbmate-tool -- --version 15
        ```
    *   See all available commands/apps:
        ```bash
        nix run .#show-commands
        # or
        nix flake show
        ```

## Directory Structure Overview

*   `ansible/`: Ansible playbooks, roles, and configuration files.
*   `ebssurrogate/`: Files and scripts specific to the `amazon-ebssurrogate` Packer builder, often used for more complex bootstrapping or chroot operations in Stage 1.
*   `migrations/`: SQL migration files, managed by `dbmate`.
*   `nix/`: Nix expressions for custom packages, PostgreSQL extensions, and development tools.
    *   `ext/`: Nix derivations for individual PostgreSQL extensions.
    *   `tools/`: Scripts made available as Nix apps.
*   `scripts/`: General shell scripts used by Packer provisioners.
*   `*.pkr.hcl`: Packer build template files.
*   `flake.nix` / `flake.lock`: Nix Flake definition and lock file.

---

Feel free to explore the `flake.nix` and Packer HCL files for more detailed insights into the build process and available configurations.
```

**Key things this README covers:**

*   **Clear Purpose:** What the repo is for (building custom PostgreSQL AMIs).
*   **Why it's useful:** Benefits like specific versions, curated extensions, reproducibility.
*   **Core Technologies:** Mentions Packer and Nix.
*   **Key Files/Directories:** Briefly explains `flake.nix`, Packer files, Ansible, etc.
*   **How to Build AMIs:**
    *   Lists prerequisites.
    *   Highlights the primary `nix run .#build-test-ami` method.
    *   Briefly mentions manual stage-by-stage building as an alternative.
*   **Local Development:**
    *   How to enter the Nix dev shell (`nix develop`).
    *   Examples of using Nix apps (`nix run .#app`) for common local tasks.
*   **Simple Directory Overview:** Helps users navigate.
*   **Call to Action:** Encourages exploring specific files for more details.

**To make it even better for *your specific repo*, you might want to customize:**

*   **Replace placeholders:** Like `<profile-name>` or `your-base-ami-name`.
*   **Specific AMI names:** If your Stage 1/2 HCL files have fixed names, mention them.
*   **Prerequisites:** If you have other specific tools not covered by Nix, list them.
*   **Contact/Support:** How to get help or ask questions.
*   **Contributing:** If you want others to contribute.

# Example (variables will need to be set or passed):
export AWS_PROFILE="your-profile"
export TARGET_REGION="us-east-1"
export STAGE1_BUILD_IDENTIFIER="unique-build-id" # Must match 'postgres-version' from Stage 1
export POSTGRES_MAJOR_TO_BUILD="15"
# ... other necessary variables ...

# Ensure common-nix.vars.pkr.hcl and development-arm.vars.pkr.hcl are present

packer init stage2-nix-psql.pkr.hcl
packer build \
  -var "profile=${AWS_PROFILE}" \
  -var "region=${TARGET_REGION}" \
  -var "ami_name=your-final-ami-base-name" \
  -var "postgres-version=${STAGE1_BUILD_IDENTIFIER}" \
  -var "postgres_major_version=${POSTGRES_MAJOR_TO_BUILD}" \
  -var-file="development-arm.vars.pkr.hcl" \
  -var-file="common-nix.vars.pkr.hcl" \
  # ... other -var flags ...
  stage2-nix-psql.pkr.hcl
