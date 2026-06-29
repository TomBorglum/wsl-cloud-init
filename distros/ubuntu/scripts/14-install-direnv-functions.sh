#!/bin/bash
set -euo pipefail
shopt -s nullglob

: "${TARGET_USER:?TARGET_USER is required}"

# direnv functions (per-user). Idempotent: each run re-selects the current set and
# install overwrites, so re-running can add directives that were skipped before.
git -C /opt/wsl-cloud-init sparse-checkout add distros/shared/direnv/lib
sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.config/direnv/lib"

# Runtime directives (always); the git/ subdir is gated on INSTALL_GIT_CONFIG.
dirs=(/opt/wsl-cloud-init/distros/shared/direnv/lib)
if [[ "${INSTALL_GIT_CONFIG:-}" == "true" ]]; then
  dirs+=(/opt/wsl-cloud-init/distros/shared/direnv/lib/git)
fi
for dir in "${dirs[@]}"; do
  files=("$dir"/*.sh)
  if [[ ${#files[@]} -gt 0 ]]; then
    install -o "$TARGET_USER" -g "$TARGET_USER" -m 644 "${files[@]}" "/home/$TARGET_USER/.config/direnv/lib/"
  fi
done
