#!/bin/bash
set -e
source /opt/wsl-cloud-init-config.sh

sudo -u "$LINUX_USERNAME" git config --global credential.helper "$GIT_CREDENTIAL_MANAGER"
sudo -u "$LINUX_USERNAME" git config --global user.name "$GIT_NAME"
sudo -u "$LINUX_USERNAME" git config --global user.email "$GIT_EMAIL"
sudo -u "$LINUX_USERNAME" git config --global init.defaultBranch main
