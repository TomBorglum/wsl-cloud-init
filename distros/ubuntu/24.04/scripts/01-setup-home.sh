#!/bin/bash
set -e
source /opt/wsl-cloud-init-config.sh

chown -R "$LINUX_USERNAME:$LINUX_USERNAME" "/home/$LINUX_USERNAME"
sudo -u "$LINUX_USERNAME" mkdir -p "/home/$LINUX_USERNAME/projects"
