#!/bin/bash
set -e
source /opt/wsl-cloud-init-config.sh

curl -fsSL https://fnm.vercel.app/install -o /tmp/fnm-install.sh
sudo -u "$LINUX_USERNAME" bash /tmp/fnm-install.sh --install-dir "/home/$LINUX_USERNAME/.fnm" --skip-shell
rm -f /tmp/fnm-install.sh
