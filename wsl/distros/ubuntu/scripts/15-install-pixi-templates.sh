#!/bin/bash
set -euo pipefail
shopt -s nullglob

: "${TARGET_USER:?TARGET_USER is required}"

# pixi project templates (per-user), sourced from the sparse checkout declared in
# user-data.template. The `use pixi <name>` direnv directive scaffolds pixi.toml from
# ~/.config/pixi/templates/<name>.toml. Ungated: the templates are inert until a user
# names one in an .envrc, so the opt-in is per-project, not per-install. Idempotent:
# each run re-installs the current set (install overwrites).
sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.config/pixi/templates"

src=/opt/wsl-cloud-init/wsl/user/.config/pixi/templates
files=("$src"/*.toml)
if [[ ${#files[@]} -gt 0 ]]; then
  install -o "$TARGET_USER" -g "$TARGET_USER" -m 644 "${files[@]}" "/home/$TARGET_USER/.config/pixi/templates/"
fi
