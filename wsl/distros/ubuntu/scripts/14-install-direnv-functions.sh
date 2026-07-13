#!/bin/bash
set -euo pipefail
shopt -s nullglob

: "${TARGET_USER:?TARGET_USER is required}"

# direnv functions (per-user), sourced from the sparse checkout declared in
# user-data.template. Idempotent: each run re-installs the current set (install
# overwrites), so re-running can add directives that were skipped before.
sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.config/direnv/lib"

# Runtime directives (fnm, pixi, sdk) always; the claude/ subdir (use_sonarqube_mcp) is
# gated on INSTALL_CLAUDE_CODE since it only makes sense with Claude Code. Both install flat
# into ~/.config/direnv/lib (direnv globs that dir non-recursively), mirroring how
# 13-install-zsh-functions.sh gates its git/ subdir.
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
