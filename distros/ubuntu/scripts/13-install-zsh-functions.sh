#!/bin/bash
set -euo pipefail
shopt -s nullglob

# Shared zsh functions (system-wide). Idempotent: each run re-selects the current
# set and install overwrites, so re-running can add helpers that were skipped before.
git -C /opt/wsl-cloud-init sparse-checkout add distros/shared/zsh
mkdir -p /usr/local/share/zsh/site-functions

# Non-git helpers (always); the git/ subdir is gated on INSTALL_GIT_CONFIG.
dirs=(/opt/wsl-cloud-init/distros/shared/zsh)
if [[ "${INSTALL_GIT_CONFIG:-}" == "true" ]]; then
  dirs+=(/opt/wsl-cloud-init/distros/shared/zsh/git)
fi
for dir in "${dirs[@]}"; do
  files=("$dir"/*.zsh)
  [[ ${#files[@]} -gt 0 ]] && install -m 644 "${files[@]}" /usr/local/share/zsh/site-functions/
done
