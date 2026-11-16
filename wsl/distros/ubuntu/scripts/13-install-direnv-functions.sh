#!/bin/bash
set -euo pipefail
shopt -s nullglob

: "${TARGET_USER:?TARGET_USER is required}"

# Each run re-installs the current set, so a re-run picks up directives added since
# provisioning.
sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.config/direnv/lib"

# The claude/ subdir is gated on INSTALL_CLAUDE_CODE. Both sets install flat into
# ~/.config/direnv/lib, which direnv globs non-recursively.
src=/opt/wsl-cloud-init/wsl/user/.config/direnv/lib
dirs=("$src")
if [[ "${INSTALL_CLAUDE_CODE:-}" == "true" ]]; then
  dirs+=("$src/claude")
fi
for dir in "${dirs[@]}"; do
  files=("$dir"/*.sh)
  if [[ ${#files[@]} -gt 0 ]]; then
    install -o "$TARGET_USER" -g "$TARGET_USER" -m 644 "${files[@]}" "/home/$TARGET_USER/.config/direnv/lib/"
  fi
done
