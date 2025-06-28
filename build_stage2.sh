#!/bin/bash
set -euo pipefail

# Set required environment variables
export TARGET_REGION="us-east-1"
export CURRENT_GIT_SHA=$(git rev-parse HEAD)
export POSTGRES_MAJOR_TO_BUILD="15"
export PACKER_RUN_ID=$(date +%s)
export TIMESTAMP_S2=$(date +%Y%m%d_%H%M%S)

echo "Building with the following variables:"
echo "TARGET_REGION: ${TARGET_REGION}"
echo "CURRENT_GIT_SHA: ${CURRENT_GIT_SHA}"
echo "POSTGRES_MAJOR_TO_BUILD: ${POSTGRES_MAJOR_TO_BUILD}"
echo "PACKER_RUN_ID: ${PACKER_RUN_ID}"

# Ensure logs directory exists
mkdir -p logs

# Run the packer build
PACKER_LOG=1 packer build \
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
  ./stage2-nix-psql.pkr.hcl 2>&1 | tee "./logs/packer_stage2_build_${TIMESTAMP_S2}.log"