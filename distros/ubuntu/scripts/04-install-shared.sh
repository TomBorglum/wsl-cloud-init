#!/bin/bash
set -euo pipefail

: "${TARGET_USER:?TARGET_USER is required}"

# Claude skills (per-user); cp -r since this is a directory tree, not flat files
if [[ -n "$(ls -A "/home/$TARGET_USER/.claude/skills" 2>/dev/null)" ]]; then
  echo "claude skills already installed for $TARGET_USER, skipping"
else
  sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.claude/skills"
  sudo -u "$TARGET_USER" cp -r /opt/wsl-cloud-init/distros/shared/claude/skills/. "/home/$TARGET_USER/.claude/skills/"
fi
