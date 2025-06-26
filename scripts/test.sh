#!/usr/bin/env bash
set -ex  # Exit on error and show commands

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT="$SCRIPT_DIR/.."

echo "=== Creating test file ==="
cat > /tmp/test-flake-eval.nix << 'EOF'
let
  flake = builtins.getFlake (toString ./.);
  system = "aarch64-linux";
in
{
  hasPackages = flake ? packages;
  hasSystem = flake.packages ? ${system};
  psql15Exists = flake.packages.${system} ? psql_15;
  packageNames = if flake.packages ? ${system} 
    then builtins.attrNames flake.packages.${system}
    else [];
}
EOF

echo "=== Test file contents ==="
cat /tmp/test-flake-eval.nix

echo "=== Running evaluation ==="
cd "$PROJECT_ROOT"
nix eval --impure --json -f /tmp/test-flake-eval.nix || {
  echo "Evaluation failed"
  exit 1
}