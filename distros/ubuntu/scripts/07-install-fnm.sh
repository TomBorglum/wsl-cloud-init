#!/bin/bash
set -euo pipefail

: "${LINUX_USERNAME:?LINUX_USERNAME is required}"

if [[ -x "/home/$LINUX_USERNAME/.fnm/fnm" ]]; then
  echo "fnm already installed for $LINUX_USERNAME, skipping"
  exit 0
fi

curl -fsSL https://fnm.vercel.app/install -o /tmp/fnm-install.sh
sudo -u "$LINUX_USERNAME" bash /tmp/fnm-install.sh --install-dir "/home/$LINUX_USERNAME/.fnm" --skip-shell
rm -f /tmp/fnm-install.sh
