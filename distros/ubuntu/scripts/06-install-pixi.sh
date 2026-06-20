#!/bin/bash
set -euo pipefail

: "${LINUX_USERNAME:?LINUX_USERNAME is required}"

if [[ -x "/home/$LINUX_USERNAME/.pixi/bin/pixi" ]]; then
  echo "pixi already installed for $LINUX_USERNAME, skipping"
  exit 0
fi

curl -fsSL https://pixi.sh/install.sh -o /tmp/pixi-install.sh
sudo -u "$LINUX_USERNAME" PIXI_NO_PATH_UPDATE=1 bash /tmp/pixi-install.sh
rm -f /tmp/pixi-install.sh
