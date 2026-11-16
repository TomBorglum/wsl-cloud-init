#!/bin/bash
set -euo pipefail

if command -v open >/dev/null 2>&1; then
  echo "open already installed, skipping"
  exit 3  # already installed; see install.sh
fi

: "${TARGET_USER:?TARGET_USER is required}"

# The wrapper reads $POWERSHELL from the environment at runtime rather than baking the path in.
install -D -m 755 /opt/wsl-cloud-init/wsl/system/usr/local/bin/open /usr/local/bin/open

sudo -u "$TARGET_USER" tee -a "/home/$TARGET_USER/.zshenv" > /dev/null << 'EOF'
export BROWSER=open
EOF
