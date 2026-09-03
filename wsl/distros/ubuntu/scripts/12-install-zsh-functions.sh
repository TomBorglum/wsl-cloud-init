#!/bin/bash
set -euo pipefail
shopt -s nullglob

# Shared zsh functions (system-wide), sourced from the sparse checkout declared in
# user-data.template. Idempotent: each run re-installs the current set (install
# overwrites), so re-running can add helpers that were skipped before.
mkdir -p /usr/local/share/zsh/site-functions

# Non-git helpers (always); the git/ subdir is gated on INSTALL_GIT_CONFIG.
src=/opt/wsl-cloud-init/wsl/system/usr/local/share/zsh/site-functions
dirs=("$src")
if [[ "${INSTALL_GIT_CONFIG:-}" == "true" ]]; then
  dirs+=("$src/git")
fi
for dir in "${dirs[@]}"; do
  files=("$dir"/*.zsh)
  if [[ ${#files[@]} -gt 0 ]]; then
    install -m 644 "${files[@]}" /usr/local/share/zsh/site-functions/
  fi
done
