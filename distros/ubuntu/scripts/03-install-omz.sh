#!/bin/bash
set -euo pipefail

: "${TARGET_USER:?TARGET_USER is required}"

if [[ -d "/home/$TARGET_USER/.oh-my-zsh" ]]; then
  echo "oh-my-zsh already installed for $TARGET_USER, skipping"
  exit 0
fi

sudo -u "$TARGET_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
sudo -u "$TARGET_USER" git clone https://github.com/zsh-users/zsh-autosuggestions "/home/$TARGET_USER/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
