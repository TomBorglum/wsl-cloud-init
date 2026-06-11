#!/bin/bash
set -e
source /opt/wsl-cloud-init-config.sh

curl -s https://get.sdkman.io -o /tmp/sdkman-install.sh
sudo -u "$LINUX_USERNAME" SDKMAN_DIR="/home/$LINUX_USERNAME/.sdkman" bash /tmp/sdkman-install.sh
rm -f /tmp/sdkman-install.sh
sed -i '/sdkman\|SDKMAN\|THIS MUST BE AT THE END/d' "/home/$LINUX_USERNAME/.zshrc"
