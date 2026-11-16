#!/bin/bash
set -euo pipefail
shopt -s nullglob

# Each run re-installs the current set, so a re-run picks up helpers added since
# provisioning.
mkdir -p /usr/local/share/zsh/site-functions

# The git/ subdir is gated on INSTALL_GIT_CONFIG; everything else installs unconditionally.
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
