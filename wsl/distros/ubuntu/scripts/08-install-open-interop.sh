#!/bin/bash
set -euo pipefail

if command -v open >/dev/null 2>&1; then
  echo "open already installed, skipping"
  exit 0
fi

: "${TARGET_USER:?TARGET_USER is required}"

# The wrapper is a real file under wsl/system (provided by the sparse checkout declared in
# user-data.template), installed (idempotent overwrite) with the executable bit. It reads
# $POWERSHELL from the environment at runtime (exported from ~/.zshenv, derived once in
# install.sh) rather than baking the path in.
install -D -m 755 /opt/wsl-cloud-init/wsl/system/usr/local/bin/open /usr/local/bin/open

sudo -u "$TARGET_USER" tee -a "/home/$TARGET_USER/.zshenv" > /dev/null << 'EOF'
export BROWSER=open
EOF
