#!/bin/bash
set -euo pipefail

: "${TARGET_USER:?TARGET_USER is required}"

if [[ -x "/home/$TARGET_USER/.pixi/bin/pixi" ]]; then
  echo "pixi already installed for $TARGET_USER, skipping"
  exit 0
fi

curl -fsSL --proto '=https' --tlsv1.2 https://pixi.sh/install.sh -o /tmp/pixi-install.sh
sudo -u "$TARGET_USER" PIXI_NO_PATH_UPDATE=1 bash /tmp/pixi-install.sh
rm -f /tmp/pixi-install.sh
