#!/bin/bash
set -euo pipefail
shopt -s nullglob

: "${TARGET_USER:?TARGET_USER is required}"

# direnv functions (per-user), sourced from the sparse checkout declared in
# user-data.template. Idempotent: each run re-installs the current set (install
# overwrites), so re-running can add directives that were skipped before.
sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.config/direnv/lib"

# Runtime directives (always); the git/ subdir is gated on INSTALL_GIT_CONFIG.
src=/opt/wsl-cloud-init/wsl/user/.config/direnv/lib
dirs=("$src")
if [[ "${INSTALL_GIT_CONFIG:-}" == "true" ]]; then
  dirs+=("$src/git")
fi
for dir in "${dirs[@]}"; do
  files=("$dir"/*.sh)
  if [[ ${#files[@]} -gt 0 ]]; then
    install -o "$TARGET_USER" -g "$TARGET_USER" -m 644 "${files[@]}" "/home/$TARGET_USER/.config/direnv/lib/"
  fi
done
