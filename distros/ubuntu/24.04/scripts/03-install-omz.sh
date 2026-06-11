#!/bin/bash
set -e
source /opt/wsl-cloud-init-config.sh

sudo -u "$LINUX_USERNAME" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
sudo -u "$LINUX_USERNAME" git clone https://github.com/zsh-users/zsh-autosuggestions "/home/$LINUX_USERNAME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
