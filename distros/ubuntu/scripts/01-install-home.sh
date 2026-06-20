#!/bin/bash
set -euo pipefail

: "${LINUX_USERNAME:?LINUX_USERNAME is required}"

if [[ -d "/home/$LINUX_USERNAME/projects" ]]; then
  echo "home already set up, skipping"
  exit 0
fi

chown -R "$LINUX_USERNAME:$LINUX_USERNAME" "/home/$LINUX_USERNAME"
sudo -u "$LINUX_USERNAME" mkdir -p "/home/$LINUX_USERNAME/projects"
