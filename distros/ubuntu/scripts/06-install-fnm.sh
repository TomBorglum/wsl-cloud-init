#!/bin/bash
set -euo pipefail

: "${TARGET_USER:?TARGET_USER is required}"

if [[ -x "/home/$TARGET_USER/.fnm/fnm" ]]; then
  echo "fnm already installed for $TARGET_USER, skipping"
  exit 0
fi

curl -fsSL --proto '=https' --tlsv1.2 https://fnm.vercel.app/install -o /tmp/fnm-install.sh
sudo -u "$TARGET_USER" bash /tmp/fnm-install.sh --install-dir "/home/$TARGET_USER/.fnm" --skip-shell
rm -f /tmp/fnm-install.sh
