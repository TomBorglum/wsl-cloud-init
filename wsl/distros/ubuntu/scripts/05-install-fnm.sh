#!/bin/bash
set -euo pipefail

: "${TARGET_USER:?TARGET_USER is required}"

if [[ -x "/home/$TARGET_USER/.fnm/fnm" ]]; then
  echo "fnm already installed for $TARGET_USER, skipping"
  exit 3  # already installed; see install.sh
fi

# The trap is what removes the download: a failure in the install exits before any `rm` would run.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -fsSL --proto '=https' --tlsv1.2 https://fnm.vercel.app/install -o "$tmp"
# mktemp creates the file 0600 owned by root, and the installer below runs as $TARGET_USER.
chown "$TARGET_USER" "$tmp"
sudo -u "$TARGET_USER" bash "$tmp" --install-dir "/home/$TARGET_USER/.fnm" --skip-shell
