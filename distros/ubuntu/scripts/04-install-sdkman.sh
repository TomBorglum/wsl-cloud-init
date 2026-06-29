#!/bin/bash
set -euo pipefail

: "${TARGET_USER:?TARGET_USER is required}"

if [[ -d "/home/$TARGET_USER/.sdkman" ]]; then
  echo "sdkman already installed for $TARGET_USER, skipping"
  exit 0
fi

curl -fsSL --proto '=https' --tlsv1.2 https://get.sdkman.io -o /tmp/sdkman-install.sh
sudo -u "$TARGET_USER" SDKMAN_DIR="/home/$TARGET_USER/.sdkman" bash /tmp/sdkman-install.sh
rm -f /tmp/sdkman-install.sh
sed -i '/sdkman\|SDKMAN\|THIS MUST BE AT THE END/d' "/home/$TARGET_USER/.zshrc"
