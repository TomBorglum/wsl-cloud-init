#!/bin/bash
set -euo pipefail

if command -v open >/dev/null 2>&1; then
  echo "open already installed, skipping"
  exit 0
fi

: "${TARGET_USER:?TARGET_USER is required}"

# The wrapper is a real file under wsl/system, installed (idempotent overwrite) with the
# executable bit; sparse-checkout add makes it available in the /opt checkout at install.
# It reads $POWERSHELL from the environment at runtime (exported from ~/.zshenv, derived
# once in install.sh) rather than baking the path in.
git -C /opt/wsl-cloud-init sparse-checkout add wsl/system/usr/local/bin >/dev/null
install -D -m 755 /opt/wsl-cloud-init/wsl/system/usr/local/bin/open /usr/local/bin/open

sudo -u "$TARGET_USER" tee -a "/home/$TARGET_USER/.zshenv" > /dev/null << 'EOF'
export BROWSER=open
EOF
