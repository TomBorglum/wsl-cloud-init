#!/bin/bash
set -euo pipefail

# Shared zsh functions (system-wide)
if ls /usr/local/share/zsh/site-functions/*.zsh >/dev/null 2>&1; then
  echo "shared zsh functions already installed, skipping"
  exit 0
fi

git -C /opt/wsl-cloud-init sparse-checkout add distros/shared/zsh
mkdir -p /usr/local/share/zsh/site-functions
install -m 644 /opt/wsl-cloud-init/distros/shared/zsh/*.zsh /usr/local/share/zsh/site-functions/
