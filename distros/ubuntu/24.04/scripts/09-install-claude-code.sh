#!/bin/bash
set -e
source /opt/wsl-cloud-init-config.sh

curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh
sudo -u "$LINUX_USERNAME" bash /tmp/claude-install.sh
rm -f /tmp/claude-install.sh
