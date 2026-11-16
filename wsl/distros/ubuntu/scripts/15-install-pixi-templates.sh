#!/bin/bash
set -euo pipefail
shopt -s nullglob

: "${TARGET_USER:?TARGET_USER is required}"

# `use pixi <version> <name>` scaffolds pixi.toml from ~/.config/pixi/templates/<name>.toml.
# Ungated, because a template is inert until an .envrc names it, so the opt-in is per-project.
sudo -u "$TARGET_USER" mkdir -p "/home/$TARGET_USER/.config/pixi/templates"

src=/opt/wsl-cloud-init/wsl/user/.config/pixi/templates
files=("$src"/*.toml)
if [[ ${#files[@]} -gt 0 ]]; then
  install -o "$TARGET_USER" -g "$TARGET_USER" -m 644 "${files[@]}" "/home/$TARGET_USER/.config/pixi/templates/"
fi
