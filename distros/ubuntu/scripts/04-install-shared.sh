#!/bin/bash
set -euo pipefail

: "${LINUX_USERNAME:?LINUX_USERNAME is required}"

# Shared zsh functions (system-wide)
if ls /usr/local/share/zsh/site-functions/*.zsh >/dev/null 2>&1; then
  echo "shared zsh functions already installed, skipping"
else
  mkdir -p /usr/local/share/zsh/site-functions
  cp /opt/wsl-cloud-init/shared/zsh/*.zsh /usr/local/share/zsh/site-functions/
fi

# direnv libs (per-user)
if ls "/home/$LINUX_USERNAME/.config/direnv/lib/"*.sh >/dev/null 2>&1; then
  echo "direnv libs already installed for $LINUX_USERNAME, skipping"
else
  sudo -u "$LINUX_USERNAME" mkdir -p "/home/$LINUX_USERNAME/.config/direnv/lib"
  install -o "$LINUX_USERNAME" -g "$LINUX_USERNAME" -m 644 \
    /opt/wsl-cloud-init/shared/direnv/lib/*.sh \
    "/home/$LINUX_USERNAME/.config/direnv/lib/"
fi

# Claude skills (per-user)
if [[ -n "$(ls -A "/home/$LINUX_USERNAME/.claude/skills" 2>/dev/null)" ]]; then
  echo "claude skills already installed for $LINUX_USERNAME, skipping"
else
  sudo -u "$LINUX_USERNAME" mkdir -p "/home/$LINUX_USERNAME/.claude/skills"
  sudo -u "$LINUX_USERNAME" cp -r /opt/wsl-cloud-init/shared/claude/skills/. \
    "/home/$LINUX_USERNAME/.claude/skills/"
fi
