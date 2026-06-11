#!/bin/bash
set -e
source /opt/wsl-cloud-init-config.sh

mkdir -p /usr/local/share/zsh/site-functions
cp /opt/wsl-cloud-init/shared/zsh/*.zsh /usr/local/share/zsh/site-functions/

sudo -u "$LINUX_USERNAME" mkdir -p "/home/$LINUX_USERNAME/.config/direnv/lib"
install -o "$LINUX_USERNAME" -g "$LINUX_USERNAME" -m 644 /opt/wsl-cloud-init/shared/direnv/lib/*.sh "/home/$LINUX_USERNAME/.config/direnv/lib/"
