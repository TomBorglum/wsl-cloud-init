#!/bin/bash
set -euo pipefail

: "${TARGET_USER:?TARGET_USER is required}"

# Shared zsh functions (system-wide)
if ls /usr/local/share/zsh/site-functions/*.zsh >/dev/null 2>&1; then
  echo "shared zsh functions already installed, skipping"
else
  mkdir -p /usr/local/share/zsh/site-functions
  install -m 644 /opt/wsl-cloud-init/distros/shared/zsh/*.zsh /usr/local/share/zsh/site-functions/
fi

# direnv libs (per-user)
if ls "/home/$TARGET_USER/.config/direnv/lib/"*.sh >/dev/null 2>&1; then
  echo "direnv libs already installed for $TARGET_USER, skipping"
else
  sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.config/direnv/lib"
  install -o "$TARGET_USER" -g "$TARGET_USER" -m 644 /opt/wsl-cloud-init/distros/shared/direnv/lib/*.sh "/home/$TARGET_USER/.config/direnv/lib/"
fi

# Claude skills (per-user); cp -r since this is a directory tree, not flat files
if [[ -n "$(ls -A "/home/$TARGET_USER/.claude/skills" 2>/dev/null)" ]]; then
  echo "claude skills already installed for $TARGET_USER, skipping"
else
  sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.claude/skills"
  sudo -u "$TARGET_USER" cp -r /opt/wsl-cloud-init/distros/shared/claude/skills/. "/home/$TARGET_USER/.claude/skills/"
fi
