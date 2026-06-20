#!/bin/bash
set -euo pipefail

: "${LINUX_USERNAME:?LINUX_USERNAME is required}"

if [[ -d "/home/$LINUX_USERNAME/.sdkman" ]]; then
  echo "sdkman already installed for $LINUX_USERNAME, skipping"
  exit 0
fi

curl -fsSL https://get.sdkman.io -o /tmp/sdkman-install.sh
sudo -u "$LINUX_USERNAME" SDKMAN_DIR="/home/$LINUX_USERNAME/.sdkman" bash /tmp/sdkman-install.sh
rm -f /tmp/sdkman-install.sh
sed -i '/sdkman\|SDKMAN\|THIS MUST BE AT THE END/d' "/home/$LINUX_USERNAME/.zshrc"
