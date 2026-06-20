#!/bin/bash
set -euo pipefail

: "${LINUX_USERNAME:?LINUX_USERNAME is required}"

if [[ -d "/home/$LINUX_USERNAME/.oh-my-zsh" ]]; then
  echo "oh-my-zsh already installed for $LINUX_USERNAME, skipping"
  exit 0
fi

sudo -u "$LINUX_USERNAME" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
sudo -u "$LINUX_USERNAME" git clone https://github.com/zsh-users/zsh-autosuggestions "/home/$LINUX_USERNAME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
