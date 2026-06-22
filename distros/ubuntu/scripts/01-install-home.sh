#!/bin/bash
set -euo pipefail

: "${TARGET_USER:?TARGET_USER is required}"

if [[ -d "/home/$TARGET_USER/projects" ]]; then
  echo "home already set up, skipping"
  exit 0
fi

chown -R "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER"
sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/projects"
