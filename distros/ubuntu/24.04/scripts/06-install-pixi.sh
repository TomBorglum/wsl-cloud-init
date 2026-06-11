#!/bin/bash
set -e
source /opt/wsl-cloud-init-config.sh

curl -fsSL https://pixi.sh/install.sh -o /tmp/pixi-install.sh
sudo -u "$LINUX_USERNAME" PIXI_NO_PATH_UPDATE=1 bash /tmp/pixi-install.sh
rm -f /tmp/pixi-install.sh
