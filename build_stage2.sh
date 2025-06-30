#!/bin/bash
set -euo pipefail

# Enhanced logging and error handling
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"

# Trap for cleanup
cleanup() {
    local exit_code=$?
    echo "Build script exiting with code: $exit_code"
    if [ $exit_code -ne 0 ]; then
        echo "=== Build failed, checking recent logs ==="
        if [ -f "$LOG_FILE" ]; then
            echo "Last 50 lines of build log:"
            tail -50 "$LOG_FILE"
        fi
    fi
}
trap cleanup EXIT

# Set required environment variables with validation
export TARGET_REGION="${TARGET_REGION:-us-east-1}"
export CURRENT_GIT_SHA=$(git rev-parse HEAD)
export POSTGRES_MAJOR_TO_BUILD="${POSTGRES_MAJOR_TO_BUILD:-15}"
export PACKER_RUN_ID=$(date +%s)
export TIMESTAMP_S2=$(date +%Y%m%d_%H%M%S)
export AWS_PROFILE="${AWS_PROFILE:-capitala}"

# Validate required environment
if [ -z "$AWS_PROFILE" ]; then
    echo "ERROR: AWS_PROFILE must be set"
    exit 1
fi

if ! command -v packer >/dev/null 2>&1; then
    echo "ERROR: Packer not found in PATH"
    exit 1
fi

echo "Building with the following variables:"
echo "TARGET_REGION: ${TARGET_REGION}"
echo "CURRENT_GIT_SHA: ${CURRENT_GIT_SHA}"
echo "POSTGRES_MAJOR_TO_BUILD: ${POSTGRES_MAJOR_TO_BUILD}"
echo "PACKER_RUN_ID: ${PACKER_RUN_ID}"
echo "AWS_PROFILE: ${AWS_PROFILE}"

# Ensure logs directory exists
mkdir -p "$LOG_DIR"

# Define log file
LOG_FILE="${LOG_DIR}/packer_stage2_build_${TIMESTAMP_S2}.log"

# Enhanced packer execution with better error handling
echo "=== Starting Packer build for Stage 2 ==="
echo "Log file: $LOG_FILE"

# Validate that the stage 1 AMI exists
echo "=== Validating Stage 1 AMI exists ==="
STAGE1_AMI_NAME="capitala-project-ami-15.8-stage-1"
if ! aws ec2 describe-images \
    --region "$TARGET_REGION" \
    --owners self \
    --filters "Name=name,Values=$STAGE1_AMI_NAME" \
    --query 'Images[0].ImageId' \
    --output text | grep -q "^ami-"; then
    echo "ERROR: Stage 1 AMI '$STAGE1_AMI_NAME' not found in region $TARGET_REGION"
    echo "Please ensure Stage 1 build completed successfully"
    exit 1
fi

# Initialize packer plugins
echo "=== Initializing Packer plugins ==="
packer init stage2-nix-psql.pkr.hcl

# Validate packer configuration
echo "=== Validating Packer configuration ==="
if ! packer validate \
  -var "profile=${AWS_PROFILE}" \
  -var "region=${TARGET_REGION}" \
  -var "ami_regions=[\"${TARGET_REGION}\"]" \
  -var "ami_name=capitala-project-ami" \
  -var "postgres-version=15.8" \
  -var "git-head-version=${CURRENT_GIT_SHA}" \
  -var "postgres_major_version=${POSTGRES_MAJOR_TO_BUILD}" \
  -var "git_commit_sha=${CURRENT_GIT_SHA}" \
  -var "git_sha=${CURRENT_GIT_SHA}" \
  -var "packer-execution-id=${PACKER_RUN_ID}" \
  -var "force-deregister=true" \
  -var-file="development-arm.vars.pkr.hcl" \
  -var-file="common-nix.vars.pkr.hcl" \
  ./stage2-nix-psql.pkr.hcl; then
    echo "ERROR: Packer configuration validation failed"
    exit 1
fi

# Run the packer build with enhanced logging and error handling
echo "=== Executing Packer build ==="
if ! PACKER_LOG=1 packer build \
  -force \
  -timestamp-ui \
  -var "profile=${AWS_PROFILE}" \
  -var "region=${TARGET_REGION}" \
  -var "ami_regions=[\"${TARGET_REGION}\"]" \
  -var "ami_name=capitala-project-ami" \
  -var "postgres-version=15.8" \
  -var "git-head-version=${CURRENT_GIT_SHA}" \
  -var "postgres_major_version=${POSTGRES_MAJOR_TO_BUILD}" \
  -var "git_commit_sha=${CURRENT_GIT_SHA}" \
  -var "git_sha=${CURRENT_GIT_SHA}" \
  -var "packer-execution-id=${PACKER_RUN_ID}" \
  -var "force-deregister=true" \
  -var-file="development-arm.vars.pkr.hcl" \
  -var-file="common-nix.vars.pkr.hcl" \
  ./stage2-nix-psql.pkr.hcl 2>&1 | tee "$LOG_FILE"; then
    
    # Enhanced error analysis
    echo "ERROR: Packer build failed"
    echo "=== Error Analysis ==="
    
    # Check for common error patterns
    if grep -q "exit status: 141" "$LOG_FILE"; then
        echo "FOUND: Exit code 141 (SIGPIPE) error"
        echo "This typically indicates a pipeline communication issue"
        echo "Check if valid_exit_codes includes 141 in stage2-nix-psql.pkr.hcl"
    fi
    
    if grep -q "SSH handshake" "$LOG_FILE"; then
        echo "FOUND: SSH connection issues"
        echo "This might be related to network connectivity or instance startup"
    fi
    
    if grep -q "No space left on device" "$LOG_FILE"; then
        echo "FOUND: Disk space issues"
        echo "Check disk usage and volume configuration"
    fi
    
    echo "=== Last 100 lines of log ==="
    tail -100 "$LOG_FILE"
    
    exit 1
fi

echo "=== Packer build completed successfully ==="
echo "Log file available at: $LOG_FILE"

# Verify the AMI was created
AMI_NAME="capitala-project-ami-15.8"
echo "=== Verifying AMI creation ==="
if aws ec2 describe-images \
    --region "$TARGET_REGION" \
    --owners self \
    --filters "Name=name,Values=$AMI_NAME" \
    --query 'Images[0].{ImageId:ImageId,State:State,Name:Name}' \
    --output table; then
    echo "SUCCESS: AMI created successfully"
else
    echo "WARNING: Could not verify AMI creation"
fi

echo "=== Stage 2 build completed ==="

# #!/bin/bash
# set -euo pipefail

# # Set required environment variables
# export TARGET_REGION="us-east-1"
# export CURRENT_GIT_SHA=$(git rev-parse HEAD)
# export POSTGRES_MAJOR_TO_BUILD="15"
# export PACKER_RUN_ID=$(date +%s)
# export TIMESTAMP_S2=$(date +%Y%m%d_%H%M%S)
# export AWS_PROFILE="capitala"

# echo "Building with the following variables:"
# echo "TARGET_REGION: ${TARGET_REGION}"
# echo "CURRENT_GIT_SHA: ${CURRENT_GIT_SHA}"
# echo "POSTGRES_MAJOR_TO_BUILD: ${POSTGRES_MAJOR_TO_BUILD}"
# echo "PACKER_RUN_ID: ${PACKER_RUN_ID}"

# # Ensure logs directory exists
# mkdir -p logs

# # Run the packer build
# PACKER_LOG=1 packer build \
#   -force \
#   -timestamp-ui \
#   -var "profile=${AWS_PROFILE}" \
#   -var "region=${TARGET_REGION}" \
#   -var "ami_regions=[\"${TARGET_REGION}\"]" \
#   -var "ami_name=capitala-project-ami" \
#   -var "postgres-version=15.8" \
#   -var "git-head-version=${CURRENT_GIT_SHA}" \
#   -var "postgres_major_version=${POSTGRES_MAJOR_TO_BUILD}" \
#   -var "git_commit_sha=${CURRENT_GIT_SHA}" \
#   -var "git_sha=${CURRENT_GIT_SHA}" \
#   -var "packer-execution-id=${PACKER_RUN_ID}" \
#   -var "force-deregister=true" \
#   -var-file="development-arm.vars.pkr.hcl" \
#   -var-file="common-nix.vars.pkr.hcl" \
#   ./stage2-nix-psql.pkr.hcl 2>&1 | tee "./logs/packer_stage2_build_${TIMESTAMP_S2}.log"