#!/bin/bash
set -euo pipefail

: "${TARGET_USER:?TARGET_USER is required}"

if [[ -d "/home/$TARGET_USER/.sdkman" ]]; then
  echo "sdkman already installed for $TARGET_USER, skipping"
  exit 3  # already installed; see install.sh
fi

# The trap is what removes the download: a failure in the install exits before any `rm` would run.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -fsSL --proto '=https' --tlsv1.2 https://get.sdkman.io -o "$tmp"
# mktemp creates the file 0600 owned by root, and the installer below runs as $TARGET_USER.
chown "$TARGET_USER" "$tmp"
sudo -u "$TARGET_USER" SDKMAN_DIR="/home/$TARGET_USER/.sdkman" bash "$tmp"
sed -i '/sdkman\|SDKMAN\|THIS MUST BE AT THE END/d' "/home/$TARGET_USER/.zshrc"
