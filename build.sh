#!/bin/bash

# Create a logs directory in your project root if it doesn't exist
# mkdir -p ./logs

# # Get current timestamp
# TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# # Run packer build and capture all output
# packer build -force -timestamp-ui \
#   --var "ami_name=capitala" \
#   --var "region=us-east-1" \
#   --var 'ami_regions=["us-east-1"]' \
#   --var 'postgres-version=15.3' \
#   --var 'postgres_major_version=15' \
#   stage2-nix-psql.pkr.hcl 2>&1 | tee "./logs/packer_build_${TIMESTAMP}.log"

#!/bin/bash

# Create a logs directory in your project root if it doesn't exist
mkdir -p ./logs

# Get current timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Set Git commit SHA for nix packages
# GIT_COMMIT_SHA="a7189a68ed4ea78c1e73991b5f271043636cf074"

# Run packer build and capture all output
PACKER_LOG=1 packer build \
  -force \
  -timestamp-ui \
  -var "ami_name=capitala" \
  -var "region=us-east-1" \
  -var 'ami_regions=["us-east-1"]' \
  -var "postgres-version=15.3" \
  -var "postgres_major_version=15" \
  -var "git_commit_sha=${GIT_COMMIT_SHA}" \
  ./stage2-nix-psql.pkr.hcl 2>&1 | tee "./logs/packer_build_${TIMESTAMP}.log"

exit_code=${PIPESTATUS[0]}
if [ $exit_code -ne 0 ]; then
    echo "Build failed with exit code $exit_code"
    exit $exit_code
fi