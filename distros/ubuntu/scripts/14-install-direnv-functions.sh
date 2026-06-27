#!/bin/bash
set -euo pipefail

: "${TARGET_USER:?TARGET_USER is required}"

# direnv functions (per-user)
if ls "/home/$TARGET_USER/.config/direnv/lib/"*.sh >/dev/null 2>&1; then
  echo "direnv functions already installed for $TARGET_USER, skipping"
  exit 0
fi

git -C /opt/wsl-cloud-init sparse-checkout add distros/shared/direnv/lib
sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.config/direnv/lib"
install -o "$TARGET_USER" -g "$TARGET_USER" -m 644 /opt/wsl-cloud-init/distros/shared/direnv/lib/*.sh "/home/$TARGET_USER/.config/direnv/lib/"
